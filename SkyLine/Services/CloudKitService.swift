//
//  CloudKitService.swift
//  SkyLine
//
//  CloudKit integration for cross-device flight data synchronization
//

import Foundation
import CloudKit
import Combine
import SwiftUI

// MARK: - CloudKit Service
class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    private let container: CKContainer
    let database: CKDatabase  // Made public for TripStore access
    let publicDatabase: CKDatabase  // Made public for trip destinations
    
    @Published var isSyncing = false
    @Published var syncError: String?
    
    // CloudKit Record Types
    private let flightRecordType = "Flight"
    private let searchHistoryRecordType = "SearchHistory"
    
    private init() {
        // Use the specific container configured in Xcode
        container = CKContainer(identifier: "iCloud.com.skyline.flighttracker")
        database = container.privateCloudDatabase
        publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - Schema Initialization
    
    private func initializeSchema() async {
        // Create a sample flight record to establish the schema
        let sampleRecord = CKRecord(recordType: flightRecordType)
        sampleRecord["flightNumber"] = "SCHEMA_INIT"
        sampleRecord["airline"] = "Schema Initialization"
        sampleRecord["status"] = "boarding"
        sampleRecord["dataSource"] = "manual"
        
        do {
            let _ = try await database.save(sampleRecord)
            // Delete the sample record immediately
            try await database.deleteRecord(withID: sampleRecord.recordID)
            print("✅ CloudKit schema initialized")
        } catch {
            print("⚠️ Schema initialization: \(error)")
        }
        
        // Initialize search history schema
        let sampleSearchRecord = CKRecord(recordType: searchHistoryRecordType)
        sampleSearchRecord["query"] = "SCHEMA_INIT"
        sampleSearchRecord["order"] = 0
        
        do {
            let _ = try await database.save(sampleSearchRecord)
            try await database.deleteRecord(withID: sampleSearchRecord.recordID)
            print("✅ Search history schema initialized")
        } catch {
            print("⚠️ Search schema initialization: \(error)")
        }
        
        // Initialize destination images schema
        await initializeDestinationImagesSchema()
        
        // Initialize trips schema
        await initializeTripsSchema()
        
        // Initialize configuration schema
        await initializeConfigurationSchema()
    }
    
    // MARK: - Destination Images Schema
    
    private func initializeDestinationImagesSchema() async {
        let destinationImagesRecordType = "DestinationImage"
        
        // Create a sample destination image record to initialize schema
        let sampleDestinationRecord = CKRecord(recordType: destinationImagesRecordType)
        sampleDestinationRecord["airportCode"] = "SCHEMA_INIT"
        sampleDestinationRecord["cityName"] = "Schema Initialization"
        sampleDestinationRecord["countryName"] = "Test"
        sampleDestinationRecord["imageURL"] = ""
        
        // Create a temporary image for schema initialization
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema_init.jpg")
        
        // Create a minimal 1x1 pixel image
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let tempImage = renderer.image { context in
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        
        do {
            if let imageData = tempImage.jpegData(compressionQuality: 0.1) {
                try imageData.write(to: tempURL)
                sampleDestinationRecord["image"] = CKAsset(fileURL: tempURL)
            }
            
            let _ = try await publicDatabase.save(sampleDestinationRecord)
            try await publicDatabase.deleteRecord(withID: sampleDestinationRecord.recordID)
            print("✅ Destination images schema initialized")
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
            // Seed initial destination images if needed
            // Note: Uncomment this line once DestinationImageSeeder is added to the project
            // await DestinationImageSeeder.shared.seedIfNeeded()
            
        } catch {
            print("⚠️ Destination images schema initialization: \(error)")
            // Clean up temporary file on error
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    // MARK: - Trips Schema
    
    private func initializeTripsSchema() async {
        // Initialize Trip record type
        let sampleTripRecord = CKRecord(recordType: "Trip")
        sampleTripRecord["title"] = "Schema Initialization"
        sampleTripRecord["destination"] = "Test"
        sampleTripRecord["destinationCode"] = ""
        sampleTripRecord["startDate"] = Date()
        sampleTripRecord["endDate"] = Date()
        sampleTripRecord["description"] = ""
        sampleTripRecord["coverImageURL"] = ""
        sampleTripRecord["latitude"] = 0.0
        sampleTripRecord["longitude"] = 0.0
        sampleTripRecord["createdAt"] = Date()
        sampleTripRecord["updatedAt"] = Date()
        
        do {
            let _ = try await database.save(sampleTripRecord)
            try await database.deleteRecord(withID: sampleTripRecord.recordID)
            print("✅ Trip schema initialized")
        } catch {
            print("⚠️ Trip schema initialization: \(error)")
        }
        
        // Initialize TripEntry record type
        let sampleEntryRecord = CKRecord(recordType: "TripEntry")
        sampleEntryRecord["tripId"] = "SCHEMA_INIT"
        sampleEntryRecord["timestamp"] = Date()
        sampleEntryRecord["entryType"] = "note"
        sampleEntryRecord["title"] = "Schema Initialization"
        sampleEntryRecord["content"] = "Test"
        sampleEntryRecord["imageURLs"] = ["https://example.com/placeholder.jpg"] // Non-empty array for schema
        sampleEntryRecord["latitude"] = 0.0
        sampleEntryRecord["longitude"] = 0.0
        sampleEntryRecord["locationName"] = ""
        sampleEntryRecord["createdAt"] = Date()
        sampleEntryRecord["updatedAt"] = Date()
        
        do {
            let _ = try await database.save(sampleEntryRecord)
            try await database.deleteRecord(withID: sampleEntryRecord.recordID)
            print("✅ TripEntry schema initialized")
        } catch {
            print("⚠️ TripEntry schema initialization: \(error)")
        }
    }
    
    // MARK: - Configuration Schema
    
    private func initializeConfigurationSchema() async {
        // Initialize Configuration record type for BoardingPassConfig
        let sampleConfigRecord = CKRecord(recordType: "Configuration")
        sampleConfigRecord["configType"] = "BoardingPassConfig"
        sampleConfigRecord["configData"] = "{\"validationRules\":{\"flightNumberPattern\":\"^[A-Z]{2,3}[0-9]{1,4}$\"}}"
        sampleConfigRecord["lastModified"] = Date()
        
        do {
            let _ = try await database.save(sampleConfigRecord)
            try await database.deleteRecord(withID: sampleConfigRecord.recordID)
            print("✅ Configuration schema initialized")
        } catch {
            print("⚠️ Configuration schema initialization: \(error)")
        }
    }
    
    // MARK: - Account Status
    
    func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print("✅ CloudKit account available")
                // Initialize schema on first access
                await initializeSchema()
                return true
            case .noAccount:
                print("❌ No iCloud account")
                return false
            case .restricted:
                print("❌ CloudKit account restricted")
                return false
            case .couldNotDetermine:
                print("❌ Could not determine CloudKit account status")
                return false
            case .temporarilyUnavailable:
                print("⏳ CloudKit temporarily unavailable")
                return false
            @unknown default:
                print("❌ Unknown CloudKit account status")
                return false
            }
        } catch {
            print("❌ Error checking CloudKit account status: \(error)")
            return false
        }
    }
    
    // MARK: - Flight Operations
    
    func saveFlights(_ flights: [Flight]) async -> Result<Void, CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        await MainActor.run { isSyncing = true }
        
        do {
            // Convert flights to CKRecords
            let records = flights.map { createFlightRecord(from: $0) }
            
            // Save records in batches
            let batchSize = 100
            for i in stride(from: 0, to: records.count, by: batchSize) {
                let endIndex = min(i + batchSize, records.count)
                let batch = Array(records[i..<endIndex])
                
                let operation = CKModifyRecordsOperation(recordsToSave: batch)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .userInitiated
                
                try await database.add(operation)
            }
            
            await MainActor.run { 
                isSyncing = false
                syncError = nil
            }
            
            print("✅ Saved \(flights.count) flights to CloudKit")
            return .success(())
            
        } catch {
            await MainActor.run { 
                isSyncing = false
                syncError = error.localizedDescription
            }
            print("❌ Failed to save flights to CloudKit: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    func fetchFlights() async -> Result<[Flight], CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        await MainActor.run { isSyncing = true }
        
        do {
            // Use a simpler query approach that works with CloudKit
            // Exclude empty flight numbers and schema initialization records
            let query = CKQuery(recordType: flightRecordType, predicate: NSPredicate(format: "flightNumber != %@ AND flightNumber != %@", "", "SCHEMA_INIT"))
            
            let (matchResults, _) = try await database.records(matching: query)
            
            let flights = matchResults.compactMap { (recordID, result) -> Flight? in
                switch result {
                case .success(let record):
                    return createFlight(from: record)
                case .failure(let error):
                    print("❌ Failed to fetch record \(recordID): \(error)")
                    return nil
                }
            }
            
            await MainActor.run { 
                isSyncing = false
                syncError = nil
            }
            
            print("✅ Fetched \(flights.count) flights from CloudKit")
            return .success(flights)
            
        } catch {
            await MainActor.run { 
                isSyncing = false
                syncError = error.localizedDescription
            }
            print("❌ Failed to fetch flights from CloudKit: \(error)")
            return .failure(.fetchFailed)
        }
    }
    
    func deleteFlight(with id: String) async -> Result<Void, CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        do {
            let recordID = CKRecord.ID(recordName: id)
            try await database.deleteRecord(withID: recordID)
            
            print("✅ Deleted flight \(id) from CloudKit")
            return .success(())
            
        } catch {
            print("❌ Failed to delete flight from CloudKit: \(error)")
            return .failure(.deleteFailed)
        }
    }
    
    // MARK: - Search History Operations
    
    func saveSearchHistory(_ searches: [String]) async -> Result<Void, CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        // Don't save empty search history to avoid CloudKit schema issues
        guard !searches.isEmpty else {
            print("📝 Skipping empty search history save")
            return .success(())
        }
        
        do {
            // Use a single record to store all search history as an array
            let recordID = CKRecord.ID(recordName: "user_search_history")
            let record = CKRecord(recordType: searchHistoryRecordType, recordID: recordID)
            record["searchQueries"] = searches
            record["lastUpdated"] = Date()
            
            try await database.save(record)
            
            print("✅ Saved \(searches.count) search queries to CloudKit")
            return .success(())
            
        } catch {
            print("❌ Failed to save search history to CloudKit: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    func fetchSearchHistory() async -> Result<[String], CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        do {
            // Fetch the single search history record directly
            let recordID = CKRecord.ID(recordName: "user_search_history")
            let record = try await database.record(for: recordID)
            
            let searches = record["searchQueries"] as? [String] ?? []
            
            print("✅ Fetched \(searches.count) search queries from CloudKit")
            return .success(searches)
            
        } catch {
            // If record doesn't exist yet, return empty array
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 No search history found in CloudKit yet")
                return .success([])
            }
            
            print("❌ Failed to fetch search history from CloudKit: \(error)")
            return .failure(.fetchFailed)
        }
    }
    
    // MARK: - Record Conversion
    
    private func createFlightRecord(from flight: Flight) -> CKRecord {
        let record = CKRecord(recordType: flightRecordType, recordID: CKRecord.ID(recordName: flight.id))
        
        // Basic flight info
        record["flightNumber"] = flight.flightNumber
        record["airline"] = flight.airline
        record["status"] = flight.status.rawValue
        record["progress"] = flight.progress ?? 0.0
        record["flightDate"] = flight.flightDate
        record["dataSource"] = flight.dataSource.rawValue
        record["date"] = flight.date
        
        // Departure airport
        record["departureAirport"] = flight.departure.airport
        record["departureCode"] = flight.departure.code
        record["departureCity"] = flight.departure.city
        record["departureLatitude"] = flight.departure.latitude
        record["departureLongitude"] = flight.departure.longitude
        record["departureTime"] = flight.departure.time
        record["departureActualTime"] = flight.departure.actualTime
        record["departureTerminal"] = flight.departure.terminal
        record["departureGate"] = flight.departure.gate
        record["departureDelay"] = flight.departure.delay
        
        // Arrival airport
        record["arrivalAirport"] = flight.arrival.airport
        record["arrivalCode"] = flight.arrival.code
        record["arrivalCity"] = flight.arrival.city
        record["arrivalLatitude"] = flight.arrival.latitude
        record["arrivalLongitude"] = flight.arrival.longitude
        record["arrivalTime"] = flight.arrival.time
        record["arrivalActualTime"] = flight.arrival.actualTime
        record["arrivalTerminal"] = flight.arrival.terminal
        record["arrivalGate"] = flight.arrival.gate
        record["arrivalDelay"] = flight.arrival.delay
        
        // Aircraft info
        if let aircraft = flight.aircraft {
            record["aircraftType"] = aircraft.type
            record["aircraftRegistration"] = aircraft.registration
            record["aircraftIcao24"] = aircraft.icao24
        }
        
        // Current position
        if let position = flight.currentPosition {
            record["positionLatitude"] = position.latitude
            record["positionLongitude"] = position.longitude
            record["positionAltitude"] = position.altitude
            record["positionSpeed"] = position.speed
            record["positionHeading"] = position.heading
            record["positionIsGround"] = position.isGround
            record["positionLastUpdate"] = position.lastUpdate
        }
        
        return record
    }
    
    private func createFlight(from record: CKRecord) -> Flight? {
        guard let flightNumber = record["flightNumber"] as? String,
              let airline = record["airline"] as? String,
              let statusRaw = record["status"] as? String,
              let status = FlightStatus(rawValue: statusRaw),
              let dataSourceRaw = record["dataSource"] as? String,
              let dataSource = DataSource(rawValue: dataSourceRaw) else {
            return nil
        }
        
        // Create departure airport
        let departure = Airport(
            airport: record["departureAirport"] as? String ?? "",
            code: record["departureCode"] as? String ?? "",
            city: record["departureCity"] as? String ?? "",
            latitude: record["departureLatitude"] as? Double,
            longitude: record["departureLongitude"] as? Double,
            time: record["departureTime"] as? String ?? "",
            actualTime: record["departureActualTime"] as? String,
            terminal: record["departureTerminal"] as? String,
            gate: record["departureGate"] as? String,
            delay: record["departureDelay"] as? Int
        )
        
        // Create arrival airport
        let arrival = Airport(
            airport: record["arrivalAirport"] as? String ?? "",
            code: record["arrivalCode"] as? String ?? "",
            city: record["arrivalCity"] as? String ?? "",
            latitude: record["arrivalLatitude"] as? Double,
            longitude: record["arrivalLongitude"] as? Double,
            time: record["arrivalTime"] as? String ?? "",
            actualTime: record["arrivalActualTime"] as? String,
            terminal: record["arrivalTerminal"] as? String,
            gate: record["arrivalGate"] as? String,
            delay: record["arrivalDelay"] as? Int
        )
        
        // Create aircraft if data exists
        var aircraft: Aircraft? = nil
        if let type = record["aircraftType"] as? String,
           let registration = record["aircraftRegistration"] as? String,
           let icao24 = record["aircraftIcao24"] as? String {
            aircraft = Aircraft(type: type, registration: registration, icao24: icao24)
        }
        
        // Create current position if data exists
        var currentPosition: FlightPosition? = nil
        if let lat = record["positionLatitude"] as? Double,
           let lng = record["positionLongitude"] as? Double,
           let altitude = record["positionAltitude"] as? Double,
           let speed = record["positionSpeed"] as? Double,
           let heading = record["positionHeading"] as? Double {
            currentPosition = FlightPosition(
                latitude: lat,
                longitude: lng,
                altitude: altitude,
                speed: speed,
                heading: heading,
                isGround: record["positionIsGround"] as? Bool,
                lastUpdate: record["positionLastUpdate"] as? String
            )
        }
        
        return Flight(
            id: record.recordID.recordName,
            flightNumber: flightNumber,
            airline: airline,
            departure: departure,
            arrival: arrival,
            status: status,
            aircraft: aircraft,
            currentPosition: currentPosition,
            progress: record["progress"] as? Double,
            flightDate: record["flightDate"] as? String,
            dataSource: dataSource,
            date: record["date"] as? Date ?? extractDateFromDepartureTime(record["departureTime"] as? String)
        )
    }
    
    private func extractDateFromDepartureTime(_ departureTime: String?) -> Date {
        guard let departureTime = departureTime else {
            print("⚠️ No departure time found, using current date as fallback")
            return Date()
        }
        
        // Try to parse as ISO8601 date (which includes the date component)
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: departureTime) {
            print("✅ Extracted date from ISO8601 departure time: \(date)")
            return date
        }
        
        // If it's just a time string (like "14:25"), we can't extract a proper date
        // Use current date but log this for debugging
        print("⚠️ Departure time '\(departureTime)' is just time, not full date. Using current date as fallback")
        return Date()
    }
    
    // MARK: - Conflict Resolution & Offline Support
    
    func handleConflictResolution(localFlights: [Flight], cloudFlights: [Flight]) -> [Flight] {
        var resolvedFlights: [String: Flight] = [:]
        
        // Start with local flights
        for flight in localFlights {
            resolvedFlights[flight.id] = flight
        }
        
        // Merge with cloud flights using enhanced data priority
        for cloudFlight in cloudFlights {
            if let localFlight = resolvedFlights[cloudFlight.id] {
                // Conflict detected - prefer local if it has enhanced airport data
                let localHasEnhancedData = !localFlight.departure.city.isEmpty && !localFlight.arrival.city.isEmpty
                let cloudHasEnhancedData = !cloudFlight.departure.city.isEmpty && !cloudFlight.arrival.city.isEmpty
                
                if localHasEnhancedData && !cloudHasEnhancedData {
                    // Keep local version with enhanced data
                    print("🔄 Conflict resolved for flight \(localFlight.flightNumber): keeping enhanced local version")
                } else if !localHasEnhancedData && cloudHasEnhancedData {
                    // Use cloud version with enhanced data
                    resolvedFlights[cloudFlight.id] = cloudFlight
                    print("🔄 Conflict resolved for flight \(cloudFlight.flightNumber): using enhanced CloudKit version")
                } else {
                    // Both have enhanced data or both lack it - prefer CloudKit (server wins)
                    resolvedFlights[cloudFlight.id] = cloudFlight
                    print("🔄 Conflict resolved for flight \(cloudFlight.flightNumber): using CloudKit version")
                }
            } else {
                // New flight from cloud
                resolvedFlights[cloudFlight.id] = cloudFlight
            }
        }
        
        return Array(resolvedFlights.values)
    }
    
    func isOffline() async -> Bool {
        do {
            // Try a simple CloudKit operation to test connectivity
            let query = CKQuery(recordType: flightRecordType, predicate: NSPredicate(value: true))
            
            let (_, _) = try await database.records(matching: query, resultsLimit: 1)
            return false // Online
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .networkUnavailable, .networkFailure:
                    return true // Offline
                default:
                    return false // Other error, assume online
                }
            }
            return true // Unknown error, assume offline
        }
    }
    
    func syncWhenOnline() async {
        // Check if we're online
        let offline = await isOffline()
        guard !offline else {
            print("📱 Device is offline - sync will be retried later")
            return
        }
        
        // Perform sync operations
        print("🌐 Device is online - performing sync")
    }
    
    // MARK: - Background Sync
    
    func enableBackgroundSync() {
        // Subscribe to CloudKit notifications for real-time sync
        let subscription = CKQuerySubscription(
            recordType: flightRecordType,
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        
        Task {
            do {
                try await database.save(subscription)
                print("✅ CloudKit background sync subscription created")
            } catch {
                print("❌ Failed to create CloudKit subscription: \(error)")
            }
        }
    }
    
    // MARK: - Sync Operations
    
    func performFullSync() async -> Result<[Flight], CloudKitError> {
        guard await checkAccountStatus() else {
            return .failure(.accountNotAvailable)
        }
        
        await MainActor.run { 
            isSyncing = true
            syncError = nil
        }
        
        // Fetch all flights from CloudKit
        let result = await fetchFlights()
        
        await MainActor.run { isSyncing = false }
        
        return result
    }
    
    func syncSearchHistory(local: [String]) async -> Result<[String], CloudKitError> {
        // First save local history to CloudKit
        let saveResult = await saveSearchHistory(local)
        guard case .success = saveResult else {
            return .failure(.saveFailed)
        }
        
        // Then fetch merged history
        return await fetchSearchHistory()
    }
}

// MARK: - CloudKit Error Types
enum CloudKitError: LocalizedError {
    case accountNotAvailable
    case saveFailed
    case fetchFailed
    case deleteFailed
    case networkError
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .accountNotAvailable:
            return "iCloud account not available. Please sign in to iCloud in Settings."
        case .saveFailed:
            return "Failed to save data to iCloud"
        case .fetchFailed:
            return "Failed to fetch data from iCloud"
        case .deleteFailed:
            return "Failed to delete data from iCloud"
        case .networkError:
            return "Network connection error"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        }
    }
}