//
//  IntelligentBoardingPassDemo.swift
//  SkyLine
//
//  Demo and testing utilities for Apple Intelligence boarding pass extraction
//

import Foundation
import UIKit

// MARK: - Demo Service

class IntelligentBoardingPassDemo {
    static let shared = IntelligentBoardingPassDemo()
    
    private init() {}
    
    // MARK: - Demo Data
    
    func createSampleBoardingPassData() -> IntelligentBoardingPassData {
        return IntelligentBoardingPassData(
            flightNumber: "6E6252",
            airline: "IndiGo",
            passengerName: "MADAN/PRIYANSHU", 
            departureAirport: "Rajiv Gandhi International Airport",
            departureCity: "Hyderabad",
            departureCode: "HYD",
            arrivalAirport: "Chandigarh Airport",
            arrivalCity: "Chandigarh", 
            arrivalCode: "IXC",
            departureDate: "12 Nov 2025",
            departureTime: "19:45",
            arrivalTime: "21:15",
            seat: "24D",
            gate: "14",
            terminal: nil,
            confirmationCode: "ZAJIMS",
            boardingTime: "19:00"
        )
    }
    
    // MARK: - Validation Methods
    
    func validateExtractionQuality(_ data: IntelligentBoardingPassData) -> ExtractionQuality {
        var score = 0
        var maxScore = 0
        var issues: [String] = []
        
        // Flight Number (Critical)
        maxScore += 3
        if let flightNumber = data.flightNumber, !flightNumber.isEmpty {
            if isValidFlightNumber(flightNumber) {
                score += 3
            } else {
                score += 1
                issues.append("Flight number format may be incorrect")
            }
        } else {
            issues.append("Missing flight number (critical)")
        }
        
        // Route Information (Critical)
        maxScore += 4
        if let depCode = data.departureCode, !depCode.isEmpty, depCode.count == 3 {
            score += 2
        } else {
            issues.append("Missing or invalid departure airport code")
        }
        
        if let arrCode = data.arrivalCode, !arrCode.isEmpty, arrCode.count == 3 {
            score += 2
        } else {
            issues.append("Missing or invalid arrival airport code")
        }
        
        // Passenger Name (Important)
        maxScore += 2
        if let name = data.passengerName, !name.isEmpty {
            score += 2
        } else {
            issues.append("Missing passenger name")
        }
        
        // Additional Details (Nice to have)
        maxScore += 3
        if data.seat != nil { score += 1 }
        if data.gate != nil { score += 1 }
        if data.confirmationCode != nil { score += 1 }
        
        let qualityScore = Double(score) / Double(maxScore)
        
        if qualityScore >= 0.9 {
            return ExtractionQuality(level: .excellent, score: qualityScore, issues: issues)
        } else if qualityScore >= 0.7 {
            return ExtractionQuality(level: .good, score: qualityScore, issues: issues)
        } else if qualityScore >= 0.5 {
            return ExtractionQuality(level: .acceptable, score: qualityScore, issues: issues)
        } else {
            return ExtractionQuality(level: .poor, score: qualityScore, issues: issues)
        }
    }
    
    private func isValidFlightNumber(_ flightNumber: String) -> Bool {
        // Check for airline code (2-3 letters) + numbers
        let pattern = #"^[A-Z]{2,3}[0-9]{3,4}$"#
        return flightNumber.range(of: pattern, options: .regularExpression) != nil
    }
    
    // MARK: - Performance Comparison
    
    func compareBoardingPassExtractionMethods(image: UIImage) async -> ExtractionComparison {
        let startTime = Date()
        
        // Test Apple Intelligence (if available)
        var appleIntelligenceResult: IntelligentBoardingPassData?
        var appleIntelligenceTime: TimeInterval = 0
        
        if #available(iOS 18.0, *) {
            let aiStart = Date()
            if let legacyData = await AppleIntelligenceBoardingPassService.shared.analyzeBoardingPass(from: image) {
                // Convert back to intelligent format for comparison
                appleIntelligenceResult = convertFromLegacy(legacyData)
            }
            appleIntelligenceTime = Date().timeIntervalSince(aiStart)
        }
        
        // Test Vision + Pattern Matching
        let visionStart = Date()
        let visionResult = await BoardingPassScanner.shared.scanBoardingPass(from: image)
        let visionTime = Date().timeIntervalSince(visionStart)
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        return ExtractionComparison(
            appleIntelligenceResult: appleIntelligenceResult,
            appleIntelligenceTime: appleIntelligenceTime,
            visionPatternResult: visionResult,
            visionPatternTime: visionTime,
            totalTime: totalTime
        )
    }
    
    private func convertFromLegacy(_ data: BoardingPassData) -> IntelligentBoardingPassData {
        return IntelligentBoardingPassData(
            flightNumber: data.flightNumber,
            airline: nil, // Not available in legacy format
            passengerName: data.passengerName,
            departureAirport: nil, // Not available in legacy format
            departureCity: data.departureCity,
            departureCode: data.departureCode,
            arrivalAirport: nil, // Not available in legacy format
            arrivalCity: data.arrivalCity,
            arrivalCode: data.arrivalCode,
            departureDate: data.departureDate?.description,
            departureTime: data.departureTime,
            arrivalTime: data.arrivalTime,
            seat: data.seat,
            gate: data.gate,
            terminal: data.terminal,
            confirmationCode: data.confirmationCode,
            boardingTime: nil // Not available in legacy format
        )
    }
}

// MARK: - Quality Assessment Models

struct ExtractionQuality {
    enum Level: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case acceptable = "Acceptable" 
        case poor = "Poor"
        
        var emoji: String {
            switch self {
            case .excellent: return "🌟"
            case .good: return "✅"
            case .acceptable: return "⚠️"
            case .poor: return "❌"
            }
        }
    }
    
    let level: Level
    let score: Double
    let issues: [String]
    
    var description: String {
        let percentage = Int(score * 100)
        return "\(level.emoji) \(level.rawValue) (\(percentage)%)"
    }
}

struct ExtractionComparison {
    let appleIntelligenceResult: IntelligentBoardingPassData?
    let appleIntelligenceTime: TimeInterval
    let visionPatternResult: BoardingPassData?
    let visionPatternTime: TimeInterval
    let totalTime: TimeInterval
    
    var summary: String {
        var result = "🔍 Boarding Pass Extraction Comparison\n\n"
        
        // Apple Intelligence Results
        if let aiResult = appleIntelligenceResult {
            let quality = IntelligentBoardingPassDemo.shared.validateExtractionQuality(aiResult)
            result += "🧠 Apple Intelligence:\n"
            result += "   Quality: \(quality.description)\n"
            result += "   Time: \(String(format: "%.2f", appleIntelligenceTime))s\n"
            result += "   Flight: \(aiResult.flightNumber ?? "N/A")\n"
            result += "   Route: \(aiResult.departureCode ?? "?") → \(aiResult.arrivalCode ?? "?")\n\n"
        } else {
            result += "🧠 Apple Intelligence: Not available or failed\n\n"
        }
        
        // Vision + Pattern Results
        if let visionResult = visionPatternResult {
            result += "👁️ Vision + Patterns:\n"
            result += "   Time: \(String(format: "%.2f", visionPatternTime))s\n"
            result += "   Flight: \(visionResult.flightNumber ?? "N/A")\n"
            result += "   Route: \(visionResult.departureCode ?? "?") → \(visionResult.arrivalCode ?? "?")\n\n"
        } else {
            result += "👁️ Vision + Patterns: Failed\n\n"
        }
        
        result += "⏱️ Total Time: \(String(format: "%.2f", totalTime))s"
        
        return result
    }
}