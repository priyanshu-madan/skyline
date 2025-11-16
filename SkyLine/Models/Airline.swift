//
//  Airline.swift
//  SkyLine
//
//  Airline model for storing airline code to name mappings
//

import Foundation
import CloudKit

struct Airline: Identifiable, Codable {
    let id: String
    let code: String        // IATA airline code (e.g., "6E", "UA", "AI")
    let name: String        // Full airline name (e.g., "IndiGo", "United Airlines")
    let icaoCode: String?   // ICAO code (e.g., "IGO", "UAL") - optional
    let country: String?    // Country of origin
    let isActive: Bool      // Whether airline is currently operating
    let createdAt: Date
    let updatedAt: Date
    
    init(code: String, name: String, icaoCode: String? = nil, country: String? = nil, isActive: Bool = true) {
        self.id = UUID().uuidString
        self.code = code.uppercased()
        self.name = name
        self.icaoCode = icaoCode
        self.country = country
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // CloudKit convenience initializer
    init?(from record: CKRecord) {
        guard let code = record["code"] as? String,
              let name = record["name"] as? String else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.code = code
        self.name = name
        self.icaoCode = record["icaoCode"] as? String
        self.country = record["country"] as? String
        self.isActive = record["isActive"] as? Bool ?? true
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? Date()
    }
    
    // Convert to CloudKit record
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Airline", recordID: CKRecord.ID(recordName: id))
        record["code"] = code
        record["name"] = name
        record["icaoCode"] = icaoCode
        record["country"] = country
        record["isActive"] = isActive
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        return record
    }
}

// MARK: - Hashable & Equatable
extension Airline: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
    
    static func == (lhs: Airline, rhs: Airline) -> Bool {
        return lhs.code == rhs.code
    }
}