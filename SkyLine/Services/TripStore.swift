//
//  TripStore.swift
//  SkyLine
//
//  Trip management service with CloudKit synchronization
//

import Foundation
import CloudKit
import Combine
import SwiftUI

// MARK: - Trip Store
@MainActor
class TripStore: ObservableObject {
    static let shared = TripStore()
    
    @Published var trips: [Trip] = []
    @Published var tripEntries: [String: [TripEntry]] = [:] // tripId -> entries
    @Published var isLoading = false
    @Published var error: String?
    
    private let cloudKitService = CloudKitService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Caching keys
    private let tripsKey = "CachedTrips"
    private let entriesKey = "CachedTripEntries"
    private let lastSyncKey = "LastTripSyncDate"
    
    // Computed properties
    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming }.sorted { $0.startDate < $1.startDate }
    }
    
    var activeTrips: [Trip] {
        trips.filter { $0.isActive }.sorted { $0.startDate < $1.startDate }
    }
    
    var completedTrips: [Trip] {
        trips.filter { $0.isCompleted }.sorted { $0.endDate > $1.endDate }
    }
    
    var visitedCities: [VisitedCity] {
        completedTrips.compactMap { trip in
            guard let lat = trip.latitude, let lng = trip.longitude else { return nil }
            return VisitedCity(
                name: trip.destination,
                latitude: lat,
                longitude: lng,
                tripCount: 1, // Can be enhanced to count multiple visits
                lastVisited: trip.endDate
            )
        }
    }

    var tripLocations: [TripLocation] {
        trips.compactMap { trip in
            guard let lat = trip.latitude, let lng = trip.longitude else { return nil }

            let status: String
            if trip.isCompleted {
                status = "completed"
            } else if trip.isUpcoming {
                status = "upcoming"
            } else {
                status = "active"
            }

            return TripLocation(
                tripId: trip.id,
                name: trip.destination,
                state: trip.state,
                country: trip.country,
                latitude: lat,
                longitude: lng,
                status: status,
                startDate: trip.startDate,
                endDate: trip.endDate
            )
        }
    }
    
    private init() {
        // Load cached data immediately for offline access
        loadCachedData()
        
        // Only sync from CloudKit during app lifecycle events, not on init
        print("🔄 TripStore: Initialized with \(trips.count) cached trips")
    }
    
    // MARK: - Image Management

    func saveTripImageLocally(_ image: UIImage, tripId: String, theme: String? = nil) -> String? {
        do {
            // Get documents directory
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }

            // Create trips images directory if needed
            let tripsImagesURL = documentsURL.appendingPathComponent("TripImages")
            try? FileManager.default.createDirectory(at: tripsImagesURL, withIntermediateDirectories: true)

            // Save image with trip ID and optional theme as filename
            let filename: String
            if let theme = theme {
                filename = "\(tripId)_\(theme).jpg"
            } else {
                filename = "\(tripId).jpg"
            }
            let fileURL = tripsImagesURL.appendingPathComponent(filename)

            // Compress and save the image
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                return nil
            }

            try imageData.write(to: fileURL)

            // Return the local file URL as a string
            return fileURL.absoluteString

        } catch {
            print("❌ Failed to save trip image locally: \(error)")
            return nil
        }
    }

    /// Generate AI cover images for a trip and save both theme variants
    func generateAndSaveTripImages(destination: String, tripId: String) async -> String? {
        do {
            print("🎨 Generating AI images for: \(destination)")

            // Generate both dark and light mode images concurrently
            let (darkImage, lightImage) = try await TripImageGenerationService.shared.generateTripCoverImages(destination: destination)

            // Save both images locally
            let _ = saveTripImageLocally(darkImage, tripId: tripId, theme: "dark")
            let _ = saveTripImageLocally(lightImage, tripId: tripId, theme: "light")

            // Return the base URL (without theme suffix)
            // The display logic will append the theme based on current mode
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }

            let tripsImagesURL = documentsURL.appendingPathComponent("TripImages")
            let baseURL = tripsImagesURL.appendingPathComponent("\(tripId).jpg")

            print("✅ Generated and saved both theme variants")
            return baseURL.absoluteString

        } catch {
            print("❌ Failed to generate trip images: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Trip Management

    func addTrip(_ trip: Trip) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Save to CloudKit
            let record = trip.toCKRecord()
            let _ = try await cloudKitService.database.save(record)
            
            // Update local store
            trips.append(trip)
            tripEntries[trip.id] = []
            
            // Cache the updated data
            cacheData()
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to add trip: \(error.localizedDescription)"
            return .failure(.saveFailed)
        }
    }
    
    func updateTrip(_ trip: Trip) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Update in CloudKit
            var updatedTrip = trip
            updatedTrip = Trip(
                id: trip.id,
                title: trip.title,
                destination: trip.destination,
                destinationCode: trip.destinationCode,
                startDate: trip.startDate,
                endDate: trip.endDate,
                description: trip.description,
                coverImageURL: trip.coverImageURL,
                latitude: trip.latitude,
                longitude: trip.longitude,
                timeZoneIdentifier: trip.timeZoneIdentifier,
                createdAt: trip.createdAt,
                updatedAt: Date()
            )
            
            let record = updatedTrip.toCKRecord()
            let _ = try await cloudKitService.database.save(record)
            
            // Update local store
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updatedTrip
            }
            
            // Cache the updated data
            cacheData()
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to update trip: \(error.localizedDescription)"
            return .failure(.saveFailed)
        }
    }
    
    func deleteTrip(_ tripId: String) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Delete from CloudKit
            let recordID = CKRecord.ID(recordName: tripId)
            try await cloudKitService.database.deleteRecord(withID: recordID)
            
            // Delete all entries for this trip
            let _ = await deleteAllEntriesForTrip(tripId)
            
            // Update local store
            trips.removeAll { $0.id == tripId }
            tripEntries.removeValue(forKey: tripId)
            
            // Cache the updated data
            cacheData()
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to delete trip: \(error.localizedDescription)"
            return .failure(.deleteFailed)
        }
    }
    
    func fetchTrips() async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        // Check CloudKit account status first
        let accountAvailable = await cloudKitService.checkAccountStatus()
        guard accountAvailable else {
            isLoading = false
            self.error = "CloudKit account not available"
            print("❌ TripStore: CloudKit account not available")
            return .failure(.fetchFailed)
        }
        
        do {
            // Try using createdAt field which is a Date and should be queryable by default
            print("🔄 TripStore: Attempting to fetch Trip records using createdAt field...")
            
            // Use createdAt field with a date that's definitely in the past
            let oldDate = Date(timeIntervalSince1970: 0) // January 1, 1970
            let predicate = NSPredicate(format: "createdAt > %@", oldDate as NSDate)
            let query = CKQuery(recordType: "Trip", predicate: predicate)
            
            let (results, _) = try await cloudKitService.database.records(matching: query)
            
            print("🔄 TripStore: Fetched \(results.count) raw results")
            
            let fetchedTrips = results.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return Trip.fromCKRecord(record)
                case .failure(let error):
                    print("❌ TripStore: Failed to process individual record: \(error)")
                    return nil
                }
            }
            
            print("🔄 TripStore: Fetched \(fetchedTrips.count) trips from CloudKit")
            // Sort trips by start date (newest first) on the client side
            trips = fetchedTrips.sorted { $0.startDate > $1.startDate }
            
            // Fetch entries for all trips
            for trip in trips {
                let _ = await fetchEntriesForTrip(trip.id)
            }
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to fetch trips: \(error.localizedDescription)"
            print("❌ TripStore: Failed to fetch trips: \(error)")
            return .failure(.fetchFailed)
        }
    }
    
    // MARK: - Trip Entry Management
    
    func addEntry(_ entry: TripEntry) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        print("🔍 DEBUG: Attempting to save entry: \(entry.title)")
        
        do {
            // Save to CloudKit
            let record = entry.toCKRecord()
            print("🔍 DEBUG: Created CloudKit record for entry")
            
            let _ = try await cloudKitService.database.save(record)
            print("✅ Successfully saved entry to CloudKit")
            
            // Update local store
            if tripEntries[entry.tripId] == nil {
                tripEntries[entry.tripId] = []
            }
            tripEntries[entry.tripId]?.append(entry)
            tripEntries[entry.tripId]?.sort { $0.timestamp > $1.timestamp }

            // Cache the updated data
            cacheData()

            // Clear route cache for this trip since entries changed
            await RouteCache.shared.clearCache(for: entry.tripId)
            
            isLoading = false
            return .success(())
            
        } catch {
            print("❌ CloudKit save failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            // For development: still save locally even if CloudKit fails
            #if DEBUG
            print("🔧 Development mode: Saving locally despite CloudKit failure")
            
            // Update local store anyway
            if tripEntries[entry.tripId] == nil {
                tripEntries[entry.tripId] = []
            }
            tripEntries[entry.tripId]?.append(entry)
            tripEntries[entry.tripId]?.sort { $0.timestamp > $1.timestamp }
            
            // Cache the updated data
            cacheData()
            
            isLoading = false
            return .success(())
            #else
            isLoading = false
            self.error = "Failed to add entry: \(error.localizedDescription)"
            return .failure(.saveFailed)
            #endif
        }
    }
    
    func updateEntry(_ entry: TripEntry) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil

        do {
            print("🔄 TripStore: Updating entry \(entry.id), isPreview: \(entry.isPreview)")

            // Fetch the existing record from CloudKit first
            let recordID = CKRecord.ID(recordName: entry.id)
            let existingRecord = try await cloudKitService.database.record(for: recordID)

            // Update the fields on the existing record
            existingRecord["tripId"] = entry.tripId
            existingRecord["timestamp"] = entry.timestamp
            existingRecord["entryType"] = entry.entryType.rawValue
            existingRecord["title"] = entry.title
            existingRecord["content"] = entry.content
            if !entry.imageURLs.isEmpty {
                existingRecord["imageURLs"] = entry.imageURLs
            }
            existingRecord["latitude"] = entry.latitude
            existingRecord["longitude"] = entry.longitude
            existingRecord["locationName"] = entry.locationName
            existingRecord["flightId"] = entry.flightId
            existingRecord["isPreview"] = entry.isPreview
            existingRecord["regionName"] = entry.regionName
            existingRecord["regionOrder"] = entry.regionOrder
            existingRecord["isRegionAIGenerated"] = entry.isRegionAIGenerated
            existingRecord["createdAt"] = entry.createdAt
            existingRecord["updatedAt"] = entry.updatedAt

            // Save the modified record back to CloudKit
            let _ = try await cloudKitService.database.save(existingRecord)
            print("✅ TripStore: Updated entry in CloudKit, isPreview: \(entry.isPreview)")

            // Update local store
            if var entries = tripEntries[entry.tripId],
               let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
                tripEntries[entry.tripId] = entries.sorted { $0.timestamp > $1.timestamp }
                print("✅ TripStore: Updated entry in local store, isPreview: \(entry.isPreview)")
            } else {
                print("⚠️ TripStore: Entry not found in local store for tripId: \(entry.tripId)")
            }

            // Cache the updated data
            cacheData()

            // Clear route cache for this trip since entry changed
            await RouteCache.shared.clearCache(for: entry.tripId)

            isLoading = false
            return .success(())

        } catch {
            isLoading = false
            self.error = "Failed to update entry: \(error.localizedDescription)"
            print("❌ TripStore: Failed to update entry: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    func deleteEntry(_ entryId: String, tripId: String) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Delete from CloudKit
            let recordID = CKRecord.ID(recordName: entryId)
            try await cloudKitService.database.deleteRecord(withID: recordID)
            
            // Update local store
            tripEntries[tripId]?.removeAll { $0.id == entryId }

            // Cache the updated data
            cacheData()

            // Clear route cache for this trip since entry was deleted
            await RouteCache.shared.clearCache(for: tripId)
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to delete entry: \(error.localizedDescription)"
            return .failure(.deleteFailed)
        }
    }
    
    func fetchEntriesForTrip(_ tripId: String) async -> Result<Void, TripStoreError> {
        do {
            let predicate = NSPredicate(format: "tripId == %@", tripId)
            let query = CKQuery(recordType: "TripEntry", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            
            let (results, _) = try await cloudKitService.database.records(matching: query)
            
            let fetchedEntries = results.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return TripEntry.fromCKRecord(record)
                case .failure:
                    return nil
                }
            }
            
            tripEntries[tripId] = fetchedEntries
            
            // Cache the updated entries
            cacheData()
            
            return .success(())
            
        } catch {
            self.error = "Failed to fetch entries: \(error.localizedDescription)"
            return .failure(.fetchFailed)
        }
    }
    
    private func deleteAllEntriesForTrip(_ tripId: String) async -> Result<Void, TripStoreError> {
        do {
            let predicate = NSPredicate(format: "tripId == %@", tripId)
            let query = CKQuery(recordType: "TripEntry", predicate: predicate)
            
            let (results, _) = try await cloudKitService.database.records(matching: query)
            
            let recordIDs = results.compactMap { (recordID, result) in
                switch result {
                case .success:
                    return recordID
                case .failure:
                    return nil
                }
            }
            
            for recordID in recordIDs {
                try await cloudKitService.database.deleteRecord(withID: recordID)
            }
            
            return .success(())
            
        } catch {
            return .failure(.deleteFailed)
        }
    }
    
    // MARK: - Convenience Methods
    
    func getTrip(by id: String) -> Trip? {
        trips.first { $0.id == id }
    }
    
    func getEntries(for tripId: String) -> [TripEntry] {
        tripEntries[tripId] ?? []
    }
    
    func getEntriesGroupedByDay(for tripId: String, in timeZone: TimeZone = .current) -> [(Date, [TripEntry])] {
        let entries = getEntries(for: tripId)
        return entries.groupedByDay(in: timeZone)
    }

    // MARK: - Region Grouping Methods

    /// Get entries grouped by region and then by day within each region
    /// Returns: [(regionName, regionOrder, days: [(date, entries)])]
    func getEntriesGroupedByRegionAndDay(for tripId: String, in timeZone: TimeZone = .current) -> [(regionName: String, regionOrder: Int, days: [(Date, [TripEntry])])] {
        let entries = getEntries(for: tripId)
        guard !entries.isEmpty else { return [] }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        // Step 1: Group all entries by calendar day (day is the atomic unit)
        let entriesByDay = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        let sortedDays = entriesByDay.keys.sorted()

        // Step 2: For each day, determine its region by majority vote among entries that have one
        struct DayAssignment {
            let date: Date
            let regionName: String
            let regionOrder: Int
            let entries: [TripEntry]
        }

        let dayAssignments: [DayAssignment] = sortedDays.map { day in
            let dayEntries = (entriesByDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            let withRegion = dayEntries.filter { $0.regionName != nil }

            guard !withRegion.isEmpty else {
                return DayAssignment(date: day, regionName: "Unassigned", regionOrder: Int.max, entries: dayEntries)
            }

            let regionCounts = Dictionary(grouping: withRegion) { $0.regionName! }
            let dominant = regionCounts.max(by: { $0.value.count < $1.value.count })!
            let dominantOrder = dominant.value.compactMap { $0.regionOrder }.min() ?? Int.max

            return DayAssignment(date: day, regionName: dominant.key, regionOrder: dominantOrder, entries: dayEntries)
        }

        // Step 3: Merge consecutive days that share the same region into a single leg.
        // This guarantees strict chronological order with no day appearing in two sections.
        var legs: [(regionName: String, regionOrder: Int, days: [(Date, [TripEntry])])] = []
        var i = 0
        while i < dayAssignments.count {
            let regionName = dayAssignments[i].regionName
            let regionOrder = dayAssignments[i].regionOrder
            var legDays: [(Date, [TripEntry])] = []

            while i < dayAssignments.count && dayAssignments[i].regionName == regionName {
                legDays.append((dayAssignments[i].date, dayAssignments[i].entries))
                i += 1
            }

            legs.append((regionName, regionOrder, legDays))
        }

        return legs
    }

    /// Get entries grouped by region only (for region selector banner).
    /// Derived from the same day-first logic so counts stay consistent.
    func getEntriesGroupedByRegion(for tripId: String) -> [(regionName: String, regionOrder: Int, entryCount: Int)] {
        return getEntriesGroupedByRegionAndDay(for: tripId).map { leg in
            let totalEntries = leg.days.flatMap { $0.1 }.count
            return (leg.regionName, leg.regionOrder, totalEntries)
        }
    }

    /// Get entries for a specific region
    func getEntries(for tripId: String, region: String) -> [TripEntry] {
        getEntries(for: tripId).filter { $0.regionName == region }
    }

    /// Update entry's region assignment
    func updateEntryRegion(_ entryId: String, tripId: String, regionName: String?, regionOrder: Int?, isAIGenerated: Bool = false) async -> Result<Void, TripStoreError> {
        // Find existing entry
        guard var entries = tripEntries[tripId],
              let index = entries.firstIndex(where: { $0.id == entryId }) else {
            return .failure(.notFound)
        }

        let entry = entries[index]

        // Create updated entry with new region
        let updatedEntry = TripEntry(
            id: entry.id,
            tripId: entry.tripId,
            timestamp: entry.timestamp,
            entryType: entry.entryType,
            title: entry.title,
            content: entry.content,
            imageURLs: entry.imageURLs,
            latitude: entry.latitude,
            longitude: entry.longitude,
            locationName: entry.locationName,
            flightId: entry.flightId,
            isPreview: entry.isPreview,
            regionName: regionName,
            regionOrder: regionOrder,
            isRegionAIGenerated: isAIGenerated,
            createdAt: entry.createdAt,
            updatedAt: Date()
        )

        // Update in memory
        entries[index] = updatedEntry
        tripEntries[tripId] = entries
        cacheData()

        // Update in CloudKit
        return await updateEntry(updatedEntry)
    }

    // MARK: - Caching
    
    private func loadCachedData() {
        // Load trips from cache
        if let tripsData = UserDefaults.standard.data(forKey: tripsKey),
           let cachedTrips = try? JSONDecoder().decode([Trip].self, from: tripsData) {
            trips = cachedTrips
            print("✅ TripStore: Loaded \(trips.count) trips from cache")
        }
        
        // Load entries from cache
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey),
           let cachedEntries = try? JSONDecoder().decode([String: [TripEntry]].self, from: entriesData) {
            tripEntries = cachedEntries
            print("✅ TripStore: Loaded \(tripEntries.keys.count) trip entries from cache")
        }
    }
    
    private func cacheData() {
        // Cache trips
        if let tripsData = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(tripsData, forKey: tripsKey)
        }
        
        // Cache entries
        if let entriesData = try? JSONEncoder().encode(tripEntries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
        
        // Update last sync time
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
        
        print("💾 TripStore: Cached \(trips.count) trips and \(tripEntries.keys.count) trip entries")
    }
    
    var shouldSync: Bool {
        guard let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return true // Never synced
        }
        
        // Sync if it's been more than 5 minutes since last sync
        return Date().timeIntervalSince(lastSync) > 300
    }
    
    // MARK: - Public Sync Methods
    
    func syncIfNeeded() async {
        guard shouldSync else {
            print("🔄 TripStore: Skipping sync - recent sync detected")
            return
        }
        
        print("🔄 TripStore: Syncing with CloudKit...")
        await syncWithCloudKit()
    }
    
    func forceSync() async {
        print("🔄 TripStore: Force syncing with CloudKit...")
        await syncWithCloudKit()
    }
    
    private func syncWithCloudKit() async {
        let result = await fetchTrips()
        switch result {
        case .success:
            print("✅ TripStore: Successfully synced \(trips.count) trips from CloudKit")
            cacheData()
        case .failure(let error):
            print("❌ TripStore: Failed to sync from CloudKit: \(error)")
            // Keep cached data, don't fallback to sample data
        }
    }
    
    // MARK: - Data Loading (Legacy)
    
    private func loadPersistedData() async {
        // This method is now deprecated - use syncIfNeeded() instead
        await syncWithCloudKit()
    }
    
    private func loadSampleData() {
        trips = Trip.sampleTrips
        
        for trip in trips {
            tripEntries[trip.id] = TripEntry.sampleEntries(for: trip.id)
        }
    }
}

// MARK: - Trip Location Model (for globe visualization)
struct TripLocation: Identifiable, Hashable {
    let id = UUID()
    let tripId: String
    let name: String
    let state: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let status: String // "completed", "upcoming", "active"
    let startDate: Date
    let endDate: Date

    var coordinate: (lat: Double, lng: Double) {
        (latitude, longitude)
    }
}

// MARK: - Visited City Model
struct VisitedCity: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let tripCount: Int
    let lastVisited: Date

    var coordinate: (lat: Double, lng: Double) {
        (latitude, longitude)
    }
}

// MARK: - Error Types
enum TripStoreError: LocalizedError {
    case saveFailed
    case fetchFailed
    case deleteFailed
    case notFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save data"
        case .fetchFailed:
            return "Failed to fetch data"
        case .deleteFailed:
            return "Failed to delete data"
        case .notFound:
            return "Item not found"
        case .invalidData:
            return "Invalid data format"
        }
    }
}