//
//  AirportService.swift
//  SkyLine
//
//  Airport data service for coordinate lookups and information
//

import Foundation
import CoreLocation
import Combine

// MARK: - Airport Service
class AirportService: ObservableObject {
    static let shared = AirportService()
    
    private var airportDatabase: [String: CLLocationCoordinate2D] = [:]
    private var isLoaded = false
    
    // Publisher to notify when coordinates are updated
    let coordinatesUpdated = PassthroughSubject<String, Never>()
    
    private init() {
        loadInitialAirports()
    }
    
    // Airport coordinates lookup (subset of major airports)
    private let airportCoordinates: [String: CLLocationCoordinate2D] = [
        // Major US Airports
        // "LAX": CLLocationCoordinate2D(latitude: 33.9425, longitude: -118.4081), // Removed to test shared storage
        "JFK": CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781),
        "LGA": CLLocationCoordinate2D(latitude: 40.7769, longitude: -73.8740),
        "EWR": CLLocationCoordinate2D(latitude: 40.6895, longitude: -74.1745),
        "SFO": CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790),
        "ORD": CLLocationCoordinate2D(latitude: 41.9742, longitude: -87.9073),
        "DFW": CLLocationCoordinate2D(latitude: 32.8968, longitude: -97.0380),
        "ATL": CLLocationCoordinate2D(latitude: 33.6407, longitude: -84.4277),
        "MIA": CLLocationCoordinate2D(latitude: 25.7959, longitude: -80.2870),
        "BOS": CLLocationCoordinate2D(latitude: 42.3656, longitude: -71.0096),
        "SEA": CLLocationCoordinate2D(latitude: 47.4502, longitude: -122.3088),
        "LAS": CLLocationCoordinate2D(latitude: 36.0840, longitude: -115.1537),
        "PHX": CLLocationCoordinate2D(latitude: 33.4373, longitude: -112.0078),
        "DEN": CLLocationCoordinate2D(latitude: 39.8561, longitude: -104.6737),
        "IAH": CLLocationCoordinate2D(latitude: 29.9902, longitude: -95.3368),
        "MSP": CLLocationCoordinate2D(latitude: 44.8850, longitude: -93.2218),
        "DTW": CLLocationCoordinate2D(latitude: 42.2162, longitude: -83.3554),
        "PHL": CLLocationCoordinate2D(latitude: 39.8744, longitude: -75.2424),
        "CLT": CLLocationCoordinate2D(latitude: 35.2144, longitude: -80.9431),
        "BWI": CLLocationCoordinate2D(latitude: 39.1776, longitude: -76.6684),
        
        // Major International Airports
        "LHR": CLLocationCoordinate2D(latitude: 51.4700, longitude: -0.4543),
        "CDG": CLLocationCoordinate2D(latitude: 49.0097, longitude: 2.5479),
        "FRA": CLLocationCoordinate2D(latitude: 50.0379, longitude: 8.5622),
        "AMS": CLLocationCoordinate2D(latitude: 52.3105, longitude: 4.7683),
        "MAD": CLLocationCoordinate2D(latitude: 40.4839, longitude: -3.5680),
        "FCO": CLLocationCoordinate2D(latitude: 41.7999, longitude: 12.2462),
        "ZUR": CLLocationCoordinate2D(latitude: 47.4582, longitude: 8.5492),
        "VIE": CLLocationCoordinate2D(latitude: 48.1103, longitude: 16.5697),
        "CPH": CLLocationCoordinate2D(latitude: 55.6181, longitude: 12.6561),
        "ARN": CLLocationCoordinate2D(latitude: 59.6519, longitude: 17.9186),
        "HEL": CLLocationCoordinate2D(latitude: 60.3172, longitude: 24.9633),
        "SVO": CLLocationCoordinate2D(latitude: 55.9726, longitude: 37.4146),
        "OPO": CLLocationCoordinate2D(latitude: 41.2482, longitude: -8.6814),
        "LIS": CLLocationCoordinate2D(latitude: 38.7756, longitude: -9.1354),
        "BCN": CLLocationCoordinate2D(latitude: 41.2974, longitude: 2.0833),
        "MAN": CLLocationCoordinate2D(latitude: 53.3537, longitude: -2.2750),
        "DUB": CLLocationCoordinate2D(latitude: 53.4264, longitude: -6.2499),
        
        // Asia-Pacific
        "NRT": CLLocationCoordinate2D(latitude: 35.7720, longitude: 140.3929),
        "HND": CLLocationCoordinate2D(latitude: 35.5494, longitude: 139.7798),
        "ICN": CLLocationCoordinate2D(latitude: 37.4602, longitude: 126.4407),
        "PVG": CLLocationCoordinate2D(latitude: 31.1443, longitude: 121.8083),
        "PEK": CLLocationCoordinate2D(latitude: 40.0799, longitude: 116.6031),
        "CAN": CLLocationCoordinate2D(latitude: 23.3924, longitude: 113.2988),
        "HKG": CLLocationCoordinate2D(latitude: 22.3080, longitude: 113.9185),
        "SIN": CLLocationCoordinate2D(latitude: 1.3644, longitude: 103.9915),
        "BKK": CLLocationCoordinate2D(latitude: 13.6900, longitude: 100.7501),
        "KUL": CLLocationCoordinate2D(latitude: 2.7456, longitude: 101.7072),
        "SYD": CLLocationCoordinate2D(latitude: -33.9399, longitude: 151.1753),
        "MEL": CLLocationCoordinate2D(latitude: -37.6690, longitude: 144.8410),
        
        // India 
        "DEL": CLLocationCoordinate2D(latitude: 28.5562, longitude: 77.1000), // Delhi Airport
        "BOM": CLLocationCoordinate2D(latitude: 19.0896, longitude: 72.8656),
        "MAA": CLLocationCoordinate2D(latitude: 12.9941, longitude: 80.1709),
        "BLR": CLLocationCoordinate2D(latitude: 13.1979, longitude: 77.7069),
        "HYD": CLLocationCoordinate2D(latitude: 17.2403, longitude: 78.4294),
        "IXC": CLLocationCoordinate2D(latitude: 30.6735, longitude: 76.7884), // Chandigarh Airport
        "CCU": CLLocationCoordinate2D(latitude: 22.6546, longitude: 88.4467),
        "AMD": CLLocationCoordinate2D(latitude: 23.0775, longitude: 72.6362),
        "COK": CLLocationCoordinate2D(latitude: 9.9502, longitude: 76.2673),
        
        // Middle East & Africa
        "DXB": CLLocationCoordinate2D(latitude: 25.2532, longitude: 55.3657),
        "DOH": CLLocationCoordinate2D(latitude: 25.2732, longitude: 51.6078),
        "AUH": CLLocationCoordinate2D(latitude: 24.4330, longitude: 54.6511),
        "CAI": CLLocationCoordinate2D(latitude: 30.1219, longitude: 31.4056),
        "JNB": CLLocationCoordinate2D(latitude: -26.1367, longitude: 28.2411),
        
        // South America
        "GRU": CLLocationCoordinate2D(latitude: -23.4356, longitude: -46.4731),
        "GIG": CLLocationCoordinate2D(latitude: -22.8099, longitude: -43.2505),
        "BOG": CLLocationCoordinate2D(latitude: 4.7016, longitude: -74.1469),
        "LIM": CLLocationCoordinate2D(latitude: -12.0219, longitude: -77.1143),
        "SCL": CLLocationCoordinate2D(latitude: -33.3930, longitude: -70.7858),
        "EZE": CLLocationCoordinate2D(latitude: -34.8222, longitude: -58.5358),
        
        // Canada
        "YYZ": CLLocationCoordinate2D(latitude: 43.6777, longitude: -79.6248),
        "YVR": CLLocationCoordinate2D(latitude: 49.1967, longitude: -123.1815),
        "YUL": CLLocationCoordinate2D(latitude: 45.4706, longitude: -73.7408),
        "YYC": CLLocationCoordinate2D(latitude: 51.1315, longitude: -114.0106)
    ]
    
    // Airport names lookup
    private let airportNames: [String: String] = [
        "LAX": "Los Angeles International Airport",
        "JFK": "John F. Kennedy International Airport",
        "LGA": "LaGuardia Airport",
        "EWR": "Newark Liberty International Airport",
        "SFO": "San Francisco International Airport",
        "ORD": "Chicago O'Hare International Airport",
        "DFW": "Dallas/Fort Worth International Airport",
        "ATL": "Hartsfield-Jackson Atlanta International Airport",
        "MIA": "Miami International Airport",
        "BOS": "Boston Logan International Airport",
        "SEA": "Seattle-Tacoma International Airport",
        "LAS": "Harry Reid International Airport",
        "PHX": "Phoenix Sky Harbor International Airport",
        "DEN": "Denver International Airport",
        "IAH": "George Bush Intercontinental Airport",
        "MSP": "Minneapolis-St. Paul International Airport",
        "DTW": "Detroit Metropolitan Wayne County Airport",
        "PHL": "Philadelphia International Airport",
        "CLT": "Charlotte Douglas International Airport",
        "BWI": "Baltimore/Washington International Thurgood Marshall Airport",
        "LHR": "London Heathrow Airport",
        "CDG": "Charles de Gaulle Airport",
        "FRA": "Frankfurt Airport",
        "AMS": "Amsterdam Airport Schiphol",
        "MAD": "Adolfo Suárez Madrid–Barajas Airport",
        "FCO": "Leonardo da Vinci International Airport",
        "ZUR": "Zurich Airport",
        "VIE": "Vienna International Airport",
        "CPH": "Copenhagen Airport",
        "ARN": "Stockholm Arlanda Airport",
        "HEL": "Helsinki-Vantaa Airport",
        "SVO": "Sheremetyevo International Airport",
        "OPO": "Francisco Sá Carneiro Airport",
        "LIS": "Lisbon Portela Airport",
        "BCN": "Barcelona-El Prat Airport",
        "MAN": "Manchester Airport",
        "DUB": "Dublin Airport",
        "NRT": "Narita International Airport",
        "HND": "Tokyo Haneda Airport",
        "ICN": "Incheon International Airport",
        "PVG": "Shanghai Pudong International Airport",
        "PEK": "Beijing Capital International Airport",
        "CAN": "Guangzhou Baiyun International Airport",
        "HKG": "Hong Kong International Airport",
        "SIN": "Singapore Changi Airport",
        "BKK": "Suvarnabhumi Airport",
        "KUL": "Kuala Lumpur International Airport",
        "SYD": "Sydney Kingsford Smith Airport",
        "MEL": "Melbourne Airport",
        "BOM": "Chhatrapati Shivaji Maharaj International Airport",
        "MAA": "Chennai International Airport",
        "BLR": "Kempegowda International Airport",
        "HYD": "Rajiv Gandhi International Airport",
        "CCU": "Netaji Subhas Chandra Bose International Airport",
        "AMD": "Sardar Vallabhbhai Patel International Airport",
        "COK": "Cochin International Airport",
        "DXB": "Dubai International Airport",
        "DOH": "Hamad International Airport",
        "AUH": "Abu Dhabi International Airport",
        "CAI": "Cairo International Airport",
        "JNB": "O.R. Tambo International Airport",
        "GRU": "São Paulo/Guarulhos International Airport",
        "GIG": "Rio de Janeiro/Galeão International Airport",
        "BOG": "El Dorado International Airport",
        "LIM": "Jorge Chávez International Airport",
        "SCL": "Arturo Merino Benítez International Airport",
        "EZE": "Ezeiza International Airport",
        "YYZ": "Toronto Pearson International Airport",
        "YVR": "Vancouver International Airport",
        "YUL": "Montréal-Pierre Elliott Trudeau International Airport",
        "YYC": "Calgary International Airport"
    ]
    
    private func loadInitialAirports() {
        // Load the static airport coordinates into the database
        airportDatabase = airportCoordinates
        isLoaded = true
    }
    
    /// Get coordinates for an airport by IATA code
    func getCoordinates(for airportCode: String) -> CLLocationCoordinate2D? {
        let code = airportCode.uppercased()
        
        print("🔍 getCoordinates called for: \(code)")
        print("📊 Current airportDatabase keys: \(Array(airportDatabase.keys).sorted())")
        
        // Return from database if available
        if let coordinates = airportDatabase[code] {
            print("✅ Found coordinates for \(code): \(coordinates)")
            return coordinates
        }
        
        print("❌ No coordinates found for \(code) in database")
        
        // If not found, coordinates will be fetched when getCoordinatesAsync is called
        
        return nil
    }
    
    /// Get coordinates for an airport by IATA code (async version)
    func getCoordinatesAsync(for airportCode: String) async -> CLLocationCoordinate2D? {
        let code = airportCode.uppercased()
        
        // Return from local database if available
        if let coordinates = airportDatabase[code] {
            return coordinates
        }
        
        // Use shared coordinate service for missing airports
        if let sharedCoordinates = await SharedAirportService.shared.getAirportCoordinates(for: code) {
            // Cache locally for faster subsequent access
            await MainActor.run {
                airportDatabase[code] = sharedCoordinates
                coordinatesUpdated.send(code)
            }
            return sharedCoordinates
        }
        
        return nil
    }
    
    /// Get complete airport information including city and country
    func getAirportInfo(for airportCode: String) async -> (name: String?, city: String?, country: String?, coordinates: CLLocationCoordinate2D?) {
        let code = airportCode.uppercased()
        
        // Always try to get enhanced info from shared service first for complete data
        if let sharedInfo = await SharedAirportService.shared.getAirportInfo(for: code) {
            // Cache coordinates locally for faster subsequent access
            await MainActor.run {
                airportDatabase[code] = sharedInfo.coordinates
                coordinatesUpdated.send(code)
            }
            return (
                name: sharedInfo.name,
                city: sharedInfo.city,
                country: sharedInfo.country,
                coordinates: sharedInfo.coordinates
            )
        }
        
        // Fallback to local static data if shared service fails
        let localName = airportNames[code]
        let localCoordinates = airportDatabase[code]
        return (name: localName, city: nil, country: nil, coordinates: localCoordinates)
    }
    
    /// Fetch airport coordinates from online database
    private func fetchAirportCoordinates(for airportCode: String) async {
        print("🌐 Starting fallback coordinate lookup for airport: \(airportCode)")
        
        // Using API Ninjas for dynamic coordinate fetching  
        let urlString = "https://api.api-ninjas.com/v1/airports?iata=\(airportCode)"
        
        guard let url = URL(string: urlString) else { 
            print("❌ Invalid URL for airport: \(airportCode)")
            return 
        }
        
        var request = URLRequest(url: url)
        // Replace with your actual API key from https://api.api-ninjas.com/
        request.setValue("AtKK3R3Zn/WiGvJjG4VCkA==gtAtsv7PEeY7GTDB", forHTTPHeaderField: "X-API-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 API Response status: \(httpResponse.statusCode)")
            }
            
            if let dataString = String(data: data, encoding: .utf8) {
                print("📄 API Response data: \(dataString)")
            }
            
            if let airports = try? JSONDecoder().decode([AirportAPIResponse].self, from: data),
               let airport = airports.first {
                
                let coordinate = CLLocationCoordinate2D(
                    latitude: airport.latitude,
                    longitude: airport.longitude
                )
                
                await MainActor.run {
                    airportDatabase[airportCode.uppercased()] = coordinate
                    coordinatesUpdated.send(airportCode.uppercased())
                    print("✅ Fetched and saved coordinates for \(airportCode): \(coordinate)")
                }
            } else {
                print("❌ Failed to decode airport data for \(airportCode)")
            }
        } catch {
            print("❌ Failed to fetch coordinates for \(airportCode): \(error)")
        }
    }
    
    /// Get airport name by IATA code
    func getName(for airportCode: String) -> String? {
        return airportNames[airportCode.uppercased()]
    }
    
    /// Get airport info (name and coordinates) by IATA code
    func getAirportInfo(for airportCode: String) -> (name: String?, coordinates: CLLocationCoordinate2D?) {
        let code = airportCode.uppercased()
        return (
            name: airportNames[code],
            coordinates: airportCoordinates[code]
        )
    }
    
    /// Check if an airport code is supported
    func isSupported(_ airportCode: String) -> Bool {
        return airportCoordinates[airportCode.uppercased()] != nil
    }
    
    /// Get all supported airport codes
    func getAllSupportedCodes() -> [String] {
        return Array(airportCoordinates.keys).sorted()
    }
    
    /// Search airports by partial code or name
    func searchAirports(query: String) -> [(code: String, name: String)] {
        let query = query.lowercased()
        var results: [(code: String, name: String)] = []
        
        for (code, name) in airportNames {
            if code.lowercased().contains(query) || name.lowercased().contains(query) {
                results.append((code: code, name: name))
            }
        }
        
        return results.sorted { $0.code < $1.code }
    }
    
    /// Calculate distance between two airports
    func distance(from: String, to: String) -> CLLocationDistance? {
        guard let fromCoord = getCoordinates(for: from),
              let toCoord = getCoordinates(for: to) else {
            return nil
        }
        
        let fromLocation = CLLocation(latitude: fromCoord.latitude, longitude: fromCoord.longitude)
        let toLocation = CLLocation(latitude: toCoord.latitude, longitude: toCoord.longitude)
        
        return fromLocation.distance(from: toLocation)
    }
    
    /// Get timezone information for an airport (simplified, in real app would use more comprehensive data)
    func getTimezone(for airportCode: String) -> TimeZone? {
        // This is a simplified mapping - in production you'd want more comprehensive timezone data
        let timezoneMapping: [String: String] = [
            "LAX": "America/Los_Angeles",
            "SFO": "America/Los_Angeles",
            "SEA": "America/Los_Angeles",
            "LAS": "America/Los_Angeles",
            "PHX": "America/Phoenix",
            "DEN": "America/Denver",
            "ORD": "America/Chicago",
            "DFW": "America/Chicago",
            "MSP": "America/Chicago",
            "ATL": "America/New_York",
            "JFK": "America/New_York",
            "LGA": "America/New_York",
            "EWR": "America/New_York",
            "BOS": "America/New_York",
            "MIA": "America/New_York",
            "LHR": "Europe/London",
            "CDG": "Europe/Paris",
            "FRA": "Europe/Berlin",
            "AMS": "Europe/Amsterdam",
            "NRT": "Asia/Tokyo",
            "HND": "Asia/Tokyo",
            "ICN": "Asia/Seoul",
            "PVG": "Asia/Shanghai",
            "HKG": "Asia/Hong_Kong",
            "SIN": "Asia/Singapore",
            "SYD": "Australia/Sydney",
            "MEL": "Australia/Melbourne"
        ]
        
        guard let timezoneIdentifier = timezoneMapping[airportCode.uppercased()] else {
            return nil
        }
        
        return TimeZone(identifier: timezoneIdentifier)
    }
}

// MARK: - API Response Models

struct AirportAPIResponse: Codable {
    let iata: String
    let icao: String
    let name: String
    let city: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let elevation_ft: Int
    let timezone: String
}

// MARK: - Extensions

extension Airport {
    /// Update airport with coordinates from AirportService
    mutating func updateCoordinates() {
        let coordinates = AirportService.shared.getCoordinates(for: self.code)
        if let coords = coordinates {
            self = Airport(
                airport: self.airport,
                code: self.code,
                city: self.city,
                latitude: coords.latitude,
                longitude: coords.longitude,
                time: self.time,
                actualTime: self.actualTime,
                terminal: self.terminal,
                gate: self.gate,
                delay: self.delay
            )
        }
    }
    
    /// Get enhanced airport with name and coordinates
    func withEnhancedInfo() -> Airport {
        let (name, coordinates) = AirportService.shared.getAirportInfo(for: self.code)
        
        return Airport(
            airport: name ?? self.airport,
            code: self.code,
            city: self.city,
            latitude: coordinates?.latitude ?? self.latitude,
            longitude: coordinates?.longitude ?? self.longitude,
            time: self.time,
            actualTime: self.actualTime,
            terminal: self.terminal,
            gate: self.gate,
            delay: self.delay
        )
    }
}
