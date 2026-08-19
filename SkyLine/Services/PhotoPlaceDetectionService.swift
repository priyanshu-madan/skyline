//
//  PhotoPlaceDetectionService.swift
//  SkyLine
//
//  Orchestrates authorization → fetch → cluster → name, with a fallback ladder
//  that guarantees the swipe deck is never empty.
//

import Foundation
import Photos
import CoreLocation
import MapKit
import Combine

// MARK: - Errors

enum PhotoPlaceDetectionError: LocalizedError {
    case accessDenied
    case accessNotDetermined
    case cancelled

    var errorDescription: String? {
        switch self {
        case .accessDenied:        return "SkyLine needs access to your photos to find the places you went"
        case .accessNotDetermined: return "Photo access has not been requested yet"
        case .cancelled:           return "Place detection was cancelled"
        }
    }
}

// MARK: - Progress

enum PlaceDetectionPhase: String, Sendable {
    case idle
    case requestingAccess
    case fetchingPhotos
    case clustering
    case namingPlaces
    case finished
}

// MARK: - Service

@MainActor
final class PhotoPlaceDetectionService: ObservableObject {

    // MARK: - Properties

    static let shared = PhotoPlaceDetectionService()

    @Published private(set) var phase: PlaceDetectionPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published var isLoading = false
    @Published var error: String?

    private let fetcher: PhotoAssetFetcher
    private let clusterer: PlaceClusterer
    private let namingService: PlaceNamingService
    private let authorization = PhotoLibraryAuthorizationService.shared

    private init(
        fetcher: PhotoAssetFetcher = PhotoAssetFetcher(),
        clusterer: PlaceClusterer = PlaceClusterer(),
        namingService: PlaceNamingService = PlaceNamingService.shared
    ) {
        self.fetcher = fetcher
        self.clusterer = clusterer
        self.namingService = namingService
    }

    // MARK: - Entry Point

    /// Detects the places a trip's photos describe.
    ///
    /// THE FALLBACK LADDER — this method never returns an empty deck when the
    /// trip has a destination, and never returns "sorry, nothing found":
    ///
    ///   Tier 1  .photoGPS               geotagged photos → spatial clusters.
    ///   Tier 2  .photoTimeOnly          photos exist but none are geotagged.
    ///                                   Cluster by TIME, hand each session a
    ///                                   representative photo, and ask "where
    ///                                   was this?" instead of "list your places".
    ///   Tier 3  .destinationSuggestion  no usable photos at all. POIs around
    ///                                   the trip destination, offered as
    ///                                   "did you go here?".
    ///   Tier 4  .manual                 always available in the UI as a search
    ///                                   field; not produced here.
    ///
    /// Tier 2 is the one that matters. A large share of users have Camera
    /// location turned off, and for them a GPS-only design shows a blank page —
    /// which kills the product on first run. But the photos still carry two
    /// things: WHEN, and WHAT IT LOOKED LIKE. So the question we put to the
    /// user changes from recall ("where did you go on this trip?", a blank
    /// page, genuinely hard) to recognition ("here's a photo from Tuesday
    /// 2pm — where was this?", easy, and answerable in one tap from a nearby-POI
    /// list). Recognition over recall is the entire reason the no-GPS path is
    /// workable rather than a consolation prize.
    func detectPlaces(for trip: Trip) async -> Result<PlaceDetectionResult, PhotoPlaceDetectionError> {
        isLoading = true
        error = nil
        phase = .requestingAccess
        progress = 0
        defer {
            isLoading = false
            phase = .finished
            progress = 1
        }

        // MARK: Authorization
        let access = await authorization.requestAccess()
        guard access == .full || access == .limited else {
            self.error = PhotoPlaceDetectionError.accessDenied.errorDescription
            print("❌ PlaceDetection: Access \(access.rawValue) — falling back to destination suggestions")
            // Even denied is not a dead end: suggest POIs around the destination.
            let fallback = await destinationSuggestions(for: trip)
            var diagnostics = PlaceDetectionDiagnostics()
            diagnostics.isLimitedLibraryAccess = false
            return .success(PlaceDetectionResult(places: fallback, source: .destinationSuggestion, diagnostics: diagnostics))
        }

        var diagnostics = PlaceDetectionDiagnostics()
        diagnostics.isLimitedLibraryAccess = (access == .limited)

        // MARK: Fetch
        phase = .fetchingPhotos
        progress = 0.1
        let outcome = await fetcher.fetchPoints(start: trip.startDate, end: trip.endDate)
        diagnostics.assetsInDateRange = outcome.totalInRange
        diagnostics.assetsWithLocation = outcome.located.count
        diagnostics.assetsWithLocationRecoveredFromEXIF = outcome.recoveredFromEXIF
        diagnostics.screenshotsExcluded = outcome.screenshotsExcluded

        if Task.isCancelled { return .failure(.cancelled) }

        // MARK: Tier 1 — GPS clustering
        phase = .clustering
        progress = 0.3
        let clusters = clusterer.cluster(points: outcome.points)
        diagnostics.clustersBeforeTrim = clusters.count
        diagnostics.clustersDroppedAsOutliers = clusterer.outlierCount(points: outcome.points)

        if clusters.count >= 2 {
            phase = .namingPlaces
            let places = await nameClusters(clusters, tripId: trip.id, diagnostics: &diagnostics)
            print("✅ PlaceDetection: \(places.count) places from photo GPS")
            return .success(PlaceDetectionResult(places: places, source: .photoGPS, diagnostics: diagnostics))
        }

        // MARK: Tier 2 — time-only clustering
        if outcome.points.count >= 3 {
            print("⚠️ PlaceDetection: \(diagnostics.assetsWithLocation)/\(diagnostics.assetsInDateRange) photos geotagged — using time-only clustering")
            progress = 0.6
            let sessions = clusterer.segmentByTimeOnly(points: outcome.points)
            if !sessions.isEmpty {
                let pointsByID = Dictionary(uniqueKeysWithValues: outcome.points.map { ($0.id, $0) })
                let timeZone = trip.destinationTimeZone
                let places = sessions.prefix(clusterer.configuration.maxPlaces).map { visit -> DetectedPlace in
                    let sessionPoints = visit.assetIdentifiers.compactMap { pointsByID[$0] }
                    return DetectedPlace(
                        tripId: trip.id,
                        // No invented name. The card shows the photo and the
                        // time, and the name field is the thing the user fills.
                        name: Self.sessionPlaceholderName(for: visit, in: timeZone),
                        latitude: nil,
                        longitude: nil,
                        category: nil,
                        visits: [visit],
                        representativeAssetIdentifier: clusterer.pickRepresentative(from: sessionPoints)?.id,
                        allAssetIdentifiers: visit.assetIdentifiers,
                        source: .photoTimeOnly,
                        significance: clusterer.significance(for: [visit])
                    )
                }
                print("✅ PlaceDetection: \(places.count) time-only sessions awaiting a location")
                return .success(PlaceDetectionResult(places: Array(places), source: .photoTimeOnly, diagnostics: diagnostics))
            }
        }

        // MARK: Tier 3 — destination suggestions
        print("⚠️ PlaceDetection: No usable photos — falling back to destination suggestions")
        progress = 0.8
        let suggestions = await destinationSuggestions(for: trip)
        return .success(PlaceDetectionResult(places: suggestions, source: .destinationSuggestion, diagnostics: diagnostics))
    }

    // MARK: - Category Suppression

    /// Categories that are never a "place you went" even when the clustering
    /// is perfectly correct.
    ///
    /// This exists because DISTANCE CANNOT CATCH AN AIRPORT. Narita is 64 km
    /// from central Tokyo — well inside any outlier radius loose enough to
    /// allow a legitimate day trip, and measured as such: the fixture's
    /// airport cluster survives distance rejection every time. The only
    /// reliable signal that a stay was an airport is the resolved POI
    /// category, which is why this filter runs AFTER naming rather than
    /// during clustering.
    ///
    /// Airports are also guaranteed to cluster well — you are there for hours
    /// and you photograph things — so without this the top card on almost
    /// every trip is the departure terminal.
    private static let suppressedCategories: Set<String> = [
        MKPointOfInterestCategory.airport.rawValue
    ]

    // MARK: - Naming

    private func nameClusters(
        _ clusters: [PlaceCluster],
        tripId: String,
        diagnostics: inout PlaceDetectionDiagnostics
    ) async -> [DetectedPlace] {
        var places: [DetectedPlace] = []
        var successes = 0
        var failures = 0

        // Sequential, not a TaskGroup: PlaceNamingService is an actor that
        // serialises anyway, and firing a group at it would only queue inside
        // the actor while making progress reporting meaningless.
        for (index, cluster) in clusters.enumerated() {
            if Task.isCancelled { break }
            let resolved = await namingService.resolveName(
                latitude: cluster.latitude,
                longitude: cluster.longitude,
                spreadMeters: cluster.spreadMeters
            )
            if resolved.isFallbackCoordinate { failures += 1 } else { successes += 1 }

            if let category = resolved.category, Self.suppressedCategories.contains(category) {
                print("🔄 PlaceDetection: Suppressing \(resolved.name) (category \(category))")
                progress = 0.3 + 0.7 * (Double(index + 1) / Double(clusters.count))
                continue
            }

            places.append(
                DetectedPlace(
                    id: cluster.id,
                    tripId: tripId,
                    name: resolved.name,
                    latitude: cluster.latitude,
                    longitude: cluster.longitude,
                    category: resolved.category,
                    visits: cluster.visits,
                    representativeAssetIdentifier: cluster.representativeAssetIdentifier,
                    allAssetIdentifiers: cluster.allAssetIdentifiers,
                    source: .photoGPS,
                    significance: cluster.significance
                )
            )
            progress = 0.3 + 0.7 * (Double(index + 1) / Double(clusters.count))
        }

        diagnostics.geocodeSuccesses = successes
        diagnostics.geocodeFailures = failures
        return places
    }

    // MARK: - Tier 3 Fallback

    /// POIs around the trip destination, offered as "did you go here?".
    /// This is the floor of the ladder: as long as a trip has a destination
    /// string, there is something on screen.
    private func destinationSuggestions(for trip: Trip) async -> [DetectedPlace] {
        var coordinate = trip.coordinate
        if coordinate == nil {
            // Trip has no stored coordinate — forward-geocode the destination.
            coordinate = await namingService.geocode(destination: trip.destination)
        }
        guard let coordinate else {
            print("⚠️ PlaceDetection: No coordinate for '\(trip.destination)' — manual entry only")
            return []
        }

        let results = await namingService.searchPlaces(
            near: coordinate.latitude,
            longitude: coordinate.longitude,
            query: nil,
            radius: 2000,
            limit: 12
        )

        return results.map { resolved in
            DetectedPlace(
                tripId: trip.id,
                name: resolved.name,
                latitude: nil,          // unconfirmed — the user has not said they went
                longitude: nil,
                category: resolved.category,
                visits: [],
                representativeAssetIdentifier: nil,
                allAssetIdentifiers: [],
                source: .destinationSuggestion,
                significance: 0
            )
        }
    }

    // MARK: - Helpers

    /// "Tuesday afternoon" — a time label, never a fake place name. The card
    /// must not imply the app knows something it does not.
    private static func sessionPlaceholderName(for visit: PhotoVisitSession, in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: visit.startDate)

        let hour = calendar.component(.hour, from: visit.startDate)
        let partOfDay: String
        switch hour {
        case 0..<5:   partOfDay = "night"
        case 5..<12:  partOfDay = "morning"
        case 12..<17: partOfDay = "afternoon"
        case 17..<21: partOfDay = "evening"
        default:      partOfDay = "night"
        }
        return "\(day) \(partOfDay)"
    }
}
