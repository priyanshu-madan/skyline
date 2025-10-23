//
//  Trip.swift
//  SkyLine
//
//  Travel trip model for the travel journal functionality
//

import Foundation
import CoreLocation
import CloudKit

// MARK: - Trip Model
struct Trip: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let destination: String
    let destinationCode: String? // Airport code if applicable
    let startDate: Date
    let endDate: Date
    let description: String?
    let coverImageURL: String?
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    let updatedAt: Date
    
    // Computed properties
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    var isUpcoming: Bool {
        Date() < startDate
    }
    
    var isCompleted: Bool {
        Date() > endDate
    }
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var durationText: String {
        let days = Int(duration / 86400) // 24 * 60 * 60
        if days == 1 {
            return "1 day"
        } else {
            return "\(days) days"
        }
    }
    
    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startText = formatter.string(from: startDate)
        let endText = formatter.string(from: endDate)
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        
        if yearFormatter.string(from: startDate) == yearFormatter.string(from: Date()) {
            return "\(startText) - \(endText)"
        } else {
            yearFormatter.dateFormat = "MMM d, yyyy"
            return "\(yearFormatter.string(from: startDate)) - \(yearFormatter.string(from: endDate))"
        }
    }
    
    var statusColor: String {
        if isActive {
            return "green"
        } else if isUpcoming {
            return "blue"
        } else {
            return "gray"
        }
    }
    
    var statusText: String {
        if isActive {
            return "Active"
        } else if isUpcoming {
            return "Upcoming"
        } else {
            return "Completed"
        }
    }
    
    // Initializers
    init(
        id: String = UUID().uuidString,
        title: String,
        destination: String,
        destinationCode: String? = nil,
        startDate: Date,
        endDate: Date,
        description: String? = nil,
        coverImageURL: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.destinationCode = destinationCode
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
        self.coverImageURL = coverImageURL
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Trip Status
enum TripStatus: String, CaseIterable, Codable {
    case upcoming = "upcoming"
    case active = "active"
    case completed = "completed"
    
    var displayName: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        }
    }
    
    var systemImage: String {
        switch self {
        case .upcoming:
            return "calendar"
        case .active:
            return "location"
        case .completed:
            return "checkmark.circle"
        }
    }
}

// MARK: - Sample Data
extension Trip {
    static let sampleTrips: [Trip] = [
        Trip(
            title: "Summer in Tokyo",
            destination: "Tokyo",
            destinationCode: "NRT",
            startDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: -23, to: Date()) ?? Date(),
            description: "Exploring the vibrant culture and amazing food of Tokyo",
            latitude: 35.6762,
            longitude: 139.6503
        ),
        Trip(
            title: "European Adventure",
            destination: "Paris",
            destinationCode: "CDG",
            startDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date(),
            description: "Art, history, and cuisine across Europe",
            latitude: 48.8566,
            longitude: 2.3522
        ),
        Trip(
            title: "California Coast",
            destination: "San Francisco",
            destinationCode: "SFO",
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
            description: "Road trip along the beautiful California coastline",
            latitude: 37.7749,
            longitude: -122.4194
        )
    ]
    
    static let sample = sampleTrips[0]
}

// MARK: - CloudKit Conversion
extension Trip {
    // Convert to CloudKit record
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Trip", recordID: CKRecord.ID(recordName: id))
        
        record["title"] = title
        record["destination"] = destination
        record["destinationCode"] = destinationCode
        record["startDate"] = startDate
        record["endDate"] = endDate
        record["description"] = description
        record["coverImageURL"] = coverImageURL
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        
        return record
    }
    
    // Create from CloudKit record
    static func fromCKRecord(_ record: CKRecord) -> Trip? {
        guard let title = record["title"] as? String,
              let destination = record["destination"] as? String,
              let startDate = record["startDate"] as? Date,
              let endDate = record["endDate"] as? Date else {
            return nil
        }
        
        return Trip(
            id: record.recordID.recordName,
            title: title,
            destination: destination,
            destinationCode: record["destinationCode"] as? String,
            startDate: startDate,
            endDate: endDate,
            description: record["description"] as? String,
            coverImageURL: record["coverImageURL"] as? String,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date()
        )
    }
}