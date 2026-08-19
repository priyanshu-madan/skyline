//
//  PlaceQueries.swift
//  SkyLine
//
//  Rollups and grouping helpers over Place + Visit
//

import Foundation
import CoreLocation

// MARK: - Place Summary
/// A place plus everything the UI needs to render one row: how many times you
/// went, when, and what you decided.
struct PlaceSummary: Identifiable, Hashable {
    let place: Place
    let visitCount: Int
    let firstVisitDate: Date?
    let lastVisitDate: Date?
    /// Most recent explicit verdict. `nil` = never rated.
    let verdict: Verdict?
    let verdictCounts: [Verdict: Int]

    var id: String { place.id }
    var isRated: Bool { verdict != nil }

    var visitCountText: String {
        visitCount == 1 ? "1 visit" : "\(visitCount) visits"
    }

    var lastVisitText: String {
        guard let lastVisitDate = lastVisitDate else { return "No visits yet" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: lastVisitDate)
    }

    init(place: Place, visits: [Visit]) {
        self.place = place
        self.visitCount = visits.count
        self.firstVisitDate = visits.earliest()?.date
        self.lastVisitDate = visits.mostRecent()?.date
        self.verdict = visits.currentVerdict()
        self.verdictCounts = visits.verdictCounts()
    }
}

// MARK: - Country Group
struct PlaceCountryGroup: Identifiable, Hashable {
    let countryName: String
    let countryCode: String?
    let summaries: [PlaceSummary]

    var id: String { countryCode ?? countryName }
    var placeCount: Int { summaries.count }
    var visitCount: Int { summaries.reduce(0) { $0 + $1.visitCount } }
    var worthItCount: Int { summaries.filter { $0.verdict == .worthIt }.count }

    var lastVisitDate: Date? {
        summaries.compactMap { $0.lastVisitDate }.max()
    }
}

// MARK: - Globe Payload
/// One dot on the globe. Field names mirror the existing `visitedCities` /
/// `tripLocations` payloads in `WebViewGlobeView.updateGlobeDataWithTab`, so a
/// new `window.updatePlaceData(...)` layer can consume it unchanged.
struct PlaceGlobePoint: Identifiable, Hashable {
    let placeId: String
    let name: String
    let latitude: Double
    let longitude: Double
    let verdict: Verdict?
    let visitCount: Int
    let lastVisited: Date?
    let country: String?
    let category: PlaceCategory

    var id: String { placeId }

    var colorHex: String { Verdict.globeHexColor(for: verdict) }

    /// JSON-serializable dictionary, matching the app's existing bridge style
    /// (`JSONSerialization` over `[[String: Any]]`, then string interpolation).
    var jsonObject: [String: Any] {
        [
            "lat": latitude,
            "lng": longitude,
            "name": name,
            "color": colorHex,
            "placeId": placeId,
            "verdict": verdict?.rawValue ?? "unrated",
            "category": category.rawValue,
            "country": country ?? "",
            "visitCount": visitCount,
            "lastVisited": lastVisited?.timeIntervalSince1970 ?? 0
        ]
    }

    static func jsonString(from points: [PlaceGlobePoint]) -> String {
        let objects = points.map { $0.jsonObject }
        guard let data = try? JSONSerialization.data(withJSONObject: objects),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

// MARK: - Store Queries
extension PlaceStore {

    // MARK: Lookups

    func place(by id: String) -> Place? {
        places.first { $0.id == id }
    }

    func visit(by id: String) -> Visit? {
        visits.first { $0.id == id }
    }

    func visits(for placeId: String) -> [Visit] {
        visitsByPlaceId[placeId] ?? []
    }

    func visitCount(for placeId: String) -> Int {
        visitsByPlaceId[placeId]?.count ?? 0
    }

    func mostRecentVisit(for placeId: String) -> Visit? {
        visitsByPlaceId[placeId]?.first // index is stored newest-first
    }

    /// The verdict shown on the map for a place: most recent explicit verdict.
    func verdict(for placeId: String) -> Verdict? {
        visits(for: placeId).currentVerdict()
    }

    func summary(for placeId: String) -> PlaceSummary? {
        guard let place = place(by: placeId) else { return nil }
        return PlaceSummary(place: place, visits: visits(for: placeId))
    }

    // MARK: Rollups

    /// Every place with its visit rollup, most recently visited first.
    var placeSummaries: [PlaceSummary] {
        places
            .map { PlaceSummary(place: $0, visits: visits(for: $0.id)) }
            .sorted { lhs, rhs in
                switch (lhs.lastVisitDate, rhs.lastVisitDate) {
                case let (left?, right?): return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.place.name < rhs.place.name
                }
            }
    }

    func places(with verdict: Verdict) -> [PlaceSummary] {
        placeSummaries.filter { $0.verdict == verdict }
    }

    var unratedSummaries: [PlaceSummary] {
        placeSummaries.filter { $0.verdict == nil }
    }

    /// Verdict -> places, best-first. Unrated places are excluded.
    var placesByVerdict: [Verdict: [PlaceSummary]] {
        var grouped: [Verdict: [PlaceSummary]] = [:]
        for summary in placeSummaries {
            guard let verdict = summary.verdict else { continue }
            grouped[verdict, default: []].append(summary)
        }
        return grouped
    }

    /// Countries, most places first. Places with no country land in "Unknown".
    var placesByCountry: [PlaceCountryGroup] {
        let grouped = Dictionary(grouping: placeSummaries) { summary -> String in
            let country = summary.place.country ?? ""
            return country.isEmpty ? "Unknown" : country
        }

        return grouped
            .map { countryName, summaries in
                PlaceCountryGroup(
                    countryName: countryName,
                    countryCode: summaries.compactMap { $0.place.countryCode }.first,
                    summaries: summaries
                )
            }
            .sorted { lhs, rhs in
                if lhs.placeCount != rhs.placeCount { return lhs.placeCount > rhs.placeCount }
                return lhs.countryName < rhs.countryName
            }
    }

    var countryCount: Int {
        Set(places.compactMap { place -> String? in
            guard let country = place.country, !country.isEmpty else { return nil }
            return country
        }).count
    }

    var ratedVisitCount: Int {
        visits.filter { $0.isRated }.count
    }

    var worthItCount: Int {
        placeSummaries.filter { $0.verdict == .worthIt }.count
    }

    var mostRecentVisit: Visit? {
        visits.mostRecent()
    }

    /// Places you keep going back to.
    func mostVisitedPlaces(limit: Int = 10) -> [PlaceSummary] {
        placeSummaries
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Trip Scoping

    func visits(forTrip tripId: String) -> [Visit] {
        visits.filter { $0.tripId == tripId }.sortedByDateDescending()
    }

    func places(forTrip tripId: String) -> [PlaceSummary] {
        let placeIds = Set(visits(forTrip: tripId).map { $0.placeId })
        return placeSummaries.filter { placeIds.contains($0.place.id) }
    }

    // MARK: Search

    func searchPlaces(_ query: String) -> [PlaceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return placeSummaries }
        return placeSummaries.filter { summary in
            summary.place.name.localizedCaseInsensitiveContains(trimmed) ||
            (summary.place.city?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
            (summary.place.country?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    func placesNear(_ coordinate: CLLocationCoordinate2D, within radius: CLLocationDistance = 500) -> [Place] {
        places
            .filter { $0.distance(to: coordinate) <= radius }
            .sorted { $0.distance(to: coordinate) < $1.distance(to: coordinate) }
    }

    // MARK: Globe

    /// Coordinates + verdict per place - everything the globe layer needs.
    var globePoints: [PlaceGlobePoint] {
        placeSummaries.compactMap { summary in
            guard summary.place.hasValidCoordinate else { return nil }
            return PlaceGlobePoint(
                placeId: summary.place.id,
                name: summary.place.name,
                latitude: summary.place.latitude,
                longitude: summary.place.longitude,
                verdict: summary.verdict,
                visitCount: summary.visitCount,
                lastVisited: summary.lastVisitDate,
                country: summary.place.country,
                category: summary.place.category
            )
        }
    }

    var globePointsJSON: String {
        PlaceGlobePoint.jsonString(from: globePoints)
    }

    /// Cheap change-detection string, matching the hash-then-debounce pattern
    /// `WebViewGlobeView` already uses before pushing data into the WebView.
    var globePointsHash: String {
        globePoints
            .map { "\($0.placeId):\($0.verdict?.rawValue ?? "-"):\($0.visitCount)" }
            .joined(separator: "|")
    }
}
