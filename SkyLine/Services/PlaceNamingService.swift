//
//  PlaceNamingService.swift
//  SkyLine
//
//  Reverse geocoding + nearby-POI naming for cluster centroids.
//
//  API STATUS — verified, not assumed:
//    CLGeocoder is deprecated as of iOS 26.0. Verified in the iOS 26.0 SDK:
//      CLGeocoder.h:23  API_DEPRECATED("Use MapKit", ios(5.0, 26.0), ...)
//      CLGeocoder.h:33  reverseGeocodeLocation:completionHandler:
//                       API_DEPRECATED("Use MKReverseGeocodingRequest", ios(5.0, 26.0), ...)
//
//    MKReverseGeocodingRequest signature verified against
//    MapKit.framework/Headers/MKReverseGeocodingRequest.h in the iOS 26.0 SDK
//    and confirmed by typechecking this file with
//    `swiftc -typecheck -target arm64-apple-ios26.0`:
//      - (nullable instancetype)initWithLocation:(CLLocation *)location;
//          → failable in Swift: MKReverseGeocodingRequest(location:) -> Self?
//      @property (nonatomic, nullable, strong) NSLocale *preferredLocale;
//      - (void)getMapItemsWithCompletionHandler:(...)
//              NS_SWIFT_ASYNC_NAME(getter:mapItems());
//          → in Swift this is `var mapItems: [MKMapItem] { get async throws }`,
//            i.e. `try await request.mapItems`. NOT a method call.
//      The async getter is NONISOLATED (the NS_SWIFT_UI_ACTOR annotation is on
//      the completion block, not the async form), and MKMapItem is not Sendable —
//      which is why every call below happens inside a nonisolated function that
//      extracts plain Strings/Doubles before anything crosses back.
//
//    Also note the Swift refinements, which are compile errors if you get them
//    wrong: MKLocalSearchRequest → MKLocalSearch.Request,
//    MKLocalSearchResponse → MKLocalSearch.Response,
//    MKPointsOfInterestRequestMaxRadius → MKLocalPointsOfInterestRequest.maxRadius.
//
//  ⚠️ NOT VERIFIED AT RUNTIME: whether MKReverseGeocodingRequest returns
//  point-of-interest map items or only address-level ones for a given
//  coordinate. Apple documents it as returning `[MKMapItem]` without promising
//  POIs. That uncertainty is the reason the POI lookup below is an INDEPENDENT
//  second stage built on MKLocalSearch rather than a filter over the
//  reverse-geocode results — if reverse geocoding turns out to be
//  address-only, naming still produces restaurant names.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Resolved Name

/// Sendable value type. Nothing MapKit ever escapes this file.
struct ResolvedPlaceName: Codable, Hashable, Sendable {
    let name: String
    let category: String?       // MKPointOfInterestCategory.rawValue
    let locality: String?       // city
    let isFallbackCoordinate: Bool
}

// MARK: - Naming Service

/// An `actor` so requests serialise for free. MapKit's geocoding throttle is
/// undocumented and server-side; hammering it returns errors that look like
/// "no result", which would silently degrade every name on a busy trip.
/// One request at a time plus a floor on the interval keeps us well inside it.
actor PlaceNamingService {

    // MARK: - Configuration

    struct Configuration: Sendable {
        /// Minimum wall-clock gap between outbound MapKit requests.
        var minimumRequestInterval: TimeInterval = 0.6
        /// Attempts per cluster before giving up and using coordinates.
        var maxAttempts: Int = 3
        /// Base delay for exponential backoff on failure.
        var retryBaseDelay: TimeInterval = 1.0
        /// POI search radius floor/ceiling. Scaled by cluster spread so a park
        /// searches wider than a bar.
        var minimumSearchRadius: CLLocationDistance = 80
        var maximumSearchRadius: CLLocationDistance = 400
        /// Cache grid precision. 4 dp ≈ 11 m — tight enough that two genuinely
        /// different places never collide, loose enough that re-running
        /// detection on the same trip is a pure cache hit.
        var cacheCoordinatePrecision: Int = 4
        var cacheValidityInterval: TimeInterval = 90 * 24 * 3600   // 90 days

        static let `default` = Configuration()
    }

    // MARK: - Properties

    static let shared = PlaceNamingService()

    private let configuration: Configuration
    private var lastRequestAt: Date = .distantPast
    private var cache: [String: CachedName] = [:]
    private let cacheURL: URL

    /// Categories that are never what the user means by "a place I went".
    private static let excludedCategories: [MKPointOfInterestCategory] = [
        .atm, .parking, .restroom, .evCharger, .gasStation, .mailbox,
        .police, .fireStation, .carRental
    ]

    private struct CachedName: Codable {
        let resolved: ResolvedPlaceName
        let fetchedAt: Date
        func isValid(_ interval: TimeInterval) -> Bool {
            Date().timeIntervalSince(fetchedAt) < interval
        }
    }

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        // Caches directory, matching RouteCache — this is regenerable data and
        // must not consume the user's iCloud backup allowance.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheURL = caches.appendingPathComponent("place_names_cache.json")
        // Loaded synchronously via a nonisolated static: calling an
        // actor-isolated method from a non-isolated init is an error in Swift 6.
        self.cache = Self.loadCache(from: cacheURL, validity: configuration.cacheValidityInterval)
    }

    // MARK: - Public API

    /// Names a cluster centroid. Never throws and never returns nil: on total
    /// failure it degrades to a formatted coordinate, because a card reading
    /// "35.6693, 139.6975" is still swipeable and a card reading nothing is not.
    func resolveName(
        latitude: Double,
        longitude: Double,
        spreadMeters: Double = 0
    ) async -> ResolvedPlaceName {
        let key = cacheKey(latitude: latitude, longitude: longitude)
        if let cached = cache[key], cached.isValid(configuration.cacheValidityInterval) {
            return cached.resolved
        }

        let radius = min(
            max(spreadMeters + 60, configuration.minimumSearchRadius),
            configuration.maximumSearchRadius
        )

        var resolved: ResolvedPlaceName?
        var attempt = 0

        while attempt < configuration.maxAttempts && resolved == nil {
            attempt += 1
            await throttle()
            resolved = await Self.lookup(
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                excluding: Self.excludedCategories
            )
            if resolved == nil && attempt < configuration.maxAttempts {
                let delay = configuration.retryBaseDelay * pow(2, Double(attempt - 1))
                print("⚠️ PlaceNaming: Attempt \(attempt) failed, backing off \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        let final = resolved ?? ResolvedPlaceName(
            name: Self.formatCoordinate(latitude: latitude, longitude: longitude),
            category: nil,
            locality: nil,
            isFallbackCoordinate: true
        )

        if !final.isFallbackCoordinate {
            cache[key] = CachedName(resolved: final, fetchedAt: Date())
            saveCache()
            print("✅ PlaceNaming: \(final.name)")
        } else {
            // Never cache a failure — the next run should retry.
            print("⚠️ PlaceNaming: Falling back to coordinates for \(latitude), \(longitude)")
        }
        return final
    }

    /// Searches POIs around a coordinate. Used by the destination-suggestion
    /// fallback and by the manual "add a place" field.
    func searchPlaces(
        near latitude: Double,
        longitude: Double,
        query: String? = nil,
        radius: CLLocationDistance = 1500,
        limit: Int = 20
    ) async -> [ResolvedPlaceName] {
        await throttle()
        return await Self.search(
            latitude: latitude,
            longitude: longitude,
            query: query,
            radius: radius,
            limit: limit,
            excluding: Self.excludedCategories
        )
    }

    /// Forward-geocodes a destination string when a `Trip` has no coordinate.
    /// Uses MKGeocodingRequest — CLGeocoder.geocodeAddressString is deprecated
    /// in iOS 26.0 with the replacement named explicitly in the header
    /// (CLGeocoder.h:44: API_DEPRECATED("Use MKGeocodingRequest", ...)).
    func geocode(destination: String) async -> CLLocationCoordinate2D? {
        await throttle()
        return await Self.forwardGeocode(destination)
    }

    // MARK: - Throttle

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        let wait = configuration.minimumRequestInterval - elapsed
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestAt = Date()
    }

    // MARK: - MapKit Calls
    //
    // These are `nonisolated static` on purpose: MKMapItem and
    // MKReverseGeocodingRequest are not Sendable, so they must be created AND
    // consumed inside one non-isolated async scope. Only the Sendable
    // ResolvedPlaceName crosses back to the actor.

    private nonisolated static func lookup(
        latitude: Double,
        longitude: Double,
        radius: CLLocationDistance,
        excluding: [MKPointOfInterestCategory]
    ) async -> ResolvedPlaceName? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        // Stage A — reverse geocode. Gives us the city and, possibly, a POI.
        var locality: String?
        var addressName: String?
        var reverseBest: ResolvedPlaceName?

        // Failable init: returns nil for an invalid coordinate.
        if let request = MKReverseGeocodingRequest(location: location) {
            request.preferredLocale = Locale.current
            do {
                // NS_SWIFT_ASYNC_NAME(getter:mapItems()) → async throws property.
                let items = try await request.mapItems
                for item in items {
                    if locality == nil {
                        locality = item.addressRepresentations?.cityName
                    }
                    if addressName == nil {
                        addressName = item.address?.shortAddress ?? item.address?.fullAddress
                    }
                    // A named item WITH a POI category is a real venue, not a
                    // street address. That is what we actually want on a card.
                    if reverseBest == nil,
                       let name = item.name, !name.isEmpty,
                       let category = item.pointOfInterestCategory,
                       !excluding.contains(category) {
                        reverseBest = ResolvedPlaceName(
                            name: name,
                            category: category.rawValue,
                            locality: item.addressRepresentations?.cityName,
                            isFallbackCoordinate: false
                        )
                    }
                }
            } catch {
                print("⚠️ PlaceNaming: Reverse geocode failed — \(error.localizedDescription)")
            }
        }

        if let reverseBest { return reverseBest }

        // Stage B — explicit nearby-POI search. Independent of Stage A, so
        // naming still works if reverse geocoding only ever returns addresses.
        let poiRequest = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(excluding: excluding)
        do {
            let response = try await MKLocalSearch(request: poiRequest).start()
            let scored = response.mapItems.compactMap { item -> (String, String?, Double)? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let d = GeoMath.distance(
                    lat1: latitude, lng1: longitude,
                    lat2: item.location.coordinate.latitude,
                    lng2: item.location.coordinate.longitude
                )
                return (name, item.pointOfInterestCategory?.rawValue, d)
            }
            // Nearest to the photo-weighted centroid wins. The centroid is the
            // best estimate of where the user actually stood.
            if let best = scored.min(by: { $0.2 < $1.2 }) {
                return ResolvedPlaceName(
                    name: best.0,
                    category: best.1,
                    locality: locality,
                    isFallbackCoordinate: false
                )
            }
        } catch {
            print("⚠️ PlaceNaming: POI search failed — \(error.localizedDescription)")
        }

        // Stage C — a street address beats coordinates.
        if let addressName, !addressName.isEmpty {
            return ResolvedPlaceName(name: addressName, category: nil, locality: locality, isFallbackCoordinate: false)
        }
        // Stage D — the city alone beats coordinates.
        if let locality, !locality.isEmpty {
            return ResolvedPlaceName(name: locality, category: nil, locality: locality, isFallbackCoordinate: false)
        }
        return nil
    }

    private nonisolated static func search(
        latitude: Double,
        longitude: Double,
        query: String?,
        radius: CLLocationDistance,
        limit: Int,
        excluding: [MKPointOfInterestCategory]
    ) async -> [ResolvedPlaceName] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)

        do {
            let response: MKLocalSearch.Response
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = region
                request.resultTypes = [.pointOfInterest, .address]
                response = try await MKLocalSearch(request: request).start()
            } else {
                let request = MKLocalPointsOfInterestRequest(center: center, radius: min(radius, MKLocalPointsOfInterestRequest.maxRadius))
                request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: excluding)
                response = try await MKLocalSearch(request: request).start()
            }

            return response.mapItems.prefix(limit).compactMap { item in
                guard let name = item.name, !name.isEmpty else { return nil }
                return ResolvedPlaceName(
                    name: name,
                    category: item.pointOfInterestCategory?.rawValue,
                    locality: item.addressRepresentations?.cityName,
                    isFallbackCoordinate: false
                )
            }
        } catch {
            print("❌ PlaceNaming: Search failed — \(error.localizedDescription)")
            return []
        }
    }

    private nonisolated static func forwardGeocode(_ address: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        request.preferredLocale = Locale.current
        do {
            let items = try await request.mapItems
            guard let first = items.first else { return nil }
            let c = first.location.coordinate
            return CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        } catch {
            print("⚠️ PlaceNaming: Forward geocode of '\(address)' failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Formatting

    private nonisolated static func formatCoordinate(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    // MARK: - Cache

    private func cacheKey(latitude: Double, longitude: Double) -> String {
        let p = pow(10.0, Double(configuration.cacheCoordinatePrecision))
        return "\((latitude * p).rounded() / p),\((longitude * p).rounded() / p)"
    }

    private nonisolated static func loadCache(from url: URL, validity: TimeInterval) -> [String: CachedName] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CachedName].self, from: data) else { return [:] }
        let valid = decoded.filter { $0.value.isValid(validity) }
        print("💾 PlaceNaming: Loaded \(valid.count) cached names")
        return valid
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    func clearCache() {
        cache = [:]
        try? FileManager.default.removeItem(at: cacheURL)
        print("💾 PlaceNaming: Cache cleared")
    }
}
