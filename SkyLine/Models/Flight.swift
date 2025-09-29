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
    let airline: String?
    let departure: Airport
    let arrival: Airport
    let status: FlightStatus
    let aircraft: Aircraft?
    let currentPosition: FlightPosition?
    let progress: Double? // 0.0 to 1.0
    let flightDate: String?
    let dataSource: DataSource
    let date: Date
    
    var isDeparted: Bool {
        status == .departed || status == .inAir || status == .landed
    }
    
    var isActive: Bool {
        status == .inAir || status == .departed
    }
    
    var routeDescription: String {
        "\(departure.code) → \(arrival.code)"
    }
    
    // Helper function to extract flight date from departure time
    static func extractFlightDate(from departureTime: String) -> Date {
        let formatter = ISO8601DateFormatter()
        if let parsedDate = formatter.date(from: departureTime) {
            // Return the date component only (start of day)
            return Calendar.current.startOfDay(for: parsedDate)
        }
        // Fallback to current date if parsing fails
        return Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Airport Model
struct Airport: Codable, Hashable {
    let airport: String
    let code: String
    let city: String
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
            city: "Los Angeles",
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
            city: "New York",
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
        dataSource: .aviationstack,
        date: Flight.extractFlightDate(from: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
    )
    
    static let sampleInAir = Flight(
        id: "sample-ua456-20250824",
        flightNumber: "UA456",
        airline: "United Airlines",
        departure: Airport(
            airport: "San Francisco International Airport",
            code: "SFO",
            city: "San Francisco",
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
            city: "Chicago",
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
        dataSource: .combined,
        date: Flight.extractFlightDate(from: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)))
    )
    
    // Additional sample flights matching Figma design
    static let sampleFigmaDesign = Flight(
        id: "sample-figma-bna-bdb",
        flightNumber: "LA 21",
        airline: "Garuda INA",
        departure: Airport(
            airport: "Banda Aceh Airport",
            code: "BNA",
            city: "Banda Aceh",
            latitude: 5.523611,
            longitude: 95.420833,
            time: ISO8601DateFormatter().string(from: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()),
            actualTime: nil,
            terminal: "1",
            gate: "A5",
            delay: nil
        ),
        arrival: Airport(
            airport: "Bandar Baru Airport",
            code: "BDB",
            city: "Bandar Baru",
            latitude: 1.385,
            longitude: 103.8667,
            time: ISO8601DateFormatter().string(from: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()),
            actualTime: nil,
            terminal: "2",
            gate: "B12",
            delay: nil
        ),
        status: .boarding,
        aircraft: Aircraft(
            type: "Boeing 737-800",
            registration: "PK-GMA",
            icao24: "8D0001"
        ),
        currentPosition: nil,
        progress: 0.0,
        flightDate: ISO8601DateFormatter().string(from: Date()),
        dataSource: .manual,
        date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    )
    
    static let sampleJakartaDenpasar = Flight(
        id: "sample-jkt-dps",
        flightNumber: "JT 930",
        airline: "Lion Air",
        departure: Airport(
            airport: "Soekarno-Hatta International Airport",
            code: "JKT",
            city: "Jakarta",
            latitude: -6.1275,
            longitude: 106.6537,
            time: ISO8601DateFormatter().string(from: Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: Date()) ?? Date()),
            actualTime: nil,
            terminal: "1A",
            gate: "A7",
            delay: nil
        ),
        arrival: Airport(
            airport: "Ngurah Rai International Airport",
            code: "DPS",
            city: "Denpasar",
            latitude: -8.7467,
            longitude: 115.1667,
            time: ISO8601DateFormatter().string(from: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date()),
            actualTime: nil,
            terminal: "D",
            gate: "D3",
            delay: nil
        ),
        status: .departed,
        aircraft: Aircraft(
            type: "Boeing 737-900ER",
            registration: "PK-LJR",
            icao24: "8D0002"
        ),
        currentPosition: nil,
        progress: 0.3,
        flightDate: ISO8601DateFormatter().string(from: Date()),
        dataSource: .manual,
        date: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    )
}