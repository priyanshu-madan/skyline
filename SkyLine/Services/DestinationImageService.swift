//
//  DestinationImageService.swift
//  SkyLine
//
//  CloudKit service for managing destination images shared across users
//

import Foundation
import CloudKit
import SwiftUI

// MARK: - Destination Image Model
struct DestinationImage: Identifiable {
    let id: String
    let airportCode: String
    let cityName: String
    let countryName: String?
    let image: UIImage?
    let imageURL: String?
    let recordID: CKRecord.ID
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.airportCode = record["airportCode"] as? String ?? ""
        self.cityName = record["cityName"] as? String ?? ""
        self.countryName = record["countryName"] as? String
        self.imageURL = record["imageURL"] as? String
        self.recordID = record.recordID
        
        // Handle CKAsset image
        if let asset = record["image"] as? CKAsset,
           let imageData = try? Data(contentsOf: asset.fileURL!),
           let uiImage = UIImage(data: imageData) {
            self.image = uiImage
        } else {
            self.image = nil
        }
    }
}

// MARK: - Destination Image Service
class DestinationImageService: ObservableObject {
    static let shared = DestinationImageService()
    
    private let container = CKContainer(identifier: "iCloud.com.priyanshumadan.skyline")
    private let publicDatabase: CKDatabase
    
    // Cache for loaded images
    @Published var imageCache: [String: UIImage] = [:]
    @Published var isLoading: Bool = false
    
    private let recordType = "DestinationImage"
    
    private init() {
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - Fetch Methods
    
    /// Fetch destination image for a specific airport code
    func fetchDestinationImage(for airportCode: String) async -> UIImage? {
        // Check cache first
        if let cachedImage = imageCache[airportCode] {
            print("✅ Using cached image for \(airportCode)")
            return cachedImage
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let predicate = NSPredicate(format: "airportCode == %@", airportCode)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            let result = try await publicDatabase.records(matching: query)
            
            for (_, record) in result.matchResults {
                switch record {
                case .success(let ckRecord):
                    let destinationImage = DestinationImage(from: ckRecord)
                    
                    if let image = destinationImage.image {
                        await MainActor.run {
                            imageCache[airportCode] = image
                            isLoading = false
                        }
                        print("✅ Fetched destination image for \(airportCode)")
                        return image
                    }
                case .failure(let error):
                    print("❌ Error fetching destination image record: \(error)")
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
            
            print("⚠️ No destination image found for \(airportCode)")
            return nil
            
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ Error fetching destination image for \(airportCode): \(error)")
            return nil
        }
    }
    
    /// Fetch destination image for city name (fallback)
    func fetchDestinationImageByCity(_ cityName: String) async -> UIImage? {
        // Check cache first using city name as key
        let cacheKey = "city_\(cityName.lowercased())"
        if let cachedImage = imageCache[cacheKey] {
            print("✅ Using cached city image for \(cityName)")
            return cachedImage
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let predicate = NSPredicate(format: "cityName CONTAINS[cd] %@", cityName)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            let result = try await publicDatabase.records(matching: query)
            
            for (_, record) in result.matchResults {
                switch record {
                case .success(let ckRecord):
                    let destinationImage = DestinationImage(from: ckRecord)
                    
                    if let image = destinationImage.image {
                        await MainActor.run {
                            imageCache[cacheKey] = image
                            isLoading = false
                        }
                        print("✅ Fetched destination image for city \(cityName)")
                        return image
                    }
                case .failure(let error):
                    print("❌ Error fetching city destination image record: \(error)")
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
            
            print("⚠️ No destination image found for city \(cityName)")
            return nil
            
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ Error fetching destination image for city \(cityName): \(error)")
            return nil
        }
    }
    
    /// Get destination image with fallback strategy
    func getDestinationImage(airportCode: String, cityName: String) async -> UIImage? {
        // Try airport code first
        if let image = await fetchDestinationImage(for: airportCode) {
            return image
        }
        
        // Fallback to city name
        if let image = await fetchDestinationImageByCity(cityName) {
            return image
        }
        
        return nil
    }
    
    // MARK: - Upload Methods (for seeding data)
    
    /// Upload a new destination image to CloudKit
    func uploadDestinationImage(
        airportCode: String,
        cityName: String,
        countryName: String? = nil,
        image: UIImage,
        imageURL: String? = nil
    ) async -> Bool {
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Create temporary file for image
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                await MainActor.run { isLoading = false }
                print("❌ Failed to convert image to data")
                return false
            }
            
            try imageData.write(to: tempURL)
            
            // Create CloudKit record
            let recordID = CKRecord.ID(recordName: "destination_\(airportCode.lowercased())_\(UUID().uuidString)")
            let record = CKRecord(recordType: recordType, recordID: recordID)
            
            record["airportCode"] = airportCode.uppercased()
            record["cityName"] = cityName
            record["countryName"] = countryName
            record["imageURL"] = imageURL
            record["image"] = CKAsset(fileURL: tempURL)
            
            let _ = try await publicDatabase.save(record)
            
            // Cache the uploaded image
            await MainActor.run {
                imageCache[airportCode] = image
                isLoading = false
            }
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
            print("✅ Successfully uploaded destination image for \(airportCode)")
            return true
            
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ Error uploading destination image: \(error)")
            return false
        }
    }
    
    /// Fetch all destination images (for admin/debugging)
    func fetchAllDestinationImages() async -> [DestinationImage] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let result = try await publicDatabase.records(matching: query)
            
            var images: [DestinationImage] = []
            
            for (_, record) in result.matchResults {
                switch record {
                case .success(let ckRecord):
                    let destinationImage = DestinationImage(from: ckRecord)
                    images.append(destinationImage)
                case .failure(let error):
                    print("❌ Error fetching destination image record: \(error)")
                }
            }
            
            print("✅ Fetched \(images.count) destination images")
            return images
            
        } catch {
            print("❌ Error fetching all destination images: \(error)")
            return []
        }
    }
    
    /// Clear image cache
    func clearCache() {
        DispatchQueue.main.async {
            self.imageCache.removeAll()
        }
        print("🗑️ Cleared destination image cache")
    }
}