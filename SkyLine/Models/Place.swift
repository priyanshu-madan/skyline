//
//  Place.swift
//  SkyLine
//
//  Canonical location model for the place log
//

import Foundation
import CoreLocation
import CloudKit
import MapKit

// MARK: - Place Model
/// A canonical location. One `Place` per real-world spot; every time the user
/// goes there a new `Visit` points at the same `Place.id`.
struct Place: Codable, Identifiable, Hashable {
    static let recordType = "Place"

    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let category: PlaceCategory
    let address: String?
    let city: String?
    let state: String?          // State / province, when known
    let country: String?        // Display name, e.g. "Japan"
    let countryCode: String?    // ISO 3166-1 alpha-2, e.g. "JP" - nil when unknown
    /// Stable external identifier used to dedup the same spot across visits and
    /// devices, e.g. `"mapkit:<MKMapItem.Identifier.rawValue>"` or `"iata:NRT"`.
    let externalIdentifier: String?
    let externalIdentifierSource: PlaceIdentifierSource
    let timeZoneIdentifier: String? // IANA identifier, e.g. "Asia/Tokyo"
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Computed

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone {
        if let identifier = timeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return .current
    }

    /// "Shibuya, Japan" - the line under the place name.
    var displayLocality: String {
        let parts = [city, country].compactMap { value -> String? in
            guard let value = value, !value.isEmpty else { return nil }
            return value
        }
        return parts.joined(separator: ", ")
    }

    var displayAddress: String {
        if let address = address, !address.isEmpty { return address }
        if !displayLocality.isEmpty { return displayLocality }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// Diacritic-folded, punctuation-stripped name used for fuzzy dedup.
    var normalizedName: String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Coarse geographic bucket (~11 m) - cheap pre-filter before a real
    /// distance check.
    var coarseLocationKey: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    var hasValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && !(latitude == 0 && longitude == 0)
    }

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory = .other,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        externalIdentifier: String? = nil,
        externalIdentifierSource: PlaceIdentifierSource = .none,
        timeZoneIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.address = address
        self.city = city
        self.state = state
        self.country = country
        self.countryCode = countryCode
        self.externalIdentifier = externalIdentifier
        self.externalIdentifierSource = externalIdentifierSource
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Matching / Merging
extension Place {
    func distance(to other: Place) -> CLLocationDistance {
        location.distance(from: other.location)
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    /// True when both places carry the same non-empty external identifier.
    func sharesExternalIdentifier(with other: Place) -> Bool {
        guard let mine = externalIdentifier, !mine.isEmpty,
              let theirs = other.externalIdentifier, !theirs.isEmpty else {
            return false
        }
        return mine == theirs
    }

    /// Returns a copy of `self` with any missing detail filled in from `other`.
    /// `id`, `name` and `createdAt` always stay with `self` (the stored record).
    func merged(with other: Place) -> Place {
        Place(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category == .other ? other.category : category,
            address: address ?? other.address,
            city: city ?? other.city,
            state: state ?? other.state,
            country: country ?? other.country,
            countryCode: countryCode ?? other.countryCode,
            externalIdentifier: externalIdentifier ?? other.externalIdentifier,
            externalIdentifierSource: externalIdentifier == nil ? other.externalIdentifierSource : externalIdentifierSource,
            timeZoneIdentifier: timeZoneIdentifier ?? other.timeZoneIdentifier,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    /// True when nothing user-visible differs (so an upsert can skip the write).
    func isEquivalent(to other: Place) -> Bool {
        name == other.name &&
        latitude == other.latitude &&
        longitude == other.longitude &&
        category == other.category &&
        address == other.address &&
        city == other.city &&
        state == other.state &&
        country == other.country &&
        countryCode == other.countryCode &&
        externalIdentifier == other.externalIdentifier &&
        timeZoneIdentifier == other.timeZoneIdentifier
    }

    func touched() -> Place {
        Place(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            address: address,
            city: city,
            state: state,
            country: country,
            countryCode: countryCode,
            externalIdentifier: externalIdentifier,
            externalIdentifierSource: externalIdentifierSource,
            timeZoneIdentifier: timeZoneIdentifier,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    /// Conservative country-code helper. Only the code -> display-name direction
    /// is a stable Foundation API, so we never guess a code from a name.
    static func countryName(forCode code: String?) -> String? {
        guard let code = code, code.count == 2 else { return nil }
        return Locale.current.localizedString(forRegionCode: code.uppercased())
    }
}

// MARK: - Place Identifier Source
enum PlaceIdentifierSource: String, Codable, CaseIterable, Hashable {
    case mapKit = "mapKit"          // MKMapItem.Identifier.rawValue
    case airportCode = "airportCode" // IATA code from an imported Flight
    case skylineTrip = "skylineTrip" // Legacy Trip record
    case photoCluster = "photoCluster" // Derived from a camera-roll cluster
    case none = "none"

    /// Total decode - see the `Verdict` note.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self) else {
            self = .none
            return
        }
        self = PlaceIdentifierSource(rawValue: raw) ?? .none
    }
}

// MARK: - Place Category
enum PlaceCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case restaurant = "restaurant"
    case cafe = "cafe"
    case bar = "bar"
    case bakery = "bakery"
    case hotel = "hotel"
    case museum = "museum"
    case gallery = "gallery"
    case landmark = "landmark"
    case park = "park"
    case nature = "nature"
    case beach = "beach"
    case viewpoint = "viewpoint"
    case shop = "shop"
    case market = "market"
    case nightlife = "nightlife"
    case entertainment = "entertainment"
    case sports = "sports"
    case wellness = "wellness"
    case transit = "transit"
    case airport = "airport"
    case city = "city"
    case neighborhood = "neighborhood"
    case other = "other"

    var id: String { rawValue }

    /// Total decode - unknown categories become `.other` instead of throwing.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self) else {
            self = .other
            return
        }
        self = PlaceCategory(rawValue: raw) ?? .other
    }

    var displayName: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .cafe: return "Cafe"
        case .bar: return "Bar"
        case .bakery: return "Bakery"
        case .hotel: return "Stay"
        case .museum: return "Museum"
        case .gallery: return "Gallery"
        case .landmark: return "Landmark"
        case .park: return "Park"
        case .nature: return "Nature"
        case .beach: return "Beach"
        case .viewpoint: return "Viewpoint"
        case .shop: return "Shop"
        case .market: return "Market"
        case .nightlife: return "Nightlife"
        case .entertainment: return "Entertainment"
        case .sports: return "Sports"
        case .wellness: return "Wellness"
        case .transit: return "Transit"
        case .airport: return "Airport"
        case .city: return "City"
        case .neighborhood: return "Neighborhood"
        case .other: return "Place"
        }
    }

    var systemImage: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .bakery: return "birthday.cake"
        case .hotel: return "bed.double"
        case .museum: return "building.columns"
        case .gallery: return "photo.artframe"
        case .landmark: return "mappin.and.ellipse"
        case .park: return "tree"
        case .nature: return "mountain.2"
        case .beach: return "beach.umbrella"
        case .viewpoint: return "binoculars"
        case .shop: return "bag"
        case .market: return "cart"
        case .nightlife: return "music.note"
        case .entertainment: return "theatermasks"
        case .sports: return "sportscourt"
        case .wellness: return "figure.mind.and.body"
        case .transit: return "tram"
        case .airport: return "airplane"
        case .city: return "building.2"
        case .neighborhood: return "map"
        case .other: return "mappin"
        }
    }

    var emoji: String {
        switch self {
        case .restaurant: return "🍽️"
        case .cafe: return "☕️"
        case .bar: return "🍸"
        case .bakery: return "🥐"
        case .hotel: return "🛏️"
        case .museum: return "🏛️"
        case .gallery: return "🖼️"
        case .landmark: return "📍"
        case .park: return "🌳"
        case .nature: return "⛰️"
        case .beach: return "🏖️"
        case .viewpoint: return "🔭"
        case .shop: return "🛍️"
        case .market: return "🧺"
        case .nightlife: return "🎶"
        case .entertainment: return "🎭"
        case .sports: return "🏟️"
        case .wellness: return "🧘"
        case .transit: return "🚉"
        case .airport: return "✈️"
        case .city: return "🏙️"
        case .neighborhood: return "🗺️"
        case .other: return "📌"
        }
    }

    /// Bridge from the legacy journal model so the importer can classify old rows.
    init(tripEntryType: TripEntryType) {
        switch tripEntryType {
        case .food: self = .restaurant
        case .activity: self = .entertainment
        case .sightseeing: self = .landmark
        case .accommodation: self = .hotel
        case .transportation: self = .transit
        case .flight: self = .airport
        case .shopping: self = .shop
        case .note: self = .other
        case .photo: self = .other
        }
    }
}

// MARK: - MapKit Bridge
extension Place {
    /// VERIFIED against the iPhoneOS26.0 SDK headers on this machine:
    ///   MKMapItem.h:24  `identifier` -> `MKMapItem.Identifier?`, ios(18.0)+
    ///   MKMapItemIdentifier.h        `rawValue: String`
    ///   MKMapItem.h:35  `location: CLLocation`, ios(26.0)+
    ///   MKMapItem.h:36  `address: MKAddress?`, ios(26.0)+
    ///   MKMapItem.h:37  `addressRepresentations: MKAddressRepresentations?`, ios(26.0)+
    /// The project's IPHONEOS_DEPLOYMENT_TARGET is 26.0, so all of the above are
    /// usable unconditionally and `placemark` (deprecated in iOS 26) is avoided.
    ///
    /// NOT used: `MKAddressRepresentations.regionCode` is NS_REFINED_FOR_SWIFT,
    /// so its Swift signature is not something to rely on blind - `countryCode`
    /// is therefore left nil here and only populated when a caller knows it.
    init(mapItem: MKMapItem, id: String = UUID().uuidString) {
        let coordinate = mapItem.location.coordinate
        let representations = mapItem.addressRepresentations
        let identifier = mapItem.identifier?.rawValue

        self.init(
            id: id,
            name: mapItem.name ?? representations?.cityName ?? "Unnamed place",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: PlaceCategory(mapKitCategory: mapItem.pointOfInterestCategory),
            address: mapItem.address?.fullAddress,
            city: representations?.cityName,
            state: nil, // `cityWithContext` is "Cupertino, CA" - parsing it is fragile
            country: representations?.regionName,
            countryCode: nil,
            externalIdentifier: identifier.map { "mapkit:\($0)" },
            externalIdentifierSource: identifier == nil ? .none : .mapKit,
            timeZoneIdentifier: mapItem.timeZone?.identifier
        )
    }
}

extension PlaceCategory {
    /// Only iOS 13-era `MKPointOfInterestCategory` constants are matched, so the
    /// switch stays valid regardless of SDK. Everything else lands on `.other`.
    init(mapKitCategory: MKPointOfInterestCategory?) {
        guard let mapKitCategory = mapKitCategory else {
            self = .other
            return
        }

        switch mapKitCategory {
        case .restaurant, .foodMarket:
            self = .restaurant
        case .cafe:
            self = .cafe
        case .brewery, .winery, .nightlife:
            self = .bar
        case .bakery:
            self = .bakery
        case .hotel, .campground:
            self = .hotel
        case .museum:
            self = .museum
        case .nationalPark, .park:
            self = .park
        case .beach:
            self = .beach
        case .aquarium, .zoo, .amusementPark, .movieTheater, .theater:
            self = .entertainment
        case .store:
            self = .shop
        case .stadium:
            self = .sports
        case .fitnessCenter:
            self = .wellness
        case .publicTransport:
            self = .transit
        case .airport:
            self = .airport
        case .library, .university, .school:
            self = .landmark
        case .marina:
            self = .nature
        default:
            self = .other
        }
    }
}

// MARK: - CloudKit Conversion
extension Place {
    /// Field types, for the CloudKit Dashboard:
    ///   name                     String
    ///   latitude                 Double
    ///   longitude                Double
    ///   category                 String
    ///   address                  String  (optional)
    ///   city                     String  (optional)
    ///   state                    String  (optional)
    ///   country                  String  (optional)
    ///   countryCode              String  (optional)
    ///   externalIdentifier       String  (optional, QUERYABLE - dedup lookups)
    ///   externalIdentifierSource String
    ///   timeZoneIdentifier       String  (optional)
    ///   createdAt                Date/Time (QUERYABLE - fetch predicate)
    ///   updatedAt                Date/Time
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Place.recordType, recordID: CKRecord.ID(recordName: id))
        apply(to: record)
        return record
    }

    /// Field-by-field write onto an existing record, so a fetch-then-mutate
    /// update never clobbers server metadata (same approach as
    /// `TripStore.updateEntry`).
    func apply(to record: CKRecord) {
        record["name"] = name
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["category"] = category.rawValue
        record["address"] = address
        record["city"] = city
        record["state"] = state
        record["country"] = country
        record["countryCode"] = countryCode
        record["externalIdentifier"] = externalIdentifier
        record["externalIdentifierSource"] = externalIdentifierSource.rawValue
        record["timeZoneIdentifier"] = timeZoneIdentifier
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
    }

    static func fromCKRecord(_ record: CKRecord) -> Place? {
        guard let name = record["name"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else {
            return nil
        }

        // Never guard on an enum raw value - fall back instead (commit d962e9e).
        let category = PlaceCategory(rawValue: record["category"] as? String ?? "") ?? .other
        let identifierSource = PlaceIdentifierSource(rawValue: record["externalIdentifierSource"] as? String ?? "") ?? .none

        return Place(
            id: record.recordID.recordName,
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            address: record["address"] as? String,
            city: record["city"] as? String,
            state: record["state"] as? String,
            country: record["country"] as? String,
            countryCode: record["countryCode"] as? String,
            externalIdentifier: record["externalIdentifier"] as? String,
            externalIdentifierSource: identifierSource,
            timeZoneIdentifier: record["timeZoneIdentifier"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date()
        )
    }
}

// MARK: - Sample Data
extension Place {
    static let samplePlaces: [Place] = [
        Place(
            name: "Fuglen Tokyo",
            latitude: 35.6693,
            longitude: 139.6957,
            category: .cafe,
            address: "1-16-11 Tomigaya, Shibuya City, Tokyo",
            city: "Tokyo",
            country: "Japan",
            countryCode: "JP",
            externalIdentifier: "mapkit:SAMPLE-FUGLEN",
            externalIdentifierSource: .mapKit,
            timeZoneIdentifier: "Asia/Tokyo"
        ),
        Place(
            name: "Shinjuku Gyoen",
            latitude: 35.6852,
            longitude: 139.7100,
            category: .park,
            city: "Tokyo",
            country: "Japan",
            countryCode: "JP",
            timeZoneIdentifier: "Asia/Tokyo"
        ),
        Place(
            name: "Narita International Airport",
            latitude: 35.7719,
            longitude: 140.3928,
            category: .airport,
            city: "Narita",
            country: "Japan",
            countryCode: "JP",
            externalIdentifier: "iata:NRT",
            externalIdentifierSource: .airportCode,
            timeZoneIdentifier: "Asia/Tokyo"
        )
    ]

    static let sample = samplePlaces[0]
}

// MARK: - Sorting
extension Array where Element == Place {
    func sortedByName() -> [Place] {
        sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func groupedByCountry() -> [String: [Place]] {
        Dictionary(grouping: self) { $0.country ?? "Unknown" }
    }

    func nearest(to coordinate: CLLocationCoordinate2D) -> Place? {
        self.min { lhs, rhs in
            lhs.distance(to: coordinate) < rhs.distance(to: coordinate)
        }
    }
}
