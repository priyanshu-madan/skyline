//
//  CountryLocator.swift
//  SkyLine
//
//  Resolves a coordinate to a country, entirely offline.
//
//  The place log groups by country, so a place with no country falls into an
//  "Unknown" bucket and the header reports zero countries no matter how many
//  places exist. Neither of the two import paths could supply one: places
//  derived from a Flight had only an IATA code, and places derived from a Trip
//  inherited `trip.country`, which is nil for every trip created through the
//  map picker.
//
//  Reverse geocoding would answer this, but it is a network round trip per
//  place, rate limited, and wrong to run in a loop over an import of hundreds.
//  countries.geojson is already in the bundle for the globe's country layer, so
//  the answer is available locally - the globe has been doing this in
//  JavaScript all along.
//

import Foundation
import CoreLocation

// MARK: - Country Locator

/// Point-in-polygon country lookup backed by the bundled Natural Earth data.
///
/// Loads lazily on first use and holds ~177 country outlines in memory. Lookups
/// are read-only after that, so the type is safe to call from any context once
/// warmed.
final class CountryLocator: @unchecked Sendable {

    static let shared = CountryLocator()

    struct Country: Hashable {
        let name: String        // English display name, e.g. "Japan"
        let code: String        // ISO 3166-1 alpha-2, e.g. "JP"
    }

    /// One country's outline plus a precomputed bounding box. The bounding box
    /// is the whole performance story: rejecting a country costs four
    /// comparisons instead of walking a 4,000-vertex ring, which is what makes
    /// this usable inside an import loop.
    private struct Outline {
        let country: Country
        let rings: [[[Double]]]     // polygon rings: [ring][vertex][lon, lat]
        let minLat, maxLat, minLon, maxLon: Double
    }

    private var outlines: [Outline] = []
    private var isLoaded = false
    private let lock = NSLock()

    private init() {}

    // MARK: - Lookup

    /// The country containing this coordinate, or nil over open water or where
    /// the data has no matching polygon.
    func country(at coordinate: CLLocationCoordinate2D) -> Country? {
        country(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func country(latitude: Double, longitude: Double) -> Country? {
        loadIfNeeded()

        guard latitude.isFinite, longitude.isFinite,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else {
            return nil
        }

        for outline in outlines {
            guard latitude >= outline.minLat, latitude <= outline.maxLat,
                  longitude >= outline.minLon, longitude <= outline.maxLon else {
                continue
            }
            if contains(latitude: latitude, longitude: longitude, rings: outline.rings) {
                return outline.country
            }
        }
        return nil
    }

    /// Warms the dataset off the main thread. Worth calling before an import so
    /// the first lookup does not pay the parse cost inline.
    func preload() {
        Task.detached(priority: .utility) { [weak self] in
            self?.loadIfNeeded()
        }
    }

    // MARK: - Geometry

    /// Ray casting. `rings[0]` is the outer ring; any further rings are holes,
    /// so a point inside a hole is outside the country - which matters for real
    /// enclaves such as Lesotho inside South Africa.
    private func contains(latitude: Double, longitude: Double, rings: [[[Double]]]) -> Bool {
        guard let outer = rings.first, isInside(latitude, longitude, ring: outer) else {
            return false
        }
        for hole in rings.dropFirst() where isInside(latitude, longitude, ring: hole) {
            return false
        }
        return true
    }

    private func isInside(_ lat: Double, _ lon: Double, ring: [[Double]]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            guard ring[i].count >= 2, ring[j].count >= 2 else { j = i; continue }
            let xi = ring[i][0], yi = ring[i][1]
            let xj = ring[j][0], yj = ring[j][1]

            if (yi > lat) != (yj > lat) {
                let denominator = yj - yi
                if denominator != 0 {
                    let intersectX = (xj - xi) * (lat - yi) / denominator + xi
                    if lon < intersectX { inside.toggle() }
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "countries", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            print("⚠️ CountryLocator: countries.geojson unavailable - country lookup disabled")
            return
        }

        var built: [Outline] = []
        built.reserveCapacity(features.count)

        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }

            // NAME_EN is the English exonym ("Tanzania"); ADMIN is the formal
            // name ("United Republic of Tanzania"). A place list wants the
            // former.
            let name = (properties["NAME_EN"] as? String)
                ?? (properties["ADMIN"] as? String)
                ?? (properties["NAME"] as? String)

            // Natural Earth writes "-99" rather than null for disputed or
            // unassigned codes; ISO_A2_EH resolves several of those.
            let rawCode = (properties["ISO_A2"] as? String).flatMap { $0 == "-99" ? nil : $0 }
                ?? (properties["ISO_A2_EH"] as? String).flatMap { $0 == "-99" ? nil : $0 }

            guard let name, let rawCode, rawCode.count == 2 else { continue }
            let country = Country(name: name, code: rawCode.uppercased())

            var polygons: [[[[Double]]]] = []
            if type == "Polygon", let rings = geometry["coordinates"] as? [[[Double]]] {
                polygons = [rings]
            } else if type == "MultiPolygon", let multi = geometry["coordinates"] as? [[[[Double]]]] {
                polygons = multi
            }

            for rings in polygons {
                guard let outer = rings.first, !outer.isEmpty else { continue }
                var minLat = Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
                var minLon = Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
                for vertex in outer where vertex.count >= 2 {
                    minLon = min(minLon, vertex[0]); maxLon = max(maxLon, vertex[0])
                    minLat = min(minLat, vertex[1]); maxLat = max(maxLat, vertex[1])
                }
                guard minLat <= maxLat, minLon <= maxLon else { continue }
                built.append(Outline(country: country, rings: rings,
                                     minLat: minLat, maxLat: maxLat,
                                     minLon: minLon, maxLon: maxLon))
            }
        }

        // Smallest bounding box first: an enclave is tested before the country
        // that surrounds it, so Vatican City wins over Italy.
        outlines = built.sorted {
            (($0.maxLat - $0.minLat) * ($0.maxLon - $0.minLon))
                < (($1.maxLat - $1.minLat) * ($1.maxLon - $1.minLon))
        }
        print("🌍 CountryLocator: loaded \(outlines.count) country outlines")
    }
}

// MARK: - String Helper

extension String {
    /// `nil` when the string is empty or only whitespace.
    ///
    /// Optional-coalescing does not fire on `""`, so a blank stored value would
    /// otherwise win over a correctly resolved one and show as "Unknown".
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
