//
//  Flight.swift
//  SkyLine
//
//  Flight data models matching the React Native structure
//

import Foundation
import CoreLocation

// MARK: - Main Flight Model
struct Flight: Codable, Identifiable, Hashable {
    let id: String
    let flightNumber: String
    let airline: String
    let departure: Airport
    let arrival: Airport
    let status: FlightStatus
    let aircraft: Aircraft?
    let currentPosition: FlightPosition?
    let progress: Double? // 0.0 to 1.0
    let flightDate: String?
    let dataSource: DataSource
    
    var isDeparted: Bool {
        status == .departed || status == .inAir || status == .landed
    }
    
    var isActive: Bool {
        status == .inAir || status == .departed
    }
    
    var routeDescription: String {
        "\(departure.code) → \(arrival.code)"
    }
}

// MARK: - Airport Model
struct Airport: Codable, Hashable {
    let airport: String
    let code: String
    let latitude: Double?
    let longitude: Double?
    let time: String
    let actualTime: String?
    let terminal: String?
    let gate: String?
    let delay: Int?
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        if let actualTime = actualTime, !actualTime.isEmpty {
            if let date = ISO8601DateFormatter().date(from: actualTime) {
                return formatter.string(from: date)
            }
        }
        
        if let date = ISO8601DateFormatter().date(from: time) {
            return formatter.string(from: date)
        }
        
        return "N/A"
    }
    
    var hasDelay: Bool {
        guard let delay = delay else { return false }
        return delay > 0
    }
    
    var delayText: String {
        guard let delay = delay, delay > 0 else { return "" }
        return "+\(delay)min"
    }
}

// MARK: - Aircraft Model
struct Aircraft: Codable, Hashable {
    let type: String?
    let registration: String?
    let icao24: String?
    
    var displayName: String {
        if let type = type, !type.isEmpty {
            if let registration = registration, !registration.isEmpty {
                return "\(type) • \(registration)"
            }
            return type
        }
        return registration ?? "Unknown Aircraft"
    }
}

// MARK: - Flight Position Model
struct FlightPosition: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let heading: Double
    let isGround: Bool?
    let lastUpdate: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var altitudeInFeet: String {
        let feet = Int(altitude * 3.28084) // Convert meters to feet
        return "\(feet.formatted()) ft"
    }
    
    var speedInKnots: String {
        let knots = Int(speed * 0.539957) // Convert km/h to knots
        return "\(knots) kts"
    }
}

// MARK: - Flight Status Enum
enum FlightStatus: String, Codable, CaseIterable {
    case boarding = "boarding"
    case departed = "departed"
    case inAir = "in-air"
    case landed = "landed"
    case delayed = "delayed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .boarding: return "Boarding"
        case .departed: return "Departed"
        case .inAir: return "In Air"
        case .landed: return "Landed"
        case .delayed: return "Delayed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: String {
        switch self {
        case .boarding: return "orange"
        case .departed: return "blue"
        case .inAir: return "green"
        case .landed: return "mint"
        case .delayed: return "red"
        case .cancelled: return "pink"
        }
    }
    
    var systemImage: String {
        switch self {
        case .boarding: return "person.badge.clock"
        case .departed: return "airplane.departure"
        case .inAir: return "airplane"
        case .landed: return "airplane.arrival"
        case .delayed: return "clock.badge.exclamationmark"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Data Source Enum
enum DataSource: String, Codable {
    case opensky = "opensky"
    case aviationstack = "aviationstack"
    case combined = "combined"
    case pkpass = "pkpass"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .opensky: return "OpenSky Network"
        case .aviationstack: return "AviationStack"
        case .combined: return "Combined Sources"
        case .pkpass: return "Apple Wallet"
        case .manual: return "Manual Entry"
        }
    }
}

// MARK: - Flight Search Result
struct FlightSearchResult: Codable {
    let flights: [Flight]
    let totalCount: Int
    let dataSource: String
    let searchTime: Date
}

// MARK: - Sample Data for Development
extension Flight {
    static let sample = Flight(
        id: "sample-aa123-20250824",
        flightNumber: "AA123",
        airline: "American Airlines",
        departure: Airport(
            airport: "Los Angeles International Airport",
            code: "LAX",
            latitude: 33.9425,
            longitude: -118.4081,
            time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
            actualTime: nil,
            terminal: "4",
            gate: "42A",
            delay: nil
        ),
        arrival: Airport(
            airport: "John F. Kennedy International Airport",
            code: "JFK",
            latitude: 40.6413,
            longitude: -73.7781,
            time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(18000)),
            actualTime: nil,
            terminal: "8",
            gate: "12",
            delay: nil
        ),
        status: .boarding,
        aircraft: Aircraft(
            type: "Boeing 737-800",
            registration: "N123AA",
            icao24: "A12345"
        ),
        currentPosition: nil,
        progress: 0.0,
        flightDate: ISO8601DateFormatter().string(from: Date()),
        dataSource: .aviationstack
    )
    
    static let sampleInAir = Flight(
        id: "sample-ua456-20250824",
        flightNumber: "UA456",
        airline: "United Airlines",
        departure: Airport(
            airport: "San Francisco International Airport",
            code: "SFO",
            latitude: 37.6213,
            longitude: -122.3790,
            time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
            actualTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3540)),
            terminal: "3",
            gate: "G12",
            delay: 20
        ),
        arrival: Airport(
            airport: "Chicago O'Hare International Airport",
            code: "ORD",
            latitude: 41.9742,
            longitude: -87.9073,
            time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(10800)),
            actualTime: nil,
            terminal: "1",
            gate: "C18",
            delay: nil
        ),
        status: .inAir,
        aircraft: Aircraft(
            type: "Airbus A320",
            registration: "N456UA",
            icao24: "A98765"
        ),
        currentPosition: FlightPosition(
            latitude: 39.8283,
            longitude: -98.5795,
            altitude: 11582.4,
            speed: 850.0,
            heading: 85.5,
            isGround: false,
            lastUpdate: ISO8601DateFormatter().string(from: Date())
        ),
        progress: 0.45,
        flightDate: ISO8601DateFormatter().string(from: Date()),
        dataSource: .combined
    )
}