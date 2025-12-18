//
//  FlightAPIService.swift
//  SkyLine
//
//  Flight API service layer for native iOS networking
//

import Foundation
import Combine

// MARK: - Flight API Service
class FlightAPIService: ObservableObject {
    static let shared = FlightAPIService()
    
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    // API Configuration
    private let aviationStackAPIKey = "970ddc082032b510760d4f07521fc20e" // Add your API key
    private let aviationStackBaseURL = "https://api.aviationstack.com/v1"
    private let openSkyBaseURL = "https://opensky-network.org/api"
    
    private init() {
        // Configure date formatters
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        encoder.dateEncodingStrategy = .formatted(dateFormatter)
    }
    
    // MARK: - Flight Search Methods
    
    func searchFlightsByNumber(_ flightNumber: String) async throws -> [Flight] {
        // Try AviationStack first
        do {
            let aviationFlights = try await searchAviationStackByFlightNumber(flightNumber)
            if !aviationFlights.isEmpty {
                return aviationFlights
            }
        } catch {
            print("AviationStack search failed: \(error)")
        }
        
        // Fallback to OpenSky (limited data)
        do {
            return try await searchOpenSkyByCallsign(flightNumber)
        } catch {
            print("OpenSky search failed: \(error)")
            throw APIError.searchFailed
        }
    }
    
    func searchFlightsByRoute(_ departure: String, _ arrival: String) async throws -> [Flight] {
        // This would typically use AviationStack's route search
        return try await searchAviationStackByRoute(departure, arrival)
    }
    
    func getLiveFlights(limit: Int = 50) async throws -> [Flight] {
        return try await getOpenSkyLiveFlights(limit: limit)
    }
    
    // MARK: - AviationStack Integration
    
    private func searchAviationStackByFlightNumber(_ flightNumber: String) async throws -> [Flight] {
        guard !aviationStackAPIKey.isEmpty else {
            throw APIError.missingAPIKey
        }
        
        var components = URLComponents(string: "\(aviationStackBaseURL)/flights")!
        components.queryItems = [
            URLQueryItem(name: "access_key", value: aviationStackAPIKey),
            URLQueryItem(name: "flight_iata", value: flightNumber),
            URLQueryItem(name: "limit", value: "10")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        let aviationResponse = try decoder.decode(AviationStackResponse.self, from: data)
        return aviationResponse.data.compactMap { convertAviationStackFlight($0) }
    }
    
    private func searchAviationStackByRoute(_ departure: String, _ arrival: String) async throws -> [Flight] {
        guard !aviationStackAPIKey.isEmpty else {
            throw APIError.missingAPIKey
        }
        
        var components = URLComponents(string: "\(aviationStackBaseURL)/flights")!
        components.queryItems = [
            URLQueryItem(name: "access_key", value: aviationStackAPIKey),
            URLQueryItem(name: "dep_iata", value: departure),
            URLQueryItem(name: "arr_iata", value: arrival),
            URLQueryItem(name: "limit", value: "20")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        let aviationResponse = try decoder.decode(AviationStackResponse.self, from: data)
        return aviationResponse.data.compactMap { convertAviationStackFlight($0) }
    }
    
    // MARK: - OpenSky Integration
    
    private func searchOpenSkyByCallsign(_ callsign: String) async throws -> [Flight] {
        let url = URL(string: "\(openSkyBaseURL)/states/all")!
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        let openSkyResponse = try decoder.decode(OpenSkyResponse.self, from: data)
        
        return openSkyResponse.states?
            .filter { $0.callsign?.trimmingCharacters(in: .whitespaces).uppercased() == callsign.uppercased() }
            .compactMap { convertOpenSkyState($0) } ?? []
    }
    
    private func getOpenSkyLiveFlights(limit: Int) async throws -> [Flight] {
        let url = URL(string: "\(openSkyBaseURL)/states/all")!
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        let openSkyResponse = try decoder.decode(OpenSkyResponse.self, from: data)
        
        return openSkyResponse.states?
            .filter { state in
                // Filter for airborne flights with callsigns
                state.on_ground == false &&
                state.latitude != nil &&
                state.longitude != nil &&
                state.callsign?.trimmingCharacters(in: .whitespaces).count ?? 0 > 2
            }
            .prefix(limit)
            .compactMap { convertOpenSkyState($0) } ?? []
    }
    
    // MARK: - Data Conversion
    
    private func convertAviationStackFlight(_ aviationFlight: AviationStackFlight) -> Flight? {
        guard let flightIATA = aviationFlight.flight.iata,
              let departureAirport = aviationFlight.departure.airport,
              let departureIATA = aviationFlight.departure.iata,
              let arrivalAirport = aviationFlight.arrival.airport,
              let arrivalIATA = aviationFlight.arrival.iata,
              let airlineName = aviationFlight.airline.name else {
            return nil
        }
        
        // Get airport coordinates (triggers async fetch for missing airports)
        let depCoordinates = AirportService.shared.getCoordinates(for: departureIATA)
        let arrCoordinates = AirportService.shared.getCoordinates(for: arrivalIATA)
        
        // Note: Coordinates will be nil initially for missing airports,
        // but will be updated when the async fetch completes via the coordinate notification system
        
        return Flight(
            id: "as-\(flightIATA)-\(aviationFlight.flight_date ?? "")-\(departureIATA)-\(arrivalIATA)",
            flightNumber: flightIATA,
            airline: airlineName,
            departure: Airport(
                airport: departureAirport,
                code: departureIATA,
                city: departureAirport, // Use airport name as city for now
                latitude: depCoordinates?.latitude,
                longitude: depCoordinates?.longitude,
                time: aviationFlight.departure.scheduled ?? "",
                actualTime: aviationFlight.departure.actual,
                terminal: aviationFlight.departure.terminal,
                gate: aviationFlight.departure.gate,
                delay: aviationFlight.departure.delay
            ),
            arrival: Airport(
                airport: arrivalAirport,
                code: arrivalIATA,
                city: arrivalAirport, // Use airport name as city for now
                latitude: arrCoordinates?.latitude,
                longitude: arrCoordinates?.longitude,
                time: aviationFlight.arrival.scheduled ?? "",
                actualTime: aviationFlight.arrival.actual,
                terminal: aviationFlight.arrival.terminal,
                gate: aviationFlight.arrival.gate,
                delay: aviationFlight.arrival.delay
            ),
            status: mapAviationStackStatus(aviationFlight.flight_status),
            aircraft: aviationFlight.aircraft.map { aircraft in
                Aircraft(
                    type: aircraft.iata,
                    registration: aircraft.registration,
                    icao24: aircraft.icao24
                )
            },
            currentPosition: aviationFlight.live.map { live in
                FlightPosition(
                    latitude: live.latitude,
                    longitude: live.longitude,
                    altitude: live.altitude,
                    speed: live.speed_horizontal,
                    heading: live.direction,
                    isGround: live.is_ground,
                    lastUpdate: live.updated
                )
            },
            progress: nil,
            flightDate: aviationFlight.flight_date,
            dataSource: .aviationstack,
            date: Flight.extractFlightDate(from: aviationFlight.departure.scheduled ?? ""),
            isUserConfirmed: false,
            userConfirmedFields: .none
        )
    }
    
    private func convertOpenSkyState(_ state: OpenSkyState) -> Flight? {
        guard let callsign = state.callsign?.trimmingCharacters(in: .whitespaces),
              !callsign.isEmpty,
              let latitude = state.latitude,
              let longitude = state.longitude else {
            return nil
        }
        
        return Flight(
            id: "os-\(state.icao24)",
            flightNumber: callsign,
            airline: "Unknown",
            departure: Airport(
                airport: "Unknown",
                code: "UNK",
                city: "Unknown",
                latitude: nil,
                longitude: nil,
                time: ISO8601DateFormatter().string(from: Date()),
                actualTime: nil,
                terminal: nil,
                gate: nil,
                delay: nil
            ),
            arrival: Airport(
                airport: "Unknown",
                code: "UNK",
                city: "Unknown",
                latitude: nil,
                longitude: nil,
                time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(14400)),
                actualTime: nil,
                terminal: nil,
                gate: nil,
                delay: nil
            ),
            status: mapOpenSkyStatus(state),
            aircraft: Aircraft(
                type: nil,
                registration: nil,
                icao24: state.icao24
            ),
            currentPosition: FlightPosition(
                latitude: latitude,
                longitude: longitude,
                altitude: state.geo_altitude ?? state.baro_altitude ?? 0,
                speed: (state.velocity ?? 0) * 3.6, // Convert m/s to km/h
                heading: state.true_track ?? 0,
                isGround: state.on_ground,
                lastUpdate: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(state.last_contact)))
            ),
            progress: nil,
            flightDate: ISO8601DateFormatter().string(from: Date()),
            dataSource: .opensky,
            date: Calendar.current.startOfDay(for: Date()),
            isUserConfirmed: false,
            userConfirmedFields: .none
        )
    }
    
    // MARK: - Status Mapping
    
    private func mapAviationStackStatus(_ status: String?) -> FlightStatus {
        guard let status = status?.lowercased() else { return .boarding }
        
        switch status {
        case "scheduled": return .boarding
        case "active": return .inAir
        case "landed": return .landed
        case "cancelled": return .cancelled
        case "incident", "diverted": return .delayed
        default: return .boarding
        }
    }
    
    private func mapOpenSkyStatus(_ state: OpenSkyState) -> FlightStatus {
        let altitude = state.geo_altitude ?? state.baro_altitude ?? 0
        let velocity = state.velocity ?? 0
        
        if state.on_ground == true {
            return velocity > 5 ? .departed : .landed
        } else {
            return altitude > 1000 && velocity > 100 ? .inAir : .departed
        }
    }
}

// MARK: - API Error Types
enum APIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case serverError
    case searchFailed
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing"
        case .invalidURL:
            return "Invalid URL"
        case .serverError:
            return "Server error"
        case .searchFailed:
            return "Flight search failed"
        case .networkError:
            return "Network connection error"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - API Response Models

struct AviationStackResponse: Codable {
    let data: [AviationStackFlight]
}

struct AviationStackFlight: Codable {
    let flight_date: String?
    let flight_status: String?
    let flight: AviationStackFlightInfo
    let airline: AviationStackAirline
    let departure: AviationStackAirport
    let arrival: AviationStackAirport
    let aircraft: AviationStackAircraft?
    let live: AviationStackLive?
}

struct AviationStackFlightInfo: Codable {
    let iata: String?
    let icao: String?
    let number: String?
}

struct AviationStackAirline: Codable {
    let name: String?
    let iata: String?
    let icao: String?
}

struct AviationStackAirport: Codable {
    let airport: String?
    let timezone: String?
    let iata: String?
    let icao: String?
    let terminal: String?
    let gate: String?
    let delay: Int?
    let scheduled: String?
    let estimated: String?
    let actual: String?
}

struct AviationStackAircraft: Codable {
    let registration: String?
    let iata: String?
    let icao: String?
    let icao24: String?
}

struct AviationStackLive: Codable {
    let updated: String?
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let direction: Double
    let speed_horizontal: Double
    let speed_vertical: Double
    let is_ground: Bool
}

struct OpenSkyResponse: Codable {
    let time: Int
    let states: [OpenSkyState]?
}

struct OpenSkyState: Codable {
    let icao24: String
    let callsign: String?
    let origin_country: String
    let time_position: Int?
    let last_contact: Int
    let longitude: Double?
    let latitude: Double?
    let baro_altitude: Double?
    let on_ground: Bool?
    let velocity: Double?
    let true_track: Double?
    let vertical_rate: Double?
    let sensors: [Int]?
    let geo_altitude: Double?
    let squawk: String?
    let spi: Bool?
    let position_source: Int?
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        
        icao24 = try container.decode(String.self)
        callsign = try container.decodeIfPresent(String.self)
        origin_country = try container.decode(String.self)
        time_position = try container.decodeIfPresent(Int.self)
        last_contact = try container.decode(Int.self)
        longitude = try container.decodeIfPresent(Double.self)
        latitude = try container.decodeIfPresent(Double.self)
        baro_altitude = try container.decodeIfPresent(Double.self)
        on_ground = try container.decodeIfPresent(Bool.self)
        velocity = try container.decodeIfPresent(Double.self)
        true_track = try container.decodeIfPresent(Double.self)
        vertical_rate = try container.decodeIfPresent(Double.self)
        sensors = try container.decodeIfPresent([Int].self)
        geo_altitude = try container.decodeIfPresent(Double.self)
        squawk = try container.decodeIfPresent(String.self)
        spi = try container.decodeIfPresent(Bool.self)
        position_source = try container.decodeIfPresent(Int.self)
    }
}
