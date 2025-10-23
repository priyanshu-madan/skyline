//
//  DestinationImageSeeder.swift
//  SkyLine
//
//  Service for seeding initial destination images to CloudKit
//

import Foundation
import SwiftUI

class DestinationImageSeeder {
    static let shared = DestinationImageSeeder()
    private let imageService = DestinationImageService.shared
    
    private init() {}
    
    /// Seed popular destination images with placeholder data
    func seedInitialDestinationImages() async {
        print("🌱 Starting destination image seeding...")
        
        let destinations = getPopularDestinations()
        
        for destination in destinations {
            // Generate a placeholder image for each destination
            let placeholderImage = generatePlaceholderImage(
                for: destination.cityName,
                airportCode: destination.airportCode,
                color: destination.color
            )
            
            let success = await imageService.uploadDestinationImage(
                airportCode: destination.airportCode,
                cityName: destination.cityName,
                countryName: destination.countryName,
                image: placeholderImage,
                imageURL: nil
            )
            
            if success {
                print("✅ Seeded image for \(destination.cityName) (\(destination.airportCode))")
            } else {
                print("❌ Failed to seed image for \(destination.cityName) (\(destination.airportCode))")
            }
            
            // Add delay to avoid overwhelming CloudKit
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("🎉 Destination image seeding completed!")
    }
    
    /// Check if seeding has been completed
    func checkIfSeedingNeeded() async -> Bool {
        let existingImages = await imageService.fetchAllDestinationImages()
        return existingImages.isEmpty
    }
    
    /// Seed destination images if needed (call this on app launch)
    func seedIfNeeded() async {
        let needsSeeding = await checkIfSeedingNeeded()
        
        if needsSeeding {
            print("🌱 No destination images found - starting seeding process")
            await seedInitialDestinationImages()
        } else {
            print("✅ Destination images already exist - skipping seeding")
        }
    }
}

// MARK: - Private Helper Methods

private extension DestinationImageSeeder {
    
    struct DestinationInfo {
        let airportCode: String
        let cityName: String
        let countryName: String
        let color: UIColor
    }
    
    func getPopularDestinations() -> [DestinationInfo] {
        return [
            // US Destinations
            DestinationInfo(airportCode: "LAX", cityName: "Los Angeles", countryName: "United States", color: .systemBlue),
            DestinationInfo(airportCode: "JFK", cityName: "New York", countryName: "United States", color: .systemIndigo),
            DestinationInfo(airportCode: "SFO", cityName: "San Francisco", countryName: "United States", color: .systemOrange),
            DestinationInfo(airportCode: "ORD", cityName: "Chicago", countryName: "United States", color: .systemRed),
            DestinationInfo(airportCode: "MIA", cityName: "Miami", countryName: "United States", color: .systemTeal),
            DestinationInfo(airportCode: "LAS", cityName: "Las Vegas", countryName: "United States", color: .systemYellow),
            DestinationInfo(airportCode: "SEA", cityName: "Seattle", countryName: "United States", color: .systemGreen),
            DestinationInfo(airportCode: "DEN", cityName: "Denver", countryName: "United States", color: .systemPurple),
            
            // International Destinations
            DestinationInfo(airportCode: "LHR", cityName: "London", countryName: "United Kingdom", color: .systemBlue),
            DestinationInfo(airportCode: "CDG", cityName: "Paris", countryName: "France", color: .systemPink),
            DestinationInfo(airportCode: "NRT", cityName: "Tokyo", countryName: "Japan", color: .systemRed),
            DestinationInfo(airportCode: "SYD", cityName: "Sydney", countryName: "Australia", color: .systemOrange),
            DestinationInfo(airportCode: "DXB", cityName: "Dubai", countryName: "UAE", color: .systemYellow),
            DestinationInfo(airportCode: "SIN", cityName: "Singapore", countryName: "Singapore", color: .systemGreen),
            DestinationInfo(airportCode: "HKG", cityName: "Hong Kong", countryName: "Hong Kong", color: .systemIndigo),
            DestinationInfo(airportCode: "FRA", cityName: "Frankfurt", countryName: "Germany", color: .systemGray),
            
            // Additional Popular Destinations
            DestinationInfo(airportCode: "YYZ", cityName: "Toronto", countryName: "Canada", color: .systemRed),
            DestinationInfo(airportCode: "MEX", cityName: "Mexico City", countryName: "Mexico", color: .systemGreen),
            DestinationInfo(airportCode: "GRU", cityName: "São Paulo", countryName: "Brazil", color: .systemYellow),
            DestinationInfo(airportCode: "ICN", cityName: "Seoul", countryName: "South Korea", color: .systemBlue),
            DestinationInfo(airportCode: "BOM", cityName: "Mumbai", countryName: "India", color: .systemOrange),
            DestinationInfo(airportCode: "PEK", cityName: "Beijing", countryName: "China", color: .systemRed),
            DestinationInfo(airportCode: "MAD", cityName: "Madrid", countryName: "Spain", color: .systemYellow),
            DestinationInfo(airportCode: "AMS", cityName: "Amsterdam", countryName: "Netherlands", color: .systemOrange),
        ]
    }
    
    func generatePlaceholderImage(for cityName: String, airportCode: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Background gradient
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    color.withAlphaComponent(0.8).cgColor,
                    color.withAlphaComponent(0.3).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // Add city name text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .shadow: {
                    let shadow = NSShadow()
                    shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
                    shadow.shadowOffset = CGSize(width: 2, height: 2)
                    shadow.shadowBlurRadius = 4
                    return shadow
                }()
            ]
            
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraphStyle,
                .shadow: {
                    let shadow = NSShadow()
                    shadow.shadowColor = UIColor.black.withAlphaComponent(0.3)
                    shadow.shadowOffset = CGSize(width: 1, height: 1)
                    shadow.shadowBlurRadius = 2
                    return shadow
                }()
            ]
            
            // Draw city name
            let titleRect = CGRect(x: 20, y: size.height/2 - 40, width: size.width - 40, height: 40)
            cityName.draw(in: titleRect, withAttributes: titleAttributes)
            
            // Draw airport code
            let subtitleRect = CGRect(x: 20, y: size.height/2 + 10, width: size.width - 40, height: 30)
            airportCode.draw(in: subtitleRect, withAttributes: subtitleAttributes)
            
            // Add decorative airplane icon
            let airplaneSize: CGFloat = 24
            let airplaneRect = CGRect(
                x: size.width - airplaneSize - 20,
                y: 20,
                width: airplaneSize,
                height: airplaneSize
            )
            
            // Draw simple airplane shape
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
            context.cgContext.fillEllipse(in: airplaneRect)
        }
    }
}