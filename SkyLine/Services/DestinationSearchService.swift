//
//  DestinationSearchService.swift
//  SkyLine
//
//  Real-time destination search using MapKit for accurate location data
//

import Foundation
import MapKit
import CoreLocation

@MainActor
class DestinationSearchService: NSObject, ObservableObject {
    static let shared = DestinationSearchService()
    
    private let searchCompleter = MKLocalSearchCompleter()
    private let geocoder = CLGeocoder()
    
    @Published var suggestions: [DestinationSuggestion] = []
    @Published var isSearching = false
    
    private override init() {
        super.init()
        setupSearchCompleter()
    }
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        searchCompleter.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .airport,
            .amusementPark,
            .aquarium,
            .beach,
            .campground,
            .museum,
            .nationalPark,
            .park,
            .zoo,
            .hotel,
            .restaurant,
            .theater,
            .university,
            .stadium
        ])
    }
    
    func searchDestinations(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suggestions = []
            isSearching = false
            return
        }
        
        isSearching = true
        searchCompleter.queryFragment = query
    }
    
    func clearResults() {
        suggestions = []
        isSearching = false
        searchCompleter.queryFragment = ""
    }
    
    private func processSearchCompletion(_ completion: MKLocalSearchCompletion) async -> DestinationSuggestion? {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        
        do {
            let response = try await MKLocalSearch(request: searchRequest).start()
            
            guard let mapItem = response.mapItems.first else { return nil }
            
            let coordinate = mapItem.placemark.coordinate
            let name = mapItem.name ?? completion.title
            
            // Extract city and country information
            let placemark = mapItem.placemark
            let city = placemark.locality ?? placemark.administrativeArea ?? name
            let country = placemark.country ?? "Unknown"
            
            // Check if this is an airport
            let airportCode = extractAirportCode(from: mapItem)
            
            return DestinationSuggestion(
                city: city,
                country: country,
                airportCode: airportCode,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                fullName: name,
                subtitle: completion.subtitle
            )
            
        } catch {
            print("❌ DestinationSearchService: Failed to get location details: \(error)")
            return nil
        }
    }
    
    private func extractAirportCode(from mapItem: MKMapItem) -> String? {
        // Check if the name contains an airport code pattern (3 uppercase letters in parentheses)
        let name = mapItem.name ?? ""
        let pattern = "\\(([A-Z]{3})\\)"
        
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let range = Range(match.range(at: 1), in: name) {
            return String(name[range])
        }
        
        // Check if this is categorized as an airport
        if mapItem.pointOfInterestCategory == .airport {
            // Try to extract from the name (common patterns: "Airport Name (CODE)" or "CODE - Airport Name")
            let words = name.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            for word in words {
                if word.count == 3 && word.allSatisfy({ $0.isLetter }) {
                    return word
                }
            }
        }
        
        return nil
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension DestinationSearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task {
            let completions = completer.results.prefix(8) // Limit to 8 suggestions
            var newSuggestions: [DestinationSuggestion] = []
            
            for completion in completions {
                if let suggestion = await processSearchCompletion(completion) {
                    newSuggestions.append(suggestion)
                }
            }
            
            await MainActor.run {
                self.suggestions = newSuggestions
                self.isSearching = false
            }
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("❌ DestinationSearchService: Search failed: \(error)")
        Task { @MainActor in
            self.isSearching = false
        }
    }
}

// DestinationSuggestion model moved to separate file: Models/DestinationSuggestion.swift