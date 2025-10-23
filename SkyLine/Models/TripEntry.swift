//
//  TripEntry.swift
//  SkyLine
//
//  Trip timeline entry model for travel journal entries
//

import Foundation
import CoreLocation
import CloudKit
import UIKit

// MARK: - Trip Entry Model
struct TripEntry: Codable, Identifiable, Hashable {
    let id: String
    let tripId: String
    let timestamp: Date
    let entryType: TripEntryType
    let title: String
    let content: String
    let imageURLs: [String]
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let createdAt: Date
    let updatedAt: Date
    
    // Computed properties
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
    
    var dayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: timestamp)
    }
    
    var hasImages: Bool {
        !imageURLs.isEmpty
    }
    
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }
    
    var displayLocation: String {
        if let locationName = locationName, !locationName.isEmpty {
            return locationName
        } else if hasLocation {
            return "📍 \(String(format: "%.4f", latitude!)), \(String(format: "%.4f", longitude!))"
        } else {
            return ""
        }
    }
    
    // Initializers
    init(
        id: String = UUID().uuidString,
        tripId: String,
        timestamp: Date = Date(),
        entryType: TripEntryType,
        title: String,
        content: String,
        imageURLs: [String] = [],
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tripId = tripId
        self.timestamp = timestamp
        self.entryType = entryType
        self.title = title
        self.content = content
        self.imageURLs = imageURLs
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Trip Entry Type
enum TripEntryType: String, CaseIterable, Codable {
    case food = "food"
    case activity = "activity"
    case sightseeing = "sightseeing"
    case accommodation = "accommodation"
    case transportation = "transportation"
    case shopping = "shopping"
    case note = "note"
    case photo = "photo"
    
    var displayName: String {
        switch self {
        case .food:
            return "Food & Drink"
        case .activity:
            return "Activity"
        case .sightseeing:
            return "Sightseeing"
        case .accommodation:
            return "Accommodation"
        case .transportation:
            return "Transportation"
        case .shopping:
            return "Shopping"
        case .note:
            return "Note"
        case .photo:
            return "Photo"
        }
    }
    
    var systemImage: String {
        switch self {
        case .food:
            return "fork.knife"
        case .activity:
            return "figure.run"
        case .sightseeing:
            return "camera"
        case .accommodation:
            return "bed.double"
        case .transportation:
            return "car"
        case .shopping:
            return "bag"
        case .note:
            return "note.text"
        case .photo:
            return "photo"
        }
    }
    
    var emoji: String {
        switch self {
        case .food:
            return "🍴"
        case .activity:
            return "🎭"
        case .sightseeing:
            return "📸"
        case .accommodation:
            return "🏨"
        case .transportation:
            return "🚗"
        case .shopping:
            return "🛍️"
        case .note:
            return "📝"
        case .photo:
            return "📷"
        }
    }
    
    var color: String {
        switch self {
        case .food:
            return "orange"
        case .activity:
            return "purple"
        case .sightseeing:
            return "blue"
        case .accommodation:
            return "green"
        case .transportation:
            return "red"
        case .shopping:
            return "pink"
        case .note:
            return "gray"
        case .photo:
            return "yellow"
        }
    }
}

// MARK: - Entry Photo Metadata
struct EntryPhotoMetadata: Codable, Hashable {
    let url: String
    let timestamp: Date?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let filename: String?
    let size: CGSize?
    
    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Sample Data
extension TripEntry {
    static func sampleEntries(for tripId: String) -> [TripEntry] {
        let baseDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        
        return [
            TripEntry(
                tripId: tripId,
                timestamp: Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? baseDate,
                entryType: .food,
                title: "Amazing Ramen",
                content: "Had the most incredible tonkotsu ramen at a tiny shop in Shibuya. The broth was so rich and flavorful!",
                latitude: 35.6595,
                longitude: 139.7006,
                locationName: "Shibuya, Tokyo"
            ),
            TripEntry(
                tripId: tripId,
                timestamp: Calendar.current.date(byAdding: .hour, value: -46, to: Date()) ?? baseDate,
                entryType: .sightseeing,
                title: "Tokyo Skytree Visit",
                content: "Breathtaking views from the top! You can see the entire city sprawling out in every direction.",
                latitude: 35.7101,
                longitude: 139.8107,
                locationName: "Tokyo Skytree"
            ),
            TripEntry(
                tripId: tripId,
                timestamp: Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? baseDate,
                entryType: .activity,
                title: "Traditional Tea Ceremony",
                content: "Learned about the ancient art of tea ceremony. Such a peaceful and meditative experience.",
                latitude: 35.6762,
                longitude: 139.6503,
                locationName: "Senso-ji Temple"
            ),
            TripEntry(
                tripId: tripId,
                timestamp: Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? baseDate,
                entryType: .shopping,
                title: "Harajuku Shopping",
                content: "Found some amazing vintage clothes and unique accessories. The street fashion here is incredible!",
                latitude: 35.6702,
                longitude: 139.7016,
                locationName: "Takeshita Street, Harajuku"
            )
        ]
    }
    
    static let sample = TripEntry(
        tripId: "sample-trip",
        entryType: .food,
        title: "Sample Entry",
        content: "This is a sample entry for testing purposes.",
        latitude: 35.6762,
        longitude: 139.6503,
        locationName: "Tokyo, Japan"
    )
}

// MARK: - CloudKit Conversion
extension TripEntry {
    // Convert to CloudKit record
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "TripEntry", recordID: CKRecord.ID(recordName: id))
        
        record["tripId"] = tripId
        record["timestamp"] = timestamp
        record["entryType"] = entryType.rawValue
        record["title"] = title
        record["content"] = content
        record["imageURLs"] = imageURLs
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["locationName"] = locationName
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        
        return record
    }
    
    // Create from CloudKit record
    static func fromCKRecord(_ record: CKRecord) -> TripEntry? {
        guard let tripId = record["tripId"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let entryTypeRaw = record["entryType"] as? String,
              let entryType = TripEntryType(rawValue: entryTypeRaw),
              let title = record["title"] as? String,
              let content = record["content"] as? String else {
            return nil
        }
        
        return TripEntry(
            id: record.recordID.recordName,
            tripId: tripId,
            timestamp: timestamp,
            entryType: entryType,
            title: title,
            content: content,
            imageURLs: record["imageURLs"] as? [String] ?? [],
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            locationName: record["locationName"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date()
        )
    }
}

// MARK: - Sorting
extension Array where Element == TripEntry {
    func sortedByTimestamp() -> [TripEntry] {
        return sorted { $0.timestamp > $1.timestamp }
    }
    
    func groupedByDay() -> [(Date, [TripEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        return grouped.sorted { $0.key > $1.key }.map { (key, value) in
            (key, value.sorted { $0.timestamp > $1.timestamp })
        }
    }
}