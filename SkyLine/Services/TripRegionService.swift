//
//  TripRegionService.swift
//  SkyLine
//
//  AI-powered region detection and grouping for trips
//

import Foundation
import CoreLocation

class TripRegionService {
    static let shared = TripRegionService()

    private init() {}

    // MARK: - Region Detection

    /// Detect logical regions from trip entries using multi-heuristic approach
    /// Combines geographic clustering, location name parsing, and temporal analysis
    func detectRegions(for entries: [TripEntry], trip: Trip) async -> [(regionName: String, entries: [TripEntry])] {
        guard !entries.isEmpty else { return [] }

        // Sort entries chronologically
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }

        // Filter entries with locations
        let entriesWithLocations = sortedEntries.filter { $0.hasLocation }

        // If very few entries, create single region
        if entriesWithLocations.count < 3 {
            let regionName = await suggestRegionName(for: sortedEntries, fallback: trip.destination)
            return [(regionName, sortedEntries)]
        }

        // Perform geographic clustering
        let clusters = performGeographicClustering(entries: entriesWithLocations)

        // Assign names to clusters
        var regionGroups: [(String, [TripEntry])] = []

        for (index, cluster) in clusters.enumerated() {
            let regionName = await suggestRegionName(for: cluster, fallback: "Region \(index + 1)")

            // Include entries without locations that fall within this cluster's time range
            let clusterStartTime = cluster.map { $0.timestamp }.min() ?? Date()
            let clusterEndTime = cluster.map { $0.timestamp }.max() ?? Date()

            let entriesInTimeRange = sortedEntries.filter { entry in
                entry.timestamp >= clusterStartTime && entry.timestamp <= clusterEndTime
            }

            regionGroups.append((regionName, entriesInTimeRange))
        }

        return regionGroups
    }

    // MARK: - Geographic Clustering

    /// Cluster entries by geographic proximity using distance threshold
    private func performGeographicClustering(entries: [TripEntry]) -> [[TripEntry]] {
        guard !entries.isEmpty else { return [] }

        let distanceThreshold: CLLocationDistance = 50000 // 50km
        var clusters: [[TripEntry]] = []
        var currentCluster: [TripEntry] = []
        var lastLocation: CLLocationCoordinate2D?

        for entry in entries {
            guard let entryCoord = entry.coordinate else { continue }

            if let lastCoord = lastLocation {
                let distance = calculateDistance(from: lastCoord, to: entryCoord)

                // Check temporal gap - multi-day break suggests new region
                let timeSinceLastEntry = entry.timestamp.timeIntervalSince(currentCluster.last?.timestamp ?? entry.timestamp)
                let hasLongBreak = timeSinceLastEntry > 86400 // 24 hours

                // Start new cluster if distance is large OR there's a long temporal break
                if distance > distanceThreshold || (hasLongBreak && distance > 10000) {
                    if !currentCluster.isEmpty {
                        clusters.append(currentCluster)
                    }
                    currentCluster = [entry]
                } else {
                    currentCluster.append(entry)
                }
            } else {
                // First entry
                currentCluster = [entry]
            }

            lastLocation = entryCoord
        }

        // Add final cluster
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters.isEmpty ? [entries] : clusters
    }

    /// Calculate distance between two coordinates
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    // MARK: - Region Naming

    /// Suggest a semantic name for a region based on entry locations
    func suggestRegionName(for entries: [TripEntry], fallback: String = "Unknown Region") async -> String {
        // Strategy 1: Extract city/area from location names
        if let extractedName = extractRegionFromLocationNames(entries) {
            return extractedName
        }

        // Strategy 2: Use reverse geocoding for coordinates
        if let geoCodedName = await reverseGeocodeRegion(for: entries) {
            return geoCodedName
        }

        // Fallback
        return fallback
    }

    /// Extract common region/city name from locationName strings
    private func extractRegionFromLocationNames(_ entries: [TripEntry]) -> String? {
        let locationNames = entries.compactMap { $0.locationName }
        guard !locationNames.isEmpty else { return nil }

        // Parse location names for common patterns
        // Format examples: "Shibuya, Tokyo", "Big Sur, California", "Santa Barbara"
        var cityNames: [String: Int] = [:]

        for locationName in locationNames {
            // Split by comma and take last component (usually city)
            let components = locationName.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            if components.count >= 2 {
                // Use second-to-last component (city/area before country)
                let city = components[components.count - 2]
                cityNames[city, default: 0] += 1
            } else if let first = components.first, !first.isEmpty {
                // Single component - use as-is
                cityNames[first, default: 0] += 1
            }
        }

        // Return most common city name
        return cityNames.max(by: { $0.value < $1.value })?.key
    }

    /// Use reverse geocoding to get city name from coordinates
    private func reverseGeocodeRegion(for entries: [TripEntry]) async -> String? {
        // Get the first entry with coordinates
        guard let firstEntry = entries.first(where: { $0.hasLocation }),
              let coordinate = firstEntry.coordinate else {
            return nil
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)

            if let placemark = placemarks.first {
                // Prefer locality (city) over administrative area (state)
                if let city = placemark.locality {
                    return city
                } else if let area = placemark.administrativeArea {
                    return area
                } else if let country = placemark.country {
                    return country
                }
            }
        } catch {
            print("⚠️ Reverse geocoding failed: \(error)")
        }

        return nil
    }

    // MARK: - Entry Assignment

    /// Assign regions to entries and return updated entries.
    /// Resolves at the day level so all entries on the same calendar day
    /// receive the same region — no day can appear in two region sections.
    func assignRegionsToEntries(_ entries: [TripEntry], regions: [(String, [TripEntry])]) -> [TripEntry] {
        let cal = Calendar.current

        // Step 1: Build initial per-entry region from the detection results
        var regionByEntryId: [String: (name: String, order: Int)] = [:]
        for (regionOrder, (regionName, regionEntries)) in regions.enumerated() {
            for entry in regionEntries {
                regionByEntryId[entry.id] = (regionName, regionOrder)
            }
        }

        // Step 2: For each calendar day, pick the dominant region by majority vote
        let entriesByDay = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        var dominantByDay: [Date: (name: String, order: Int)] = [:]

        for (day, dayEntries) in entriesByDay {
            let assigned = dayEntries.compactMap { e -> (String, Int)? in
                guard let r = regionByEntryId[e.id] else { return nil }
                return (r.name, r.order)
            }
            guard !assigned.isEmpty else { continue }

            let counts = Dictionary(grouping: assigned) { $0.0 }
            if let dominant = counts.max(by: { $0.value.count < $1.value.count }),
               let firstOrder = dominant.value.first?.1 {
                dominantByDay[day] = (dominant.key, firstOrder)
            }
        }

        // Step 3: Apply the day-level region to every entry (including those without coordinates)
        return entries.map { entry in
            let day = cal.startOfDay(for: entry.timestamp)
            let region = dominantByDay[day]
            return TripEntry(
                id: entry.id,
                tripId: entry.tripId,
                timestamp: entry.timestamp,
                entryType: entry.entryType,
                title: entry.title,
                content: entry.content,
                imageURLs: entry.imageURLs,
                latitude: entry.latitude,
                longitude: entry.longitude,
                locationName: entry.locationName,
                flightId: entry.flightId,
                isPreview: entry.isPreview,
                regionName: region?.name,
                regionOrder: region?.order,
                isRegionAIGenerated: true,
                createdAt: entry.createdAt,
                updatedAt: Date()
            )
        }
    }

    // MARK: - Helpers

    /// Check if trip should show region UI (has multiple regions)
    func shouldShowRegions(for entries: [TripEntry]) -> Bool {
        let uniqueRegions = Set(entries.compactMap { $0.regionName })
        return uniqueRegions.count > 1
    }

    /// Get region summary for display
    func getRegionSummary(for entries: [TripEntry]) -> [(regionName: String, entryCount: Int)] {
        let grouped = Dictionary(grouping: entries) { $0.regionName ?? "Unassigned" }
        return grouped.map { (regionName: $0.key, entryCount: $0.value.count) }
            .sorted { ($0.entryCount, $0.regionName) > ($1.entryCount, $1.regionName) }
    }
}
