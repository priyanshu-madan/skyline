//
//  PlaceSchemaService.swift
//  SkyLine
//
//  CloudKit schema bootstrap for the Place / Visit record types
//

import Foundation
import CloudKit

// MARK: - Place Schema Service
/// Creates the "Place" and "Visit" record types in the CloudKit development
/// environment by saving one sample record of each and deleting it immediately -
/// the same idiom as `CloudKitService.initializeTripsSchema()`.
///
/// This lives in its own file because `CloudKitService.initializeSchema()` is
/// private; nothing in `CloudKitService.swift` has to change. If you would
/// rather fold it in, call `await PlaceSchemaService.shared.initializePlaceSchema()`
/// at the end of `CloudKitService.initializeSchema()`.
///
/// Additive only: it never touches Flight / Trip / TripEntry / UserProfile /
/// Configuration / DestinationImage records.
final class PlaceSchemaService {
    static let shared = PlaceSchemaService()

    private let cloudKitService = CloudKitService.shared

    /// Sentinel used by the sample records, mirroring "SCHEMA_INIT" elsewhere.
    static let schemaInitName = "SCHEMA_INIT"

    private init() {}

    // MARK: - Schema Initialization

    func initializePlaceSchema() async {
        await initializePlaceRecordType()
        await initializeVisitRecordType()
    }

    private func initializePlaceRecordType() async {
        let sampleRecord = CKRecord(recordType: Place.recordType)
        sampleRecord["name"] = PlaceSchemaService.schemaInitName
        sampleRecord["latitude"] = 0.0
        sampleRecord["longitude"] = 0.0
        sampleRecord["category"] = PlaceCategory.other.rawValue
        sampleRecord["address"] = ""
        sampleRecord["city"] = ""
        sampleRecord["state"] = ""
        sampleRecord["country"] = ""
        sampleRecord["countryCode"] = ""
        sampleRecord["externalIdentifier"] = ""
        sampleRecord["externalIdentifierSource"] = PlaceIdentifierSource.none.rawValue
        sampleRecord["timeZoneIdentifier"] = ""
        sampleRecord["createdAt"] = Date()
        sampleRecord["updatedAt"] = Date()

        do {
            let _ = try await cloudKitService.database.save(sampleRecord)
            try await cloudKitService.database.deleteRecord(withID: sampleRecord.recordID)
            print("✅ Place schema initialized")
        } catch {
            print("⚠️ Place schema initialization: \(error)")
        }
    }

    private func initializeVisitRecordType() async {
        let sampleRecord = CKRecord(recordType: Visit.recordType)
        sampleRecord["placeId"] = PlaceSchemaService.schemaInitName
        sampleRecord["date"] = Date()
        sampleRecord["verdict"] = Verdict.fine.rawValue
        sampleRecord["note"] = ""
        // A [String] field must be seeded non-empty for CloudKit to register its
        // type - same reason TripEntry seeds imageURLs with a placeholder.
        sampleRecord["photoLocalIdentifiers"] = ["SCHEMA_INIT_ASSET"]
        sampleRecord["tripId"] = ""
        sampleRecord["source"] = VisitSource.manual.rawValue
        sampleRecord["createdAt"] = Date()
        sampleRecord["updatedAt"] = Date()

        do {
            let _ = try await cloudKitService.database.save(sampleRecord)
            try await cloudKitService.database.deleteRecord(withID: sampleRecord.recordID)
            print("✅ Visit schema initialized")
        } catch {
            print("⚠️ Visit schema initialization: \(error)")
        }
    }
}
