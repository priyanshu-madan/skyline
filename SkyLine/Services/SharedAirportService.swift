//
//  SharedAirportService.swift
//  SkyLine
//
//  Shared airport coordinate storage using CloudKit public database
//

import Foundation
import CloudKit
import CoreLocation
import Combine

// MARK: - Airport Info Model
struct AirportInfo {
    let code: String
    let name: String
    let city: String
    let country: String
    let region: String
    let coordinates: CLLocationCoordinate2D
    let timezone: String?
}

// MARK: - Shared Airport Service
class SharedAirportService: ObservableObject {
    static let shared = SharedAirportService()
    
    private let container = CKContainer(identifier: "iCloud.com.skyline.flighttracker")
    private lazy var database = container.privateCloudDatabase
    private let recordType = "AirportCoordinates" // Keep existing type for backward compatibility
    
    // Publisher to notify when airport data is updated
    let airportDataUpdated = PassthroughSubject<String, Never>()
    
    // Concurrency protection and circuit breaker
    private actor ConcurrencyManager {
        private var pendingRequests: Set<String> = []
        private var cache: [String: AirportInfo] = [:]
        private var failureCount: Int = 0
        private var lastFailureTime: Date?
        private let maxFailures = 5
        private let circuitBreakerDuration: TimeInterval = 300 // 5 minutes
        
        func shouldFetch(_ code: String) -> Bool {
            // Check if already pending
            if pendingRequests.contains(code) {
                return false
            }
            
            // Check circuit breaker
            if isCircuitBreakerOpen() {
                print("⚡️ Circuit breaker open, skipping \(code)")
                return false
            }
            
            return true
        }
        
        func markPending(_ code: String) {
            pendingRequests.insert(code)
        }
        
        func markCompleted(_ code: String, info: AirportInfo?) {
            pendingRequests.remove(code)
            if let info = info {
                cache[code] = info
                resetFailures() // Success resets failure count
            }
        }
        
        func markFailed(_ code: String) {
            pendingRequests.remove(code)
            failureCount += 1
            lastFailureTime = Date()
            print("❌ Failure \(failureCount)/\(maxFailures) for \(code)")
        }
        
        func getCached(_ code: String) -> AirportInfo? {
            return cache[code]
        }
        
        private func isCircuitBreakerOpen() -> Bool {
            guard failureCount >= maxFailures,
                  let lastFailure = lastFailureTime else {
                return false
            }
            
            let timeSinceFailure = Date().timeIntervalSince(lastFailure)
            if timeSinceFailure > circuitBreakerDuration {
                resetFailures() // Reset after timeout
                return false
            }
            
            return true
        }
        
        private func resetFailures() {
            failureCount = 0
            lastFailureTime = nil
        }
    }
    
    private let concurrencyManager = ConcurrencyManager()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get airport coordinates with shared caching (backward compatibility)
    func getAirportCoordinates(for airportCode: String) async -> CLLocationCoordinate2D? {
        if let airportInfo = await getAirportInfo(for: airportCode) {
            return airportInfo.coordinates
        }
        return nil
    }
    
    /// Get complete airport information with shared caching
    func getAirportInfo(for airportCode: String) async -> AirportInfo? {
        let code = airportCode.uppercased()
        
        // Check cache first
        if let cached = await concurrencyManager.getCached(code) {
            return cached
        }
        
        // Check if already being fetched to prevent duplicates
        guard await concurrencyManager.shouldFetch(code) else {
            print("⏳ Already fetching \(code), skipping duplicate request")
            return nil
        }
        
        await concurrencyManager.markPending(code)
        
        var result: AirportInfo?
        defer {
            Task {
                if result != nil {
                    await concurrencyManager.markCompleted(code, info: result)
                } else {
                    await concurrencyManager.markFailed(code)
                }
            }
        }
        
        // First, try to get from shared CloudKit database
        if let sharedInfo = await fetchAirportInfoFromSharedDatabase(code) {
            print("✅ Found shared airport info for \(code)")
            result = sharedInfo
            return sharedInfo
        }
        
        // If not found, fetch from API and save to shared database
        print("🔍 Not found in shared DB, fetching from API for \(code)")
        if let apiInfo = await fetchAirportInfoFromAPI(code) {
            print("🔄 Saving \(code) to shared database...")
            await saveAirportInfoToSharedDatabase(apiInfo)
            result = apiInfo
            return apiInfo
        }
        
        result = nil
        return nil
    }
    
    // MARK: - CloudKit Shared Database
    
    private func fetchAirportInfoFromSharedDatabase(_ airportCode: String) async -> AirportInfo? {
        print("🔍 Checking shared CloudKit database for \(airportCode)")
        
        // Use record ID instead of querying fields to avoid queryable field issues
        let recordID = CKRecord.ID(recordName: "airport-\(airportCode)")
        
        do {
            let record = try await database.record(for: recordID)
            
            // Flexible data parsing to handle different record structures
            let latitude: Double?
            let longitude: Double?
            let name: String?
            let city: String?
            let country: String?
            let region: String?
            
            // Try different field names for backward compatibility
            if let lat = record["latitude"] as? Double {
                latitude = lat
            } else if let lat = record["lat"] as? Double {
                latitude = lat
            } else {
                latitude = nil
            }
            
            if let lng = record["longitude"] as? Double {
                longitude = lng
            } else if let lng = record["lng"] as? Double {
                longitude = lng
            } else {
                longitude = nil
            }
            
            name = record["name"] as? String ?? record["airport_name"] as? String
            city = record["city"] as? String ?? record["airport_city"] as? String
            country = record["country"] as? String ?? record["airport_country"] as? String
            region = record["region"] as? String ?? record["airport_region"] as? String
            
            // Validate essential fields
            guard let lat = latitude,
                  let lng = longitude,
                  let airportName = name,
                  let airportCity = city,
                  let airportCountry = country,
                  let airportRegion = region else {
                print("❌ Invalid/incomplete airport data for \(airportCode) in shared database - deleting corrupted record")
                // Delete corrupted record
                try? await database.deleteRecord(withID: recordID)
                return nil
            }
            
            let timezone = record["timezone"] as? String
            
            let airportInfo = AirportInfo(
                code: airportCode,
                name: airportName,
                city: airportCity,
                country: airportCountry,
                region: airportRegion,
                coordinates: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                timezone: timezone
            )
            
            print("📍 Found complete airport info for \(airportCode) in shared database")
            return airportInfo
            
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .unknownItem:
                    print("❌ \(airportCode) not found in shared database")
                case .networkUnavailable, .networkFailure:
                    print("🌐 Network unavailable for \(airportCode), will retry later")
                default:
                    print("❌ CloudKit error fetching \(airportCode): \(ckError)")
                }
            } else {
                print("❌ Failed to fetch \(airportCode) from shared database: \(error)")
            }
        }
        
        return nil
    }
    
    private func saveAirportInfoToSharedDatabase(_ airportInfo: AirportInfo) async {
        let recordID = CKRecord.ID(recordName: "airport-\(airportInfo.code)")
        
        do {
            // First try to fetch existing record to update it
            var record: CKRecord
            do {
                record = try await database.record(for: recordID)
                print("🔄 Updating existing record for \(airportInfo.code)")
            } catch {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: recordType, recordID: recordID)
                print("🆕 Creating new record for \(airportInfo.code)")
            }
            
            // Set all fields
            record["airportCode"] = airportInfo.code
            record["name"] = airportInfo.name
            record["city"] = airportInfo.city
            record["country"] = airportInfo.country
            record["region"] = airportInfo.region
            record["latitude"] = airportInfo.coordinates.latitude
            record["longitude"] = airportInfo.coordinates.longitude
            record["timezone"] = airportInfo.timezone
            record["lastUpdated"] = Date()
            
            let _ = try await database.save(record)
            print("✅ Saved complete airport info for \(airportInfo.code) to shared database")
            
            // Notify other users
            await MainActor.run {
                airportDataUpdated.send(airportInfo.code)
            }
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .serverRecordChanged:
                    print("🔄 Record already exists for \(airportInfo.code), someone else saved it")
                    // This is actually a success case - the data is already there
                case .invalidArguments:
                    if ckError.localizedDescription.contains("invalid attempt to update record from type") {
                        print("🗑️ Schema conflict for \(airportInfo.code), deleting and recreating")
                        // Delete the conflicting record and try again
                        try? await database.deleteRecord(withID: recordID)
                        // Retry with new record
                        let newRecord = CKRecord(recordType: recordType, recordID: recordID)
                        newRecord["airportCode"] = airportInfo.code
                        newRecord["name"] = airportInfo.name
                        newRecord["city"] = airportInfo.city
                        newRecord["country"] = airportInfo.country
                        newRecord["region"] = airportInfo.region
                        newRecord["latitude"] = airportInfo.coordinates.latitude
                        newRecord["longitude"] = airportInfo.coordinates.longitude
                        newRecord["timezone"] = airportInfo.timezone
                        newRecord["lastUpdated"] = Date()
                        try? await database.save(newRecord)
                    } else {
                        print("❌ Invalid arguments saving \(airportInfo.code): \(ckError)")
                    }
                case .requestRateLimited:
                    print("⏳ Rate limited saving \(airportInfo.code), will retry later")
                default:
                    print("❌ CloudKit error saving \(airportInfo.code): \(ckError)")
                }
            } else {
                print("❌ Failed to save \(airportInfo.code) to shared database: \(error)")
            }
        }
    }
    
    // MARK: - API Integration
    
    private func fetchAirportInfoFromAPI(_ airportCode: String) async -> AirportInfo? {
        print("🌐 Fetching complete airport info for \(airportCode) from API Ninjas...")
        
        let urlString = "https://api.api-ninjas.com/v1/airports?iata=\(airportCode)"
        
        guard let url = URL(string: urlString) else { 
            print("❌ Invalid URL for airport: \(airportCode)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("AtKK3R3Zn/WiGvJjG4VCkA==gtAtsv7PEeY7GTDB", forHTTPHeaderField: "X-API-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 API Response status: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    if let dataString = String(data: data, encoding: .utf8) {
                        print("📄 API Error response: \(dataString)")
                    }
                    return nil
                }
            }
            
            let airports = try JSONDecoder().decode([AirportAPIResponse].self, from: data)
            if let airport = airports.first {
                
                let airportInfo = AirportInfo(
                    code: airportCode.uppercased(),
                    name: airport.name,
                    city: airport.city,
                    country: airport.country,
                    region: airport.region,
                    coordinates: CLLocationCoordinate2D(
                        latitude: airport.latitude,
                        longitude: airport.longitude
                    ),
                    timezone: airport.timezone
                )
                
                print("✅ Fetched complete airport info for \(airportCode) from API")
                return airportInfo
            } else {
                print("❌ Failed to decode airport data for \(airportCode)")
            }
        } catch {
            print("❌ Failed to fetch airport info for \(airportCode): \(error)")
        }
        
        return nil
    }
}

// MARK: - Airport API Response (reusing from AirportService)
// The AirportAPIResponse struct is already defined in AirportService.swift