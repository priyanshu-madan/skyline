//
//  RouteCache.swift
//  SkyLine
//
//  Route caching service to persist fetched routes and avoid repeated API calls
//

import Foundation
import CoreLocation

// MARK: - Cached Route Model
struct CachedRoute: Codable {
    let startEntryId: String
    let endEntryId: String
    let coordinates: [CachedCoordinate]
    let startColor: String
    let endColor: String
    let fetchedAt: Date

    // Cache validity period (7 days)
    var isValid: Bool {
        Date().timeIntervalSince(fetchedAt) < 7 * 24 * 60 * 60
    }
}

struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(from coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - Route Cache Manager
@MainActor
class RouteCache {
    static let shared = RouteCache()

    private let cacheURL: URL
    private var cache: [String: CachedRoute] = [:]

    private init() {
        // Get app's cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = cacheDir.appendingPathComponent("route_cache.json")

        loadCache()
    }

    // MARK: - Public Methods

    /// Get cached route for a segment
    func getRoute(from startId: String, to endId: String) -> CachedRoute? {
        let key = cacheKey(from: startId, to: endId)

        guard let cached = cache[key], cached.isValid else {
            // Remove expired cache
            cache.removeValue(forKey: key)
            return nil
        }

        return cached
    }

    /// Save route to cache
    func saveRoute(
        from startId: String,
        to endId: String,
        coordinates: [CLLocationCoordinate2D],
        startColor: String,
        endColor: String
    ) {
        let key = cacheKey(from: startId, to: endId)

        let cached = CachedRoute(
            startEntryId: startId,
            endEntryId: endId,
            coordinates: coordinates.map { CachedCoordinate(from: $0) },
            startColor: startColor,
            endColor: endColor,
            fetchedAt: Date()
        )

        cache[key] = cached
        saveCache()
    }

    /// Clear all cached routes
    func clearCache() {
        cache.removeAll()
        saveCache()
    }

    /// Clear cache for specific trip
    func clearCache(for tripId: String) {
        // Remove all routes that might belong to this trip
        // (we don't store tripId in cache, so we can't filter precisely)
        // This is called when trip entries are modified
        cache.removeAll()
        saveCache()
    }

    /// Clear expired routes
    func clearExpiredRoutes() {
        let expiredKeys = cache.filter { !$0.value.isValid }.map { $0.key }
        expiredKeys.forEach { cache.removeValue(forKey: $0) }

        if !expiredKeys.isEmpty {
            saveCache()
            print("🗑️ Cleared \(expiredKeys.count) expired routes from cache")
        }
    }

    // MARK: - Private Methods

    private func cacheKey(from startId: String, to endId: String) -> String {
        return "\(startId)->\(endId)"
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            print("📦 No route cache found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            cache = try JSONDecoder().decode([String: CachedRoute].self, from: data)

            // Clear expired routes on load
            clearExpiredRoutes()

            print("✅ Loaded \(cache.count) cached routes from disk")
        } catch {
            print("⚠️ Failed to load route cache: \(error.localizedDescription)")
            cache = [:]
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            print("💾 Saved \(cache.count) routes to cache")
        } catch {
            print("⚠️ Failed to save route cache: \(error.localizedDescription)")
        }
    }
}
