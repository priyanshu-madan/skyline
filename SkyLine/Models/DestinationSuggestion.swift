//
//  DestinationSuggestion.swift
//  SkyLine
//
//  Destination suggestion model for autocomplete functionality
//

import Foundation

struct DestinationSuggestion: Identifiable, Hashable {
    let id = UUID()
    let city: String
    let state: String?
    let country: String
    let airportCode: String?
    let latitude: Double
    let longitude: Double
    let fullName: String?
    let subtitle: String?
    
    var displayName: String {
        if let fullName = fullName, !fullName.isEmpty {
            return fullName
        } else if let airportCode = airportCode {
            return "\(city), \(country) (\(airportCode))"
        } else {
            return "\(city), \(country)"
        }
    }
    
    var detailText: String {
        if let subtitle = subtitle, !subtitle.isEmpty {
            return subtitle
        } else {
            return country
        }
    }
    
    // Convenience initializer for backwards compatibility with existing mock data
    init(city: String, state: String? = nil, country: String, airportCode: String?, latitude: Double?, longitude: Double?, fullName: String? = nil, subtitle: String? = nil) {
        self.city = city
        self.state = state
        self.country = country
        self.airportCode = airportCode
        self.latitude = latitude ?? 0.0
        self.longitude = longitude ?? 0.0
        self.fullName = fullName
        self.subtitle = subtitle
    }
}