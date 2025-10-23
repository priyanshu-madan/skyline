//
//  DestinationImageBatchUploader.swift
//  SkyLine
//
//  Utility for batch uploading destination images from a local folder
//

import Foundation
import UIKit

class DestinationImageBatchUploader {
    static let shared = DestinationImageBatchUploader()
    private let imageService = DestinationImageService.shared
    
    private init() {}
    
    /// Upload images from app bundle or documents directory
    /// Expected file naming: "AIRPORT_CODE - City Name.jpg" (e.g., "LAX - Los Angeles.jpg")
    func uploadImagesFromBundle(folderName: String = "DestinationImages") async {
        print("🚀 Starting batch upload from bundle folder: \(folderName)")
        
        guard let bundlePath = Bundle.main.path(forResource: folderName, ofType: nil),
              let imageFiles = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) else {
            print("❌ Could not find \(folderName) folder in app bundle")
            return
        }
        
        let imageExtensions = ["jpg", "jpeg", "png", "heic"]
        let validImageFiles = imageFiles.filter { file in
            imageExtensions.contains(file.lowercased().components(separatedBy: ".").last ?? "")
        }
        
        print("📁 Found \(validImageFiles.count) image files")
        
        for imageFile in validImageFiles {
            await uploadSingleImage(from: "\(bundlePath)/\(imageFile)", filename: imageFile)
            
            // Add delay to respect CloudKit rate limits
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        print("🎉 Batch upload completed!")
    }
    
    /// Upload images from Documents directory
    func uploadImagesFromDocuments(folderName: String = "DestinationImages") async {
        print("🚀 Starting batch upload from Documents folder: \(folderName)")
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesFolderPath = documentsPath.appendingPathComponent(folderName)
        
        guard let imageFiles = try? FileManager.default.contentsOfDirectory(atPath: imagesFolderPath.path) else {
            print("❌ Could not find \(folderName) folder in Documents")
            print("💡 Create folder at: \(imagesFolderPath.path)")
            return
        }
        
        let imageExtensions = ["jpg", "jpeg", "png", "heic"]
        let validImageFiles = imageFiles.filter { file in
            imageExtensions.contains(file.lowercased().components(separatedBy: ".").last ?? "")
        }
        
        print("📁 Found \(validImageFiles.count) image files")
        
        for imageFile in validImageFiles {
            let fullPath = imagesFolderPath.appendingPathComponent(imageFile).path
            await uploadSingleImage(from: fullPath, filename: imageFile)
            
            // Add delay to respect CloudKit rate limits
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        print("🎉 Batch upload completed!")
    }
    
    /// Upload images from a structured JSON manifest
    func uploadFromManifest() async {
        print("🚀 Starting upload from manifest")
        
        let destinations = getDestinationManifest()
        
        for destination in destinations {
            if let image = await downloadImage(from: destination.imageURL) {
                let success = await imageService.uploadDestinationImage(
                    airportCode: destination.airportCode,
                    cityName: destination.cityName,
                    countryName: destination.countryName,
                    image: image,
                    imageURL: destination.imageURL
                )
                
                if success {
                    print("✅ Uploaded: \(destination.cityName) (\(destination.airportCode))")
                } else {
                    print("❌ Failed: \(destination.cityName) (\(destination.airportCode))")
                }
                
                // Add delay to respect CloudKit rate limits
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
        
        print("🎉 Manifest upload completed!")
    }
    
    private func uploadSingleImage(from filePath: String, filename: String) async {
        guard let image = UIImage(contentsOfFile: filePath) else {
            print("❌ Could not load image: \(filename)")
            return
        }
        
        // Parse filename: "AIRPORT_CODE - City Name.jpg"
        let nameComponents = filename.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .components(separatedBy: " - ")
        
        guard nameComponents.count >= 2 else {
            print("❌ Invalid filename format: \(filename)")
            print("💡 Expected format: 'AIRPORT_CODE - City Name.jpg'")
            return
        }
        
        let airportCode = nameComponents[0].trimmingCharacters(in: .whitespaces)
        let cityName = nameComponents[1].trimmingCharacters(in: .whitespaces)
        let countryName = nameComponents.count > 2 ? nameComponents[2].trimmingCharacters(in: .whitespaces) : nil
        
        let success = await imageService.uploadDestinationImage(
            airportCode: airportCode,
            cityName: cityName,
            countryName: countryName,
            image: image,
            imageURL: nil
        )
        
        if success {
            print("✅ Uploaded: \(cityName) (\(airportCode))")
        } else {
            print("❌ Failed: \(cityName) (\(airportCode))")
        }
    }
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("❌ Failed to download image from: \(urlString)")
            return nil
        }
    }
}

// MARK: - Destination Manifest

private extension DestinationImageBatchUploader {
    
    struct DestinationManifest {
        let airportCode: String
        let cityName: String
        let countryName: String?
        let imageURL: String
    }
    
    /// Manifest of high-quality destination images from Unsplash
    func getDestinationManifest() -> [DestinationManifest] {
        return [
            // US Cities
            DestinationManifest(
                airportCode: "LAX",
                cityName: "Los Angeles",
                countryName: "United States",
                imageURL: "https://images.unsplash.com/photo-1534361960057-19889db9621e?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "JFK",
                cityName: "New York",
                countryName: "United States",
                imageURL: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "SFO",
                cityName: "San Francisco",
                countryName: "United States",
                imageURL: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "LAS",
                cityName: "Las Vegas",
                countryName: "United States",
                imageURL: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop"
            ),
            
            // International Cities
            DestinationManifest(
                airportCode: "LHR",
                cityName: "London",
                countryName: "United Kingdom",
                imageURL: "https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "CDG",
                cityName: "Paris",
                countryName: "France",
                imageURL: "https://images.unsplash.com/photo-1502602898536-47ad22581b52?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "NRT",
                cityName: "Tokyo",
                countryName: "Japan",
                imageURL: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800&h=600&fit=crop"
            ),
            DestinationManifest(
                airportCode: "SYD",
                cityName: "Sydney",
                countryName: "Australia",
                imageURL: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop"
            ),
        ]
    }
}