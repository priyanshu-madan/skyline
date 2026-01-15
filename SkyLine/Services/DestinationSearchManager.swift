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
    
    override init() {
        super.init()
        searchCompleter.delegate = self
        
        // Include both addresses AND points of interest for comprehensive travel search
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        
        // Configure POI filter to include travel-relevant attractions
        searchCompleter.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .amusementPark,     // Theme parks like Disneyland, Universal Studios
            .nationalPark,      // National parks and preserves
            .zoo, .aquarium,    // Animal attractions
            .museum,            // Museums and cultural sites
            .theater, .movieTheater, // Entertainment venues
            .hotel,             // Accommodations
            .restaurant,        // Dining locations
            .airport,           // Transportation hubs
            .beach,             // Natural attractions
            .campground, .marina, .spa, .stadium // Other travel POIs
        ])
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
            // Use Apple's results with minimal, lightweight sorting
            // Just prioritize geographic locations (cities, countries) over specific addresses
            let sortedResults = completer.results.sorted { first, second in
                let firstIsGeographic = isLikelyGeographicLocation(first)
                let secondIsGeographic = isLikelyGeographicLocation(second)
                
                if firstIsGeographic && !secondIsGeographic {
                    return true
                } else if !firstIsGeographic && secondIsGeographic {
                    return false
                } else {
                    // Same type - maintain Apple's original order
                    return false
                }
            }
            
            searchResults = Array(sortedResults.prefix(8))
            isSearching = false
            errorMessage = nil
        }
    }
    
    // Simple check for geographic vs specific locations
    private func isLikelyGeographicLocation(_ completion: MKLocalSearchCompletion) -> Bool {
        let subtitle = completion.subtitle.lowercased()
        // Just check if it looks like a city/country rather than a specific address
        return !subtitle.contains("street") && !subtitle.contains("avenue") && 
               !subtitle.contains("road") && !subtitle.contains("boulevard")
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            isSearching = false
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
    }
}