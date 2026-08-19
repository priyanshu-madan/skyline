//
//  Visit.swift
//  SkyLine
//
//  One trip to a Place, and what the user thought of it
//

import Foundation
import CloudKit

// MARK: - Visit Model
/// The user's experience of a `Place`. Many visits point at one place.
///
/// `verdict` is optional on purpose: an imported or freshly detected visit is
/// *unrated* until the user swipes. Nothing in the app may fabricate an opinion.
struct Visit: Codable, Identifiable, Hashable {
    static let recordType = "Visit"

    let id: String
    let placeId: String
    let date: Date
    let verdict: Verdict?
    let note: String?
    /// `PHAsset.localIdentifier` strings. Device-local: they will not resolve on
    /// another device, which is fine - they are a rendering hint, not the data.
    let photoLocalIdentifiers: [String]
    let tripId: String?         // Optional link back to the legacy Trip record
    let source: VisitSource
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Computed

    var isRated: Bool { verdict != nil }

    var hasPhotos: Bool { !photoLocalIdentifiers.isEmpty }

    var hasNote: Bool {
        guard let note = note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var photoCount: Int { photoLocalIdentifiers.count }

    func dayKey(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        placeId: String,
        date: Date = Date(),
        verdict: Verdict? = nil,
        note: String? = nil,
        photoLocalIdentifiers: [String] = [],
        tripId: String? = nil,
        source: VisitSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.placeId = placeId
        self.date = date
        self.verdict = verdict
        self.note = note
        self.photoLocalIdentifiers = photoLocalIdentifiers
        self.tripId = tripId
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Mutation Helpers
/// `Visit` is an all-`let` struct like every other model here, so "editing"
/// means rebuilding. These helpers keep call sites from re-listing 10 fields.
extension Visit {
    func with(verdict newVerdict: Verdict?) -> Visit {
        rebuilt(verdict: newVerdict)
    }

    func with(note newNote: String?) -> Visit {
        rebuilt(note: newNote)
    }

    func with(photoLocalIdentifiers newIdentifiers: [String]) -> Visit {
        rebuilt(photoLocalIdentifiers: newIdentifiers)
    }

    func touched() -> Visit {
        rebuilt()
    }

    /// `verdict` is doubly optional so "leave it alone" and "clear it" stay
    /// distinguishable: pass `nil` to keep, `.some(nil)` to un-rate.
    func rebuilt(
        verdict: Verdict?? = nil,
        note: String?? = nil,
        photoLocalIdentifiers: [String]? = nil,
        tripId: String?? = nil,
        date: Date? = nil
    ) -> Visit {
        Visit(
            id: id,
            placeId: placeId,
            date: date ?? self.date,
            verdict: verdict ?? self.verdict,
            note: note ?? self.note,
            photoLocalIdentifiers: photoLocalIdentifiers ?? self.photoLocalIdentifiers,
            tripId: tripId ?? self.tripId,
            source: source,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

// MARK: - Visit Source
/// Where the visit came from. Used to keep the importer idempotent and to let
/// the UI treat, say, airport stopovers differently from swiped places.
enum VisitSource: String, Codable, CaseIterable, Hashable {
    case manual = "manual"                       // User added it by hand
    case photoCluster = "photoCluster"           // Camera-roll clustering
    case importedTrip = "importedTrip"           // Legacy Trip record
    case importedTripEntry = "importedTripEntry" // Legacy TripEntry record
    case importedFlight = "importedFlight"       // Legacy Flight record

    var displayName: String {
        switch self {
        case .manual: return "Added by you"
        case .photoCluster: return "From photos"
        case .importedTrip: return "From a trip"
        case .importedTripEntry: return "From a journal entry"
        case .importedFlight: return "From a flight"
        }
    }

    var isImported: Bool {
        switch self {
        case .importedTrip, .importedTripEntry, .importedFlight: return true
        case .manual, .photoCluster: return false
        }
    }

    /// Total decode - unknown sources become `.manual` instead of throwing.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self) else {
            self = .manual
            return
        }
        self = VisitSource(rawValue: raw) ?? .manual
    }
}

// MARK: - CloudKit Conversion
extension Visit {
    /// Field types, for the CloudKit Dashboard:
    ///   placeId               String    (QUERYABLE - visits-for-place lookups)
    ///   date                  Date/Time (SORTABLE)
    ///   verdict               String    (optional - absent means unrated)
    ///   note                  String    (optional)
    ///   photoLocalIdentifiers List<String> (omitted when empty)
    ///   tripId                String    (optional, QUERYABLE)
    ///   source                String
    ///   createdAt             Date/Time (QUERYABLE - fetch predicate)
    ///   updatedAt             Date/Time
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Visit.recordType, recordID: CKRecord.ID(recordName: id))
        apply(to: record)
        return record
    }

    func apply(to record: CKRecord) {
        record["placeId"] = placeId
        record["date"] = date
        record["verdict"] = verdict?.rawValue
        record["note"] = note
        // Mirror TripEntry.imageURLs: only write the list when it has content,
        // otherwise leave the field absent.
        if photoLocalIdentifiers.isEmpty {
            record["photoLocalIdentifiers"] = nil
        } else {
            record["photoLocalIdentifiers"] = photoLocalIdentifiers
        }
        record["tripId"] = tripId
        record["source"] = source.rawValue
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
    }

    static func fromCKRecord(_ record: CKRecord) -> Visit? {
        guard let placeId = record["placeId"] as? String,
              let date = record["date"] as? Date else {
            return nil
        }

        // Lenient on both enums - an unrecognised value must never drop the row.
        let verdict = Verdict.lenient(record["verdict"] as? String)
        let source = VisitSource(rawValue: record["source"] as? String ?? "") ?? .manual

        return Visit(
            id: record.recordID.recordName,
            placeId: placeId,
            date: date,
            verdict: verdict,
            note: record["note"] as? String,
            photoLocalIdentifiers: record["photoLocalIdentifiers"] as? [String] ?? [],
            tripId: record["tripId"] as? String,
            source: source,
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date()
        )
    }
}

// MARK: - Sample Data
extension Visit {
    static func sampleVisits(for placeId: String) -> [Visit] {
        [
            Visit(
                placeId: placeId,
                date: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
                verdict: .worthIt,
                note: "Best hand drip in Shibuya. Go before 10am.",
                source: .manual
            ),
            Visit(
                placeId: placeId,
                date: Calendar.current.date(byAdding: .day, value: -400, to: Date()) ?? Date(),
                verdict: .fine,
                source: .photoCluster
            )
        ]
    }

    static let sample = Visit(
        placeId: Place.sample.id,
        verdict: .worthIt,
        note: "Sample visit for previews."
    )
}

// MARK: - Sorting / Rollups
extension Array where Element == Visit {
    func sortedByDateDescending() -> [Visit] {
        sorted { $0.date > $1.date }
    }

    func sortedByDateAscending() -> [Visit] {
        sorted { $0.date < $1.date }
    }

    func mostRecent() -> Visit? {
        self.max { $0.date < $1.date }
    }

    func earliest() -> Visit? {
        self.min { $0.date < $1.date }
    }

    /// The verdict shown for a place: the most recent explicit one wins, so a
    /// re-rate overrides history. `nil` when the user has never rated it.
    func currentVerdict() -> Verdict? {
        sortedByDateDescending().first { $0.verdict != nil }?.verdict
    }

    func verdictCounts() -> [Verdict: Int] {
        var counts: [Verdict: Int] = [:]
        for visit in self {
            guard let verdict = visit.verdict else { continue }
            counts[verdict, default: 0] += 1
        }
        return counts
    }

    func groupedByPlaceId() -> [String: [Visit]] {
        Dictionary(grouping: self) { $0.placeId }
    }

    func groupedByDay(in timeZone: TimeZone = .current) -> [(Date, [Visit])] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let grouped = Dictionary(grouping: self) { calendar.startOfDay(for: $0.date) }
        return grouped.sorted { $0.key > $1.key }.map { (key, value) in
            (key, value.sortedByDateAscending())
        }
    }
}
