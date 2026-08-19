//
//  DetectedPlace.swift
//  SkyLine
//
//  Value types for photo-derived place detection. Deliberately free of PhotoKit
//  and MapKit types so the clustering algorithm is unit-testable without a
//  photo library and without a network.
//

import Foundation
import CoreLocation
import CloudKit

// MARK: - Photo Point

/// A single photo reduced to exactly the fields clustering needs.
/// Built from a `PHAsset` by `PhotoAssetFetcher`, but carries no PhotoKit types
/// so `PlaceClusterer` can be driven entirely from fixtures in tests.
struct PhotoPoint: Codable, Identifiable, Hashable, Sendable {
    let id: String              // PHAsset.localIdentifier
    let timestamp: Date         // PHAsset.creationDate (assets with nil creationDate are dropped upstream)
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?  // CLLocation.horizontalAccuracy; < 0 means invalid
    let isScreenshot: Bool
    let isFavorite: Bool
    let isPanorama: Bool
    let isDepthEffect: Bool     // portrait mode — a deliberate, composed shot
    let pixelWidth: Int
    let pixelHeight: Int

    init(
        id: String,
        timestamp: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        isScreenshot: Bool = false,
        isFavorite: Bool = false,
        isPanorama: Bool = false,
        isDepthEffect: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.isPanorama = isPanorama
        self.isDepthEffect = isDepthEffect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Aspect ratio, used when picking a hero image for a card.
    var aspectRatio: Double {
        guard pixelHeight > 0 else { return 1.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

// MARK: - Place Visit

/// One continuous stay at a place. A place visited on three days has three visits.
struct PlaceVisit: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let assetIdentifiers: [String]
    let latitude: Double
    let longitude: Double
    /// Max distance from this visit's own centroid to any of its photos.
    /// This is the visit's spatial *extent*, and it is what lets the merge step
    /// tell a point venue apart from a sprawling one. See
    /// `PlaceClusterer.mergeThreshold`.
    let spreadMeters: Double

    init(
        id: String = UUID().uuidString,
        startDate: Date,
        endDate: Date,
        assetIdentifiers: [String],
        latitude: Double,
        longitude: Double,
        spreadMeters: Double = 0
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.assetIdentifiers = assetIdentifiers
        self.latitude = latitude
        self.longitude = longitude
        self.spreadMeters = spreadMeters
    }

    /// Time between the first and last photo of this visit. A single-photo visit dwells 0 s.
    var dwell: TimeInterval { endDate.timeIntervalSince(startDate) }

    var photoCount: Int { assetIdentifiers.count }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Verdict

/// The one thing the user actually supplies. Raw values are stable — they are
/// persisted to CloudKit and must never be renamed.
enum PlaceVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case worthIt = "worth_it"
    case fine = "fine"
    case skip = "skip"

    var displayName: String {
        switch self {
        case .worthIt: return "Worth it"
        case .fine:    return "Fine"
        case .skip:    return "Skip"
        }
    }

    var systemImage: String {
        switch self {
        case .worthIt: return "star.fill"
        case .fine:    return "hand.thumbsup"
        case .skip:    return "xmark"
        }
    }

    /// Maps onto existing `ThemeColors` tokens — no new palette needed.
    /// success / warning / error already exist in Theme.swift.
    var themeColorToken: String {
        switch self {
        case .worthIt: return "success"
        case .fine:    return "warning"
        case .skip:    return "error"
        }
    }
}

// MARK: - Detection Source

/// Which rung of the fallback ladder produced a place. The UI renders a
/// different affordance per source — this is what guarantees "no blank page".
enum PlaceDetectionSource: String, Codable, CaseIterable, Hashable, Sendable {
    /// Clustered from photo GPS. Name and coordinate are both trustworthy.
    case photoGPS = "photo_gps"
    /// Clustered from photo timestamps only (camera had location services off).
    /// There IS a representative photo and a time window, but no coordinate yet —
    /// the user must attach a place.
    case photoTimeOnly = "photo_time_only"
    /// No usable photos. POIs suggested around the trip destination.
    case destinationSuggestion = "destination_suggestion"
    /// Typed or searched by the user.
    case manual = "manual"

    var requiresUserLocationInput: Bool {
        self == .photoTimeOnly
    }
}

// MARK: - Detected Place

/// A place the user spent time at, ready to be swiped on.
///
/// DESIGN DECISION — one place, many visits:
/// A place visited on multiple days is ONE `DetectedPlace` with multiple
/// `PlaceVisit`s, never two places. Rationale:
///   1. The verdict is an opinion about the place, not about an afternoon.
///      "Worth it" said twice about the same ramen shop is one fact.
///   2. Showing the same restaurant twice in the swipe deck is the single most
///      obvious way to make the whole mechanism read as broken.
///   3. Returning is positive evidence, so `visitCount` feeds `significance`
///      and pushes repeat places to the top of the deck rather than duplicating them.
/// Nothing is lost: the visit breakdown survives, so a guide can say
/// "you went back twice".
struct DetectedPlace: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let tripId: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let category: String?            // MKPointOfInterestCategory.rawValue when known
    let visits: [PlaceVisit]
    let representativeAssetIdentifier: String?
    let allAssetIdentifiers: [String]
    let source: PlaceDetectionSource
    let significance: Double
    let isNameUserEdited: Bool
    let verdict: PlaceVerdict?
    let note: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        tripId: String,
        name: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        category: String? = nil,
        visits: [PlaceVisit] = [],
        representativeAssetIdentifier: String? = nil,
        allAssetIdentifiers: [String] = [],
        source: PlaceDetectionSource,
        significance: Double = 0,
        isNameUserEdited: Bool = false,
        verdict: PlaceVerdict? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tripId = tripId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.visits = visits
        self.representativeAssetIdentifier = representativeAssetIdentifier
        self.allAssetIdentifiers = allAssetIdentifiers
        self.source = source
        self.significance = significance
        self.isNameUserEdited = isNameUserEdited
        self.verdict = verdict
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    var photoCount: Int { allAssetIdentifiers.count }

    var visitCount: Int { visits.count }

    var firstVisitAt: Date? { visits.map(\.startDate).min() }

    var lastVisitAt: Date? { visits.map(\.endDate).max() }

    /// Total time across all visits, from photo timestamps only.
    var totalDwell: TimeInterval { visits.reduce(0) { $0 + $1.dwell } }

    /// "Tue 4 Mar · 2 visits · 12 photos" style subtitle for the swipe card.
    func subtitle(in timeZone: TimeZone) -> String {
        var parts: [String] = []
        if let first = firstVisitAt {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEE d MMM"
            parts.append(formatter.string(from: first))
        }
        if visitCount > 1 { parts.append("\(visitCount) visits") }
        parts.append(photoCount == 1 ? "1 photo" : "\(photoCount) photos")
        return parts.joined(separator: " · ")
    }

    /// Non-mutating rebuild — `Trip`/`TripEntry` in this codebase are all-`let`
    /// structs rebuilt through the memberwise init, so this matches house style.
    func with(
        name: String? = nil,
        latitude: Double?? = nil,
        longitude: Double?? = nil,
        category: String?? = nil,
        source: PlaceDetectionSource? = nil,
        isNameUserEdited: Bool? = nil,
        verdict: PlaceVerdict?? = nil,
        note: String?? = nil
    ) -> DetectedPlace {
        DetectedPlace(
            id: id,
            tripId: tripId,
            name: name ?? self.name,
            latitude: latitude ?? self.latitude,
            longitude: longitude ?? self.longitude,
            category: category ?? self.category,
            visits: visits,
            representativeAssetIdentifier: representativeAssetIdentifier,
            allAssetIdentifiers: allAssetIdentifiers,
            source: source ?? self.source,
            significance: significance,
            isNameUserEdited: isNameUserEdited ?? self.isNameUserEdited,
            verdict: verdict ?? self.verdict,
            note: note ?? self.note,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

// MARK: - CloudKit Conversion

extension DetectedPlace {
    /// New record type — purely additive. No existing record type is touched.
    static let recordType = "DetectedPlace"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: DetectedPlace.recordType,
                              recordID: CKRecord.ID(recordName: id))
        record["tripId"] = tripId
        record["name"] = name
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["category"] = category
        record["representativeAssetIdentifier"] = representativeAssetIdentifier
        // A [String] CloudKit field must never be written empty or the type
        // fails to register on first use — same guard TripEntry.imageURLs uses.
        if !allAssetIdentifiers.isEmpty {
            record["allAssetIdentifiers"] = allAssetIdentifiers
        }
        record["source"] = source.rawValue
        record["significance"] = significance
        record["isNameUserEdited"] = isNameUserEdited
        record["verdict"] = verdict?.rawValue
        record["note"] = note
        record["visitCount"] = visits.count
        record["photoCount"] = allAssetIdentifiers.count
        record["firstVisitAt"] = firstVisitAt
        record["lastVisitAt"] = lastVisitAt
        // Visits are stored as a JSON blob rather than a second record type:
        // they are never queried independently and always load with their place,
        // so a child record type would only add fan-out and sync cost.
        if let data = try? JSONEncoder().encode(visits),
           let json = String(data: data, encoding: .utf8) {
            record["visitsJSON"] = json
        }
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> DetectedPlace? {
        guard let tripId = record["tripId"] as? String,
              let name = record["name"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            print("❌ DetectedPlace: Missing required fields on record \(record.recordID.recordName)")
            return nil
        }

        var visits: [PlaceVisit] = []
        if let json = record["visitsJSON"] as? String,
           let data = json.data(using: .utf8) {
            visits = (try? JSONDecoder().decode([PlaceVisit].self, from: data)) ?? []
        }

        // Backward-compat: unknown/removed raw values decode to a usable default
        // rather than dropping the record, mirroring the DataSource fix in
        // CloudKitService.createFlight.
        let sourceRaw = record["source"] as? String ?? PlaceDetectionSource.manual.rawValue
        let source = PlaceDetectionSource(rawValue: sourceRaw) ?? .manual

        var verdict: PlaceVerdict?
        if let verdictRaw = record["verdict"] as? String {
            verdict = PlaceVerdict(rawValue: verdictRaw)
        }

        return DetectedPlace(
            id: record.recordID.recordName,
            tripId: tripId,
            name: name,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            category: record["category"] as? String,
            visits: visits,
            representativeAssetIdentifier: record["representativeAssetIdentifier"] as? String,
            allAssetIdentifiers: record["allAssetIdentifiers"] as? [String] ?? [],
            source: source,
            significance: record["significance"] as? Double ?? 0,
            isNameUserEdited: record["isNameUserEdited"] as? Bool ?? false,
            verdict: verdict,
            note: record["note"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Detection Result

/// What `PhotoPlaceDetectionService` hands back. It always carries places —
/// the `source` and `diagnostics` tell the UI which explanation to show above them.
struct PlaceDetectionResult: Sendable {
    let places: [DetectedPlace]
    let source: PlaceDetectionSource
    let diagnostics: PlaceDetectionDiagnostics
}

/// Everything the UI needs to write an honest empty/degraded state, and
/// everything a bug report needs.
struct PlaceDetectionDiagnostics: Sendable {
    var assetsInDateRange: Int = 0
    var assetsWithLocation: Int = 0
    var assetsWithLocationRecoveredFromEXIF: Int = 0
    var screenshotsExcluded: Int = 0
    var clustersBeforeTrim: Int = 0
    var clustersDroppedAsOutliers: Int = 0
    var geocodeSuccesses: Int = 0
    var geocodeFailures: Int = 0
    var isLimitedLibraryAccess: Bool = false

    var locationCoverage: Double {
        guard assetsInDateRange > 0 else { return 0 }
        return Double(assetsWithLocation) / Double(assetsInDateRange)
    }

    /// One line the user can actually read, e.g.
    /// "None of your 214 photos from this trip have location saved."
    var userFacingExplanation: String? {
        if isLimitedLibraryAccess {
            return "SkyLine can only see \(assetsInDateRange) photos you selected. Choose more to find more places."
        }
        if assetsInDateRange == 0 {
            return "No photos found between these dates."
        }
        if assetsWithLocation == 0 {
            return "None of your \(assetsInDateRange) photos from this trip have location saved. Pick where each one was."
        }
        if locationCoverage < 0.25 {
            return "Only \(assetsWithLocation) of \(assetsInDateRange) photos have location saved, so some places may be missing."
        }
        return nil
    }
}

// MARK: - Sample Data

extension DetectedPlace {
    static let sample = DetectedPlace(
        tripId: "sample-trip",
        name: "Fuglen Tokyo",
        latitude: 35.6693,
        longitude: 139.6975,
        category: "MKPOICategoryCafe",
        visits: [
            PlaceVisit(
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_004_200),
                assetIdentifiers: ["A1", "A2", "A3"],
                latitude: 35.6693,
                longitude: 139.6975,
                spreadMeters: 18
            )
        ],
        representativeAssetIdentifier: "A2",
        allAssetIdentifiers: ["A1", "A2", "A3"],
        source: .photoGPS,
        significance: 7.2
    )
}
