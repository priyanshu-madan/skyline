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
    
    private init() {
        loadSampleData() // Load sample data for development
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
                createdAt: trip.createdAt,
                updatedAt: Date()
            )
            
            let record = updatedTrip.toCKRecord()
            let _ = try await cloudKitService.database.save(record)
            
            // Update local store
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updatedTrip
            }
            
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
        
        do {
            let query = CKQuery(recordType: "Trip", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
            
            let (results, _) = try await cloudKitService.database.records(matching: query)
            
            let fetchedTrips = results.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return Trip.fromCKRecord(record)
                case .failure:
                    return nil
                }
            }
            
            trips = fetchedTrips
            
            // Fetch entries for all trips
            for trip in trips {
                let _ = await fetchEntriesForTrip(trip.id)
            }
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to fetch trips: \(error.localizedDescription)"
            return .failure(.fetchFailed)
        }
    }
    
    // MARK: - Trip Entry Management
    
    func addEntry(_ entry: TripEntry) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Save to CloudKit
            let record = entry.toCKRecord()
            let _ = try await cloudKitService.database.save(record)
            
            // Update local store
            if tripEntries[entry.tripId] == nil {
                tripEntries[entry.tripId] = []
            }
            tripEntries[entry.tripId]?.append(entry)
            tripEntries[entry.tripId]?.sort { $0.timestamp > $1.timestamp }
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to add entry: \(error.localizedDescription)"
            return .failure(.saveFailed)
        }
    }
    
    func updateEntry(_ entry: TripEntry) async -> Result<Void, TripStoreError> {
        isLoading = true
        error = nil
        
        do {
            // Update in CloudKit
            var updatedEntry = entry
            updatedEntry = TripEntry(
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
                createdAt: entry.createdAt,
                updatedAt: Date()
            )
            
            let record = updatedEntry.toCKRecord()
            let _ = try await cloudKitService.database.save(record)
            
            // Update local store
            if var entries = tripEntries[entry.tripId],
               let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = updatedEntry
                tripEntries[entry.tripId] = entries.sorted { $0.timestamp > $1.timestamp }
            }
            
            isLoading = false
            return .success(())
            
        } catch {
            isLoading = false
            self.error = "Failed to update entry: \(error.localizedDescription)"
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
    
    func getEntriesGroupedByDay(for tripId: String) -> [(Date, [TripEntry])] {
        let entries = getEntries(for: tripId)
        return entries.groupedByDay()
    }
    
    // MARK: - Sample Data (Development)
    
    private func loadSampleData() {
        #if DEBUG
        trips = Trip.sampleTrips
        
        for trip in trips {
            tripEntries[trip.id] = TripEntry.sampleEntries(for: trip.id)
        }
        #endif
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