//
//  ItineraryModels.swift
//  SkyLine
//
//  Data models for AI-powered itinerary parsing and creation
//

import Foundation
import CoreLocation

// MARK: - Parsed Itinerary Item

struct ItineraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let activityType: TripEntryType
    let dateTime: Date
    let location: ItineraryLocation?
    let estimatedDuration: TimeInterval? // in seconds
    let confidence: Double // 0.0 to 1.0, AI confidence in parsing
    let originalText: String? // Original parsed text for reference
    
    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        activityType: TripEntryType,
        dateTime: Date,
        location: ItineraryLocation? = nil,
        estimatedDuration: TimeInterval? = nil,
        confidence: Double = 1.0,
        originalText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.activityType = activityType
        self.dateTime = dateTime
        self.location = location
        self.estimatedDuration = estimatedDuration
        self.confidence = confidence
        self.originalText = originalText
    }
}

// MARK: - Itinerary Location

struct ItineraryLocation: Codable, Hashable {
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let country: String?
    let city: String?
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var displayName: String {
        if let address = address, !address.isEmpty {
            return "\(name), \(address)"
        }
        return name
    }
}

// MARK: - Parsed Itinerary

struct ParsedItinerary: Codable {
    let id: String
    let items: [ItineraryItem]
    let metadata: ItineraryMetadata
    let processingInfo: ProcessingInfo
    
    init(
        id: String = UUID().uuidString,
        items: [ItineraryItem],
        metadata: ItineraryMetadata,
        processingInfo: ProcessingInfo
    ) {
        self.id = id
        self.items = items
        self.metadata = metadata
        self.processingInfo = processingInfo
    }
    
    var sortedItems: [ItineraryItem] {
        return items.sorted { $0.dateTime < $1.dateTime }
    }
    
    var dateRange: (start: Date, end: Date)? {
        guard !items.isEmpty else { return nil }
        let sortedItems = self.sortedItems
        return (start: sortedItems.first!.dateTime, end: sortedItems.last!.dateTime)
    }
    
    var averageConfidence: Double {
        guard !items.isEmpty else { return 0.0 }
        return items.map(\.confidence).reduce(0, +) / Double(items.count)
    }
}

// MARK: - Itinerary Metadata

struct ItineraryMetadata: Codable {
    let tripTitle: String?
    let destination: String?
    let detectedTimeZone: String?
    let estimatedStartDate: Date?
    let estimatedEndDate: Date?
    let totalItems: Int
    let detectedLanguage: String?
    
    init(
        tripTitle: String? = nil,
        destination: String? = nil,
        detectedTimeZone: String? = nil,
        estimatedStartDate: Date? = nil,
        estimatedEndDate: Date? = nil,
        totalItems: Int = 0,
        detectedLanguage: String? = "en"
    ) {
        self.tripTitle = tripTitle
        self.destination = destination
        self.detectedTimeZone = detectedTimeZone
        self.estimatedStartDate = estimatedStartDate
        self.estimatedEndDate = estimatedEndDate
        self.totalItems = totalItems
        self.detectedLanguage = detectedLanguage
    }
}

// MARK: - Processing Info

struct ProcessingInfo: Codable {
    let sourceType: ItinerarySourceType
    let processingDate: Date
    let modelUsed: String
    let processingTime: TimeInterval
    let successfullyParsedItems: Int
    let failedItems: Int
    let warnings: [String]
    
    init(
        sourceType: ItinerarySourceType,
        processingDate: Date = Date(),
        modelUsed: String,
        processingTime: TimeInterval,
        successfullyParsedItems: Int,
        failedItems: Int = 0,
        warnings: [String] = []
    ) {
        self.sourceType = sourceType
        self.processingDate = processingDate
        self.modelUsed = modelUsed
        self.processingTime = processingTime
        self.successfullyParsedItems = successfullyParsedItems
        self.failedItems = failedItems
        self.warnings = warnings
    }
}

// MARK: - Source Type

enum ItinerarySourceType: String, Codable, CaseIterable {
    case image = "image"
    case pdf = "pdf"
    case excel = "excel"
    case csv = "csv"
    case text = "text"
    case url = "url"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF Document"
        case .excel: return "Excel Spreadsheet"
        case .csv: return "CSV File"
        case .text: return "Text"
        case .url: return "URL"
        case .manual: return "Manual Entry"
        }
    }
    
    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .excel: return "tablecells"
        case .csv: return "list.bullet.rectangle"
        case .text: return "text.alignleft"
        case .url: return "link"
        case .manual: return "pencil"
        }
    }
}

// MARK: - Conversion Extensions

extension ItineraryItem {
    /// Convert to TripEntry for adding to a trip
    func toTripEntry(tripId: String) -> TripEntry {
        return TripEntry(
            tripId: tripId,
            timestamp: dateTime,
            entryType: activityType,
            title: title,
            content: content,
            latitude: location?.latitude,
            longitude: location?.longitude,
            locationName: location?.name
        )
    }
}

extension ParsedItinerary {
    /// Convert all items to TripEntries for a specific trip
    func toTripEntries(tripId: String) -> [TripEntry] {
        return items.map { $0.toTripEntry(tripId: tripId) }
    }
    
    /// Suggest a trip from the parsed itinerary
    func suggestTrip() -> Trip? {
        guard let destination = metadata.destination,
              let dateRange = dateRange else { return nil }
        
        let title = metadata.tripTitle ?? "Trip to \(destination)"
        let description = "Itinerary imported with \(items.count) activities"
        
        // Use the most common location as trip coordinates
        let mainLocation = findMainLocation()
        
        return Trip(
            title: title,
            destination: destination,
            startDate: dateRange.start,
            endDate: dateRange.end,
            description: description,
            latitude: mainLocation?.latitude,
            longitude: mainLocation?.longitude
        )
    }
    
    private func findMainLocation() -> ItineraryLocation? {
        // Find the most frequent location or return the first one with coordinates
        return items.compactMap(\.location).first { $0.latitude != nil && $0.longitude != nil }
    }
}

// MARK: - Sample Data

extension ItineraryItem {
    static let sampleBreakfast = ItineraryItem(
        title: "Breakfast at Cafe Central",
        content: "Traditional Viennese coffeehouse experience with pastries and coffee",
        activityType: .food,
        dateTime: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date(),
        location: ItineraryLocation(
            name: "Cafe Central",
            address: "Herrengasse 14, 1010 Vienna, Austria",
            latitude: 48.2105,
            longitude: 16.3658,
            country: "Austria",
            city: "Vienna"
        ),
        estimatedDuration: 90 * 60, // 90 minutes
        confidence: 0.95
    )
    
    static let sampleMuseum = ItineraryItem(
        title: "Kunsthistorisches Museum",
        content: "World-class art museum with extensive collections from ancient Egypt to the 19th century",
        activityType: .sightseeing,
        dateTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date(),
        location: ItineraryLocation(
            name: "Kunsthistorisches Museum",
            address: "Maria-Theresien-Platz, 1010 Vienna, Austria",
            latitude: 48.2034,
            longitude: 16.3614,
            country: "Austria",
            city: "Vienna"
        ),
        estimatedDuration: 3 * 60 * 60, // 3 hours
        confidence: 0.92
    )
}

extension ParsedItinerary {
    static let sample = ParsedItinerary(
        items: [.sampleBreakfast, .sampleMuseum],
        metadata: ItineraryMetadata(
            tripTitle: "Vienna Weekend",
            destination: "Vienna, Austria",
            detectedTimeZone: "Europe/Vienna",
            estimatedStartDate: Date(),
            estimatedEndDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
            totalItems: 2
        ),
        processingInfo: ProcessingInfo(
            sourceType: .image,
            modelUsed: "gpt-4o",
            processingTime: 2.5,
            successfullyParsedItems: 2
        )
    )
}