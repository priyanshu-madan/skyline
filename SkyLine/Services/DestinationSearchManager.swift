//
//  DestinationSearchManager.swift
//  SkyLine
//
//  Location search service using MKLocalSearchCompleter for destination autocomplete
//

import Foundation
import MapKit
import Combine

@MainActor
class DestinationSearchManager: NSObject, ObservableObject {
    private let searchCompleter = MKLocalSearchCompleter()

    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    // Optional region to bias search results towards a specific area
    // When set, search results will prioritize locations within this region
    // For example: Trip to Delhi → prioritizes Delhi locations over NYC
    var regionBias: MKCoordinateRegion? {
        didSet {
            searchCompleter.region = regionBias ?? MKCoordinateRegion()
        }
    }

    override init() {
        super.init()
        searchCompleter.delegate = self

        // Include both addresses AND points of interest for comprehensive travel search
        searchCompleter.resultTypes = [.address, .pointOfInterest]

        // Don't use a restrictive POI filter - Apple might categorize landmarks differently
        // Instead, we'll use our smart sorting algorithm to prioritize results
        // This ensures famous landmarks like Taj Mahal appear even if they're not in a specific category
        searchCompleter.pointOfInterestFilter = nil  // Accept ALL POIs, then sort intelligently
    }

    convenience init(regionBias: MKCoordinateRegion?) {
        self.init()
        if let region = regionBias {
            self.regionBias = region
            self.searchCompleter.region = region
        }
    }
    
    func search(for query: String) {
        guard !query.isEmpty, query.count > 2 else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        errorMessage = nil
        searchCompleter.queryFragment = query
    }
    
    func clearSearch() {
        searchResults = []
        searchCompleter.queryFragment = ""
        isSearching = false
        errorMessage = nil
    }
    
    func getLocationDetails(for completion: MKLocalSearchCompletion) async -> DestinationSuggestion? {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first else { return nil }
            
            let placemark = mapItem.placemark
            let coordinate = placemark.coordinate
            
            // Extract city, state, country, and airport code if available
            let city = placemark.locality ?? completion.title
            let state = placemark.administrativeArea // State/Province
            let country = placemark.country ?? ""

            // Try to find nearby airport code (simplified approach)
            let airportCode = await findNearbyAirportCode(coordinate: coordinate)

            return DestinationSuggestion(
                city: city,
                state: state,
                country: country,
                airportCode: airportCode,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                fullName: completion.title,  // Use the actual selected name
                subtitle: completion.subtitle
            )
        } catch {
            await MainActor.run {
                errorMessage = "Failed to get location details: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    private func findNearbyAirportCode(coordinate: CLLocationCoordinate2D) async -> String? {
        // Search for nearby airports
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "airport"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 50000, // 50km radius
            longitudinalMeters: 50000
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            // Find the closest airport
            let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearestAirport = response.mapItems
                .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                    let airportLocation = CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                    let distance = currentLocation.distance(from: airportLocation)
                    return (item, distance)
                }
                .min { $0.1 < $1.1 }
            
            if let airport = nearestAirport?.0 {
                // Try to extract airport code from name
                return extractAirportCode(from: airport.name ?? "")
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    private func extractAirportCode(from airportName: String) -> String? {
        // Look for 3-letter airport codes in parentheses like "Los Angeles International (LAX)"
        let pattern = #"\(([A-Z]{3})\)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(airportName.startIndex..<airportName.endIndex, in: airportName)
        
        if let match = regex?.firstMatch(in: airportName, options: [], range: nsRange) {
            let range = Range(match.range(at: 1), in: airportName)
            if let range = range {
                return String(airportName[range])
            }
        }
        
        return nil
    }
    
}

// MARK: - MKLocalSearchCompleterDelegate
extension DestinationSearchManager: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Debug: Log what we received from Apple
            print("🔍 Search received \(completer.results.count) results from Apple Maps")

            // Smart sorting: Prioritize landmarks and attractions over businesses
            let sortedResults = completer.results.sorted { first, second in
                let firstPriority = getResultPriority(first)
                let secondPriority = getResultPriority(second)

                if firstPriority != secondPriority {
                    return firstPriority < secondPriority  // Lower number = higher priority
                }

                // Same priority - maintain Apple's original order (relevance-based)
                return false
            }

            // Debug: Log top results with their priorities
            for (index, result) in sortedResults.prefix(10).enumerated() {
                let priority = getResultPriority(result)
                print("  \(index + 1). [\(priority)] \(result.title) - \(result.subtitle)")
            }

            searchResults = Array(sortedResults.prefix(10))
            isSearching = false
            errorMessage = nil
        }
    }

    // Assign priority scores to search results
    // Lower number = higher priority (0 is highest)
    private func getResultPriority(_ completion: MKLocalSearchCompletion) -> Int {
        let title = completion.title.lowercased()
        let subtitle = completion.subtitle.lowercased()

        // FILTER OUT: Results that are just "near" something else
        // e.g., "Hotel XYZ near Taj Mahal" should be deprioritized
        if title.contains("near") || subtitle.contains("near") {
            return 99  // Very low priority
        }

        // FILTER OUT: Generic businesses using landmark names
        let businessKeywords = ["hotel", "resort", "inn", "lodge", "restaurant",
                                "cafe", "coffee", "shop", "store", "mall", "market", "guest house"]
        let hasBusinessKeyword = businessKeywords.contains(where: { title.contains($0) })

        // If it's a business (hotel/restaurant), give it low priority
        if hasBusinessKeyword {
            return 50  // Low priority for businesses
        }

        // Priority 0: Famous landmarks and tourist attractions
        // Look for museum, temple, monument, palace, fort, tower, etc.
        let landmarkKeywords = ["museum", "temple", "palace", "fort", "tower", "monument",
                                "memorial", "cathedral", "church", "mosque", "shrine",
                                "castle", "ruins", "gardens", "park", "beach", "lake",
                                "falls", "canyon", "mountain", "hill", "statue", "zoo", "aquarium",
                                "mahal", "mandir", "gurdwara", "stupa", "pagoda", "wat",
                                "basilica", "abbey", "sanctuary", "plaza", "square", "gate",
                                "arch", "bridge", "dam", "lighthouse", "observatory",
                                "tomb", "mausoleum", "world heritage"]
        if landmarkKeywords.contains(where: { title.contains($0) || subtitle.contains($0) }) {
            return 0
        }

        // Priority 1: Geographic locations (cities, neighborhoods, areas)
        if isLikelyGeographicLocation(completion) {
            return 1
        }

        // Priority 2: General points of interest (no street address)
        if !subtitle.contains("street") && !subtitle.contains("avenue") &&
           !subtitle.contains("road") && !subtitle.contains("boulevard") {
            return 2
        }

        // Priority 3: Street addresses (lowest priority for actual destinations)
        return 3
    }

    // Check if result is a geographic location (city, neighborhood, region)
    private func isLikelyGeographicLocation(_ completion: MKLocalSearchCompletion) -> Bool {
        let subtitle = completion.subtitle.lowercased()

        // Geographic locations don't have street addresses
        let hasStreetAddress = subtitle.contains("street") || subtitle.contains("avenue") ||
                               subtitle.contains("road") || subtitle.contains("boulevard")

        // Geographic locations typically have country/state in subtitle
        let hasGeographicInfo = subtitle.contains(",") && !hasStreetAddress

        return hasGeographicInfo
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            isSearching = false
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
    }
}