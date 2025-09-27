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

// MARK: - Shared Airport Service
class SharedAirportService: ObservableObject {
    static let shared = SharedAirportService()
    
    private let container = CKContainer(identifier: "iCloud.com.skyline.flighttracker")
    private lazy var database = container.privateCloudDatabase
    private let recordType = "AirportCoordinates"
    
    // Publisher to notify when coordinates are updated
    let coordinatesUpdated = PassthroughSubject<String, Never>()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get airport coordinates with shared caching
    func getAirportCoordinates(for airportCode: String) async -> CLLocationCoordinate2D? {
        let code = airportCode.uppercased()
        
        // First, try to get from shared CloudKit database
        if let sharedCoordinates = await fetchFromSharedDatabase(code) {
            print("✅ Found shared coordinates for \(code): \(sharedCoordinates)")
            return sharedCoordinates
        }
        
        // If not found, fetch from API and save to shared database
        print("🔍 Not found in shared DB, fetching from API for \(code)")
        if let apiCoordinates = await fetchFromAPI(code) {
            print("🔄 Saving \(code) to shared database...")
            await saveToSharedDatabase(code, coordinates: apiCoordinates)
            return apiCoordinates
        }
        
        return nil
    }
    
    // MARK: - CloudKit Shared Database
    
    private func fetchFromSharedDatabase(_ airportCode: String) async -> CLLocationCoordinate2D? {
        print("🔍 Checking shared CloudKit database for \(airportCode)")
        
        // Use record ID instead of querying fields to avoid queryable field issues
        let recordID = CKRecord.ID(recordName: "airport-\(airportCode)")
        
        do {
            let record = try await database.record(for: recordID)
            
            if let latitude = record["latitude"] as? Double,
               let longitude = record["longitude"] as? Double {
                
                print("📍 Found \(airportCode) in shared database: \(latitude), \(longitude)")
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            } else {
                print("❌ Invalid coordinate data for \(airportCode) in shared database")
            }
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("❌ \(airportCode) not found in shared database")
            } else {
                print("❌ Failed to fetch \(airportCode) from shared database: \(error)")
            }
        }
        
        return nil
    }
    
    private func saveToSharedDatabase(_ airportCode: String, coordinates: CLLocationCoordinate2D) async {
        let recordID = CKRecord.ID(recordName: "airport-\(airportCode)")
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["airportCode"] = airportCode
        record["latitude"] = coordinates.latitude
        record["longitude"] = coordinates.longitude
        record["lastUpdated"] = Date()
        
        do {
            let _ = try await database.save(record)
            print("✅ Saved \(airportCode) coordinates to shared database")
            
            // Notify other users
            await MainActor.run {
                coordinatesUpdated.send(airportCode)
            }
        } catch {
            print("❌ Failed to save \(airportCode) to shared database: \(error)")
        }
    }
    
    // MARK: - API Integration
    
    private func fetchFromAPI(_ airportCode: String) async -> CLLocationCoordinate2D? {
        print("🌐 Fetching \(airportCode) from API Ninjas...")
        
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
                
                let coordinate = CLLocationCoordinate2D(
                    latitude: airport.latitude,
                    longitude: airport.longitude
                )
                
                print("✅ Fetched \(airportCode) from API: \(coordinate)")
                return coordinate
            } else {
                print("❌ Failed to decode airport data for \(airportCode)")
            }
        } catch {
            print("❌ Failed to fetch coordinates for \(airportCode): \(error)")
        }
        
        return nil
    }
}

// MARK: - Airport API Response (reusing from AirportService)
// The AirportAPIResponse struct is already defined in AirportService.swift