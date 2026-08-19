//
//  PlaceStore.swift
//  SkyLine
//
//  Place / Visit management service with CloudKit synchronization
//

import Foundation
import CoreLocation
import CloudKit
import Combine
import SwiftUI

// MARK: - Place Store
@MainActor
class PlaceStore: ObservableObject {
    static let shared = PlaceStore()

    @Published var places: [Place] = []
    @Published var visits: [Visit] = []
    /// placeId -> visits, newest first. Rebuilt on every mutation so the query
    /// helpers stay O(1) per place instead of O(n).
    @Published private(set) var visitsByPlaceId: [String: [Visit]] = [:]
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var cloudKitAvailable = false
    @Published var error: String?

    private let cloudKitService = CloudKitService.shared
    private let schemaService = PlaceSchemaService.shared
    private var cancellables = Set<AnyCancellable>()

    // Caching keys
    private let placesKey = "CachedPlaces"
    private let visitsKey = "CachedVisits"
    private let lastSyncKey = "LastPlaceSyncDate"
    private let pendingPlacesKey = "PendingPlaceWrites"
    private let pendingVisitsKey = "PendingVisitWrites"

    // MARK: - Dedup Tuning

    /// Same name inside this radius => same place.
    static let sameNameMergeRadius: CLLocationDistance = 150
    /// Same spot regardless of name inside this radius.
    static let sameSpotMergeRadius: CLLocationDistance = 40

    /// Records that could not reach CloudKit yet. Retried whenever the account
    /// becomes available again.
    private var pendingPlaceIds: Set<String> = []
    private var pendingVisitIds: Set<String> = []
    private var hasInitializedSchema = false

    private init() {
        loadCachedData()
        loadPendingWrites()
        observeAccountChanges()

        print("📍 PlaceStore: Initialized with \(places.count) cached places, \(visits.count) cached visits")

        // iCloud availability is NOT latched here - see refreshCloudKitAvailability().
        Task { await refreshCloudKitAvailability() }
    }

    // MARK: - Account Availability

    /// iCloud is frequently not ready at launch: the user may sign in later, or
    /// switch accounts while the app runs. Availability must be re-checked on
    /// every `.CKAccountChanged`, never latched at init - the exact bug fixed in
    /// `FlightStore.setupCloudKitSync()`.
    private func observeAccountChanges() {
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .sink { [weak self] _ in
                Task { await self?.refreshCloudKitAvailability() }
            }
            .store(in: &cancellables)
    }

    /// Re-checks iCloud, bootstraps the schema once, flushes anything queued
    /// while offline, and pulls on the unavailable -> available transition.
    /// Safe to call repeatedly.
    func refreshCloudKitAvailability() async {
        let available = await cloudKitService.checkAccountStatus()
        let wasAvailable = cloudKitAvailable
        cloudKitAvailable = available

        guard available else {
            print("⚠️ PlaceStore: iCloud unavailable - serving \(places.count) cached places")
            return
        }

        if !hasInitializedSchema {
            hasInitializedSchema = true
            await schemaService.initializePlaceSchema()
        }

        await flushPendingWrites()

        if !wasAvailable || shouldSync {
            print("🔄 PlaceStore: iCloud available (was: \(wasAvailable)) - syncing")
            let _ = await fetchAll()
        }
    }

    // MARK: - Place Management

    func addPlace(_ place: Place) async -> Result<Void, PlaceStoreError> {
        isLoading = true
        error = nil

        // Local-first: the place must survive a failed/offline write, otherwise
        // a swipe made on a plane disappears.
        upsertLocalPlace(place)
        cacheData()

        do {
            try await saveRecordUpserting(
                recordID: CKRecord.ID(recordName: place.id),
                recordType: Place.recordType
            ) { place.apply(to: $0) }

            pendingPlaceIds.remove(place.id)
            savePendingWrites()
            isLoading = false
            print("✅ PlaceStore: Saved place \(place.name)")
            return .success(())
        } catch {
            pendingPlaceIds.insert(place.id)
            savePendingWrites()
            isLoading = false
            self.error = "Failed to save place: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to save place \(place.name): \(error)")
            return .failure(.saveFailed)
        }
    }

    func updatePlace(_ place: Place) async -> Result<Void, PlaceStoreError> {
        await addPlace(place.touched())
    }

    /// Deletes a place and cascades to its visits (visits reference places by
    /// plain String id - there are no CKReferences anywhere in this app).
    func deletePlace(_ placeId: String) async -> Result<Void, PlaceStoreError> {
        isLoading = true
        error = nil

        let visitIds = visits.filter { $0.placeId == placeId }.map { $0.id }
        for visitId in visitIds {
            let _ = await deleteVisit(visitId)
        }

        places.removeAll { $0.id == placeId }
        pendingPlaceIds.remove(placeId)
        cacheData()
        savePendingWrites()

        do {
            try await deleteRecordIfPresent(CKRecord.ID(recordName: placeId))
            isLoading = false
            print("✅ PlaceStore: Deleted place \(placeId) and \(visitIds.count) visits")
            return .success(())
        } catch {
            isLoading = false
            self.error = "Failed to delete place: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to delete place \(placeId): \(error)")
            return .failure(.deleteFailed)
        }
    }

    // MARK: - Deduplication

    /// Finds the stored place that `candidate` is really the same spot as.
    /// 1. identical external identifier (MapKit id, IATA code, ...)
    /// 2. same normalized name within `sameNameMergeRadius`
    /// 3. any place within `sameSpotMergeRadius`
    func existingPlace(matching candidate: Place) -> Place? {
        if let identifier = candidate.externalIdentifier, !identifier.isEmpty,
           let match = places.first(where: { $0.externalIdentifier == identifier }) {
            return match
        }

        if let match = places.first(where: { $0.id == candidate.id }) {
            return match
        }

        let name = candidate.normalizedName
        if !name.isEmpty {
            let named = places.filter {
                $0.normalizedName == name && $0.distance(to: candidate) <= PlaceStore.sameNameMergeRadius
            }
            if let closest = named.min(by: { $0.distance(to: candidate) < $1.distance(to: candidate) }) {
                return closest
            }
        }

        let nearby = places.filter { $0.distance(to: candidate) <= PlaceStore.sameSpotMergeRadius }
        return nearby.min { $0.distance(to: candidate) < $1.distance(to: candidate) }
    }

    /// Returns the canonical stored place for `candidate`, creating it if new
    /// and enriching it (never overwriting a user-visible field with nil) if it
    /// already exists.
    @discardableResult
    func upsertPlace(_ candidate: Place) async -> Result<Place, PlaceStoreError> {
        if let existing = existingPlace(matching: candidate) {
            let merged = existing.merged(with: candidate)
            if merged.isEquivalent(to: existing) {
                return .success(existing)
            }
            let result = await addPlace(merged)
            switch result {
            case .success:
                return .success(merged)
            case .failure(let storeError):
                // The merge is already in the local store; report the write failure.
                return .failure(storeError)
            }
        }

        let result = await addPlace(candidate)
        switch result {
        case .success:
            return .success(candidate)
        case .failure(let storeError):
            return .failure(storeError)
        }
    }

    // MARK: - Visit Management

    func addVisit(_ visit: Visit) async -> Result<Void, PlaceStoreError> {
        isLoading = true
        error = nil

        upsertLocalVisit(visit)
        cacheData()

        do {
            try await saveRecordUpserting(
                recordID: CKRecord.ID(recordName: visit.id),
                recordType: Visit.recordType
            ) { visit.apply(to: $0) }

            pendingVisitIds.remove(visit.id)
            savePendingWrites()
            isLoading = false
            print("✅ PlaceStore: Saved visit \(visit.id) verdict: \(visit.verdict?.rawValue ?? "unrated")")
            return .success(())
        } catch {
            pendingVisitIds.insert(visit.id)
            savePendingWrites()
            isLoading = false
            self.error = "Failed to save visit: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to save visit \(visit.id): \(error)")
            return .failure(.saveFailed)
        }
    }

    func updateVisit(_ visit: Visit) async -> Result<Void, PlaceStoreError> {
        await addVisit(visit.touched())
    }

    func deleteVisit(_ visitId: String) async -> Result<Void, PlaceStoreError> {
        error = nil

        visits.removeAll { $0.id == visitId }
        pendingVisitIds.remove(visitId)
        cacheData()
        savePendingWrites()

        do {
            try await deleteRecordIfPresent(CKRecord.ID(recordName: visitId))
            print("✅ PlaceStore: Deleted visit \(visitId)")
            return .success(())
        } catch {
            self.error = "Failed to delete visit: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to delete visit \(visitId): \(error)")
            return .failure(.deleteFailed)
        }
    }

    /// The core loop write: dedup the place, then attach a visit to it.
    @discardableResult
    func recordVisit(
        to candidate: Place,
        id: String = UUID().uuidString,
        date: Date = Date(),
        verdict: Verdict? = nil,
        note: String? = nil,
        photoLocalIdentifiers: [String] = [],
        tripId: String? = nil,
        source: VisitSource = .manual
    ) async -> Result<Visit, PlaceStoreError> {
        let placeResult = await upsertPlace(candidate)

        let place: Place
        switch placeResult {
        case .success(let resolved):
            place = resolved
        case .failure(let storeError):
            // The place is in the local store even when the write failed, so
            // prefer a local match over dropping the user's swipe entirely.
            guard let fallback = existingPlace(matching: candidate) else {
                return .failure(storeError)
            }
            place = fallback
        }

        let visit = Visit(
            id: id,
            placeId: place.id,
            date: date,
            verdict: verdict,
            note: note,
            photoLocalIdentifiers: photoLocalIdentifiers,
            tripId: tripId,
            source: source
        )

        let visitResult = await addVisit(visit)
        switch visitResult {
        case .success:
            return .success(visit)
        case .failure(let storeError):
            return .failure(storeError)
        }
    }

    /// The swipe. `nil` un-rates.
    func setVerdict(_ verdict: Verdict?, forVisit visitId: String) async -> Result<Void, PlaceStoreError> {
        guard let visit = visits.first(where: { $0.id == visitId }) else {
            print("⚠️ PlaceStore: setVerdict - no visit \(visitId)")
            return .failure(.notFound)
        }
        return await addVisit(visit.with(verdict: verdict))
    }

    // MARK: - Fetching

    func fetchAll() async -> Result<Void, PlaceStoreError> {
        isSyncing = true
        let placesResult = await fetchPlaces()
        let visitsResult = await fetchVisits()
        isSyncing = false

        if case .failure(let placeError) = placesResult { return .failure(placeError) }
        if case .failure(let visitError) = visitsResult { return .failure(visitError) }

        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
        print("✅ PlaceStore: Synced \(places.count) places, \(visits.count) visits")
        return .success(())
    }

    func fetchPlaces() async -> Result<Void, PlaceStoreError> {
        isLoading = true
        error = nil

        guard await cloudKitService.checkAccountStatus() else {
            cloudKitAvailable = false
            isLoading = false
            self.error = "CloudKit account not available"
            print("❌ PlaceStore: CloudKit account not available")
            return .failure(.fetchFailed)
        }
        cloudKitAvailable = true

        do {
            let records = try await fetchAllRecords(ofType: Place.recordType)
            let fetched = records
                .compactMap { Place.fromCKRecord($0) }
                .filter { $0.name != PlaceSchemaService.schemaInitName }

            // Keep anything still queued locally - it is not on the server yet.
            //
            // Matched by ID, not by `contains` on the value. `Place` is
            // Hashable, so `fetched.contains(local)` compares WHOLE structs: a
            // place edited offline differs from the server's older copy by name
            // or updatedAt, so both survived and `places` ended up holding two
            // entries with the same id. `ForEach` over Identifiable then renders
            // the row twice.
            let fetchedIds = Set(fetched.map(\.id))
            let unsynced = places.filter { pendingPlaceIds.contains($0.id) && !fetchedIds.contains($0.id) }
            places = (fetched + unsynced).sortedByName()

            cacheData()
            isLoading = false
            print("🔄 PlaceStore: Fetched \(fetched.count) places from CloudKit")
            return .success(())
        } catch {
            isLoading = false
            self.error = "Failed to fetch places: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to fetch places: \(error)")
            return .failure(.fetchFailed)
        }
    }

    func fetchVisits() async -> Result<Void, PlaceStoreError> {
        isLoading = true
        error = nil

        do {
            let records = try await fetchAllRecords(ofType: Visit.recordType)
            let fetched = records
                .compactMap { Visit.fromCKRecord($0) }
                .filter { $0.placeId != PlaceSchemaService.schemaInitName }

            // Same ID-based match as fetchPlaces - see the note there.
            let fetchedIds = Set(fetched.map(\.id))
            let unsynced = visits.filter { pendingVisitIds.contains($0.id) && !fetchedIds.contains($0.id) }
            visits = (fetched + unsynced).sortedByDateDescending()

            cacheData()
            isLoading = false
            print("🔄 PlaceStore: Fetched \(fetched.count) visits from CloudKit")
            return .success(())
        } catch {
            isLoading = false
            self.error = "Failed to fetch visits: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to fetch visits: \(error)")
            return .failure(.fetchFailed)
        }
    }

    func fetchVisits(forPlace placeId: String) async -> Result<[Visit], PlaceStoreError> {
        do {
            let predicate = NSPredicate(format: "placeId == %@", placeId)
            let query = CKQuery(recordType: Visit.recordType, predicate: predicate)
            let (records, _) = try await runQuery(query)
            let fetched = records.compactMap { Visit.fromCKRecord($0) }.sortedByDateDescending()

            for visit in fetched { upsertLocalVisit(visit) }
            cacheData()
            return .success(fetched)
        } catch {
            self.error = "Failed to fetch visits: \(error.localizedDescription)"
            print("❌ PlaceStore: Failed to fetch visits for place \(placeId): \(error)")
            return .failure(.fetchFailed)
        }
    }

    // MARK: - CloudKit Plumbing

    /// Upsert that survives a record already existing on the server. Saving a
    /// freshly built CKRecord over an existing recordName fails with
    /// `.serverRecordChanged` (no change tag), so fetch first when possible -
    /// the same fetch-then-mutate shape as `TripStore.updateEntry`.
    private func saveRecordUpserting(
        recordID: CKRecord.ID,
        recordType: String,
        apply: (CKRecord) -> Void
    ) async throws {
        let record: CKRecord
        do {
            record = try await cloudKitService.database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        apply(record)
        let _ = try await cloudKitService.database.save(record)
    }

    private func deleteRecordIfPresent(_ recordID: CKRecord.ID) async throws {
        do {
            try await cloudKitService.database.deleteRecord(withID: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // Never synced, or already gone. Nothing to do.
        }
    }

    private func runQuery(_ query: CKQuery) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        let (results, cursor) = try await cloudKitService.database.records(matching: query)
        let records = results.compactMap { (_, result) -> CKRecord? in
            switch result {
            case .success(let record):
                return record
            case .failure(let error):
                print("❌ PlaceStore: Failed to process individual record: \(error)")
                return nil
            }
        }
        return (records, cursor)
    }

    /// Paged fetch of an entire record type.
    ///
    /// Primary predicate matches `TripStore.fetchTrips` (`createdAt > 1970`).
    /// If the index is missing CloudKit throws `.invalidArguments`, so we retry
    /// with `NSPredicate(value: true)`. If BOTH fail, mark `createdAt` and
    /// `recordName` queryable for Place/Visit in the CloudKit Dashboard - the
    /// same manual step Trip/TripEntry needed.
    private func fetchAllRecords(ofType recordType: String) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        let oldDate = Date(timeIntervalSince1970: 0) // January 1, 1970
        let primary = CKQuery(
            recordType: recordType,
            predicate: NSPredicate(format: "createdAt > %@", oldDate as NSDate)
        )

        do {
            let (records, next) = try await runQuery(primary)
            collected.append(contentsOf: records)
            cursor = next
        } catch let ckError as CKError where ckError.code == .invalidArguments {
            print("⚠️ PlaceStore: createdAt not queryable for \(recordType) - retrying with TRUEPREDICATE")
            let fallback = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (records, next) = try await runQuery(fallback)
            collected.append(contentsOf: records)
            cursor = next
        }

        while let current = cursor {
            let (results, next) = try await cloudKitService.database.records(continuingMatchFrom: current)
            let records = results.compactMap { (_, result) -> CKRecord? in
                switch result {
                case .success(let record): return record
                case .failure: return nil
                }
            }
            collected.append(contentsOf: records)
            cursor = next
        }

        return collected
    }

    // MARK: - Pending Writes

    /// Retries anything that could not reach CloudKit while the account was
    /// unavailable. Note: deletes are not queued - a delete that fails offline
    /// stays local-only and the record reappears on the next full fetch.
    private func flushPendingWrites() async {
        guard cloudKitAvailable else { return }
        guard !pendingPlaceIds.isEmpty || !pendingVisitIds.isEmpty else { return }

        print("🔄 PlaceStore: Flushing \(pendingPlaceIds.count) places, \(pendingVisitIds.count) visits")

        for placeId in Array(pendingPlaceIds) {
            guard let place = places.first(where: { $0.id == placeId }) else {
                pendingPlaceIds.remove(placeId)
                continue
            }
            do {
                try await saveRecordUpserting(
                    recordID: CKRecord.ID(recordName: place.id),
                    recordType: Place.recordType
                ) { place.apply(to: $0) }
                pendingPlaceIds.remove(placeId)
            } catch {
                print("⚠️ PlaceStore: Still cannot save place \(placeId): \(error)")
            }
        }

        for visitId in Array(pendingVisitIds) {
            guard let visit = visits.first(where: { $0.id == visitId }) else {
                pendingVisitIds.remove(visitId)
                continue
            }
            do {
                try await saveRecordUpserting(
                    recordID: CKRecord.ID(recordName: visit.id),
                    recordType: Visit.recordType
                ) { visit.apply(to: $0) }
                pendingVisitIds.remove(visitId)
            } catch {
                print("⚠️ PlaceStore: Still cannot save visit \(visitId): \(error)")
            }
        }

        savePendingWrites()
    }

    private func loadPendingWrites() {
        pendingPlaceIds = Set(UserDefaults.standard.stringArray(forKey: pendingPlacesKey) ?? [])
        pendingVisitIds = Set(UserDefaults.standard.stringArray(forKey: pendingVisitsKey) ?? [])
    }

    private func savePendingWrites() {
        UserDefaults.standard.set(Array(pendingPlaceIds), forKey: pendingPlacesKey)
        UserDefaults.standard.set(Array(pendingVisitIds), forKey: pendingVisitsKey)
    }

    // MARK: - Local Mutation

    private func upsertLocalPlace(_ place: Place) {
        if let index = places.firstIndex(where: { $0.id == place.id }) {
            places[index] = place
        } else {
            places.append(place)
        }
    }

    private func upsertLocalVisit(_ visit: Visit) {
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = visit
        } else {
            visits.append(visit)
        }
        visits.sort { $0.date > $1.date }
    }

    // MARK: - Caching

    private func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let cached = try? JSONDecoder().decode([Place].self, from: data) {
            places = cached
            print("✅ PlaceStore: Loaded \(places.count) places from cache")
        }

        if let data = UserDefaults.standard.data(forKey: visitsKey),
           let cached = try? JSONDecoder().decode([Visit].self, from: data) {
            visits = cached.sortedByDateDescending()
            print("✅ PlaceStore: Loaded \(visits.count) visits from cache")
        }

        rebuildIndexes()
    }

    /// Every mutation path calls this, so the visit index is rebuilt here.
    private func cacheData() {
        rebuildIndexes()

        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: placesKey)
        }
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
        }

        print("💾 PlaceStore: Cached \(places.count) places and \(visits.count) visits")
    }

    private func rebuildIndexes() {
        visitsByPlaceId = Dictionary(grouping: visits) { $0.placeId }
            .mapValues { $0.sortedByDateDescending() }
    }

    // MARK: - Public Sync Methods

    var shouldSync: Bool {
        guard let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return true // Never synced
        }
        return Date().timeIntervalSince(lastSync) > 300 // 5 minutes
    }

    func syncIfNeeded() async {
        guard shouldSync else {
            print("🔄 PlaceStore: Skipping sync - recent sync detected")
            return
        }
        await refreshCloudKitAvailability()
    }

    func forceSync() async {
        print("🔄 PlaceStore: Force syncing with CloudKit...")
        let available = await cloudKitService.checkAccountStatus()
        cloudKitAvailable = available
        guard available else {
            print("❌ PlaceStore: Force sync skipped - iCloud unavailable")
            return
        }
        await flushPendingWrites()
        let _ = await fetchAll()
    }
}

// MARK: - Error Types
enum PlaceStoreError: LocalizedError {
    case saveFailed
    case fetchFailed
    case deleteFailed
    case notFound
    case invalidData
    case accountUnavailable

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
        case .accountUnavailable:
            return "iCloud account not available"
        }
    }
}
