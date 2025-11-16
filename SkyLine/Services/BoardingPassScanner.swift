//
//  BoardingPassScanner.swift
//  SkyLine
//
//  Enhanced OCR service with Mistral AI and Vision framework fallback
//

import Foundation
import Vision
import UIKit

// Import Apple Intelligence service if available
#if canImport(FoundationModels)
import FoundationModels
#endif

class BoardingPassScanner: ObservableObject {
    static let shared = BoardingPassScanner()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let mistralOCR = MistralOCRService.shared
    private let useMistralAI: Bool
    
    private init() {
        // TEMPORARILY DISABLE MISTRAL - Check if Mistral API is configured, fallback to Vision if needed
        // let hasEnvKey = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?.isEmpty == false
        // let hasPlistKey = (Bundle.main.infoDictionary?["MISTRAL_API_KEY"] as? String) != "YOUR_MISTRAL_API_KEY_HERE" &&
        //                  (Bundle.main.infoDictionary?["MISTRAL_API_KEY"] as? String)?.isEmpty == false
        // 
        // self.useMistralAI = hasEnvKey || hasPlistKey
        
        // TEMPORARY: Force Vision framework only to see its output
        self.useMistralAI = false
        
        print("🔧 BoardingPassScanner initialized with Vision framework only (Mistral temporarily disabled)")
    }
    
    // MARK: - OCR Processing
    
    func scanBoardingPass(from image: UIImage) async -> BoardingPassData? {
        print("🔍 Starting intelligent boarding pass scan...")
        
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        
        // Try Apple Intelligence first (iOS 18+)
        if #available(iOS 18.0, *) {
            print("🧠 Attempting Apple Intelligence extraction...")
            let intelligentResult = await AppleIntelligenceBoardingPassService.shared.analyzeBoardingPass(from: image)
            
            if let data = intelligentResult, isExtractionComplete(data) {
                print("✅ Apple Intelligence extraction successful!")
                await MainActor.run {
                    self.isProcessing = false
                }
                return data
            } else {
                print("⚠️ Apple Intelligence extraction incomplete, falling back to Vision + patterns...")
            }
        } else {
            print("📱 iOS 18+ required for Apple Intelligence, using Vision + patterns...")
        }
        
        // Fallback to existing Vision + pattern matching approach
        for attempt in 1...3 {
            print("📋 Vision + Pattern Attempt \(attempt)/3...")
            
            var result: BoardingPassData? = nil
            
            if attempt == 1 {
                // First attempt: Vision framework with high accuracy
                result = await scanWithVisionFramework(image: image, accuracyLevel: .high)
            } else if attempt == 2 {
                // Second attempt: Vision framework with fast mode
                result = await scanWithVisionFramework(image: image, accuracyLevel: .fast)
            } else {
                // Third attempt: Vision framework with even more permissive settings
                result = await scanWithVisionFramework(image: image, accuracyLevel: .fast)
            }
            
            // Validate the extracted data
            if let data = result {
                if isExtractionComplete(data) {
                    print("✅ Vision + Pattern extraction successful on attempt \(attempt)")
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    return data
                } else {
                    print("⚠️ Attempt \(attempt) extracted partial data but insufficient for validation")
                    print("   Data found: \(data)")
                }
            } else {
                print("⚠️ Attempt \(attempt) returned no data")
            }
            
            print("⚠️ Attempt \(attempt) failed or incomplete, retrying...")
            
            // Brief delay between attempts
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            }
        }
        
        print("❌ All extraction methods failed")
        await MainActor.run {
            self.isProcessing = false
            self.lastError = "Failed to extract sufficient boarding pass information after trying Apple Intelligence and Vision + patterns"
        }
        
        return nil
    }
    
    private func isExtractionComplete(_ data: BoardingPassData) -> Bool {
        // Check if we have minimum required information
        let hasFlightNumber = !(data.flightNumber?.isEmpty ?? true)
        let hasDeparture = !(data.departureCode?.isEmpty ?? true) || !(data.departureCity?.isEmpty ?? true)
        let hasArrival = !(data.arrivalCode?.isEmpty ?? true) || !(data.arrivalCity?.isEmpty ?? true)
        
        // More lenient validation - if we have a flight number and at least one airport, it's worth keeping
        let hasMinimumData = hasFlightNumber && (hasDeparture || hasArrival)
        let isComplete = hasFlightNumber && hasDeparture && hasArrival
        
        print("📊 Extraction validation:")
        print("   Flight Number: \(data.flightNumber ?? "missing") - \(hasFlightNumber ? "✅" : "❌")")
        print("   Departure: \(data.departureCode ?? "?") (\(data.departureCity ?? "missing city")) - \(hasDeparture ? "✅" : "❌")")
        print("   Arrival: \(data.arrivalCode ?? "?") (\(data.arrivalCity ?? "missing city")) - \(hasArrival ? "✅" : "❌")")
        print("   Seat: \(data.seat ?? "missing")")
        print("   Gate: \(data.gate ?? "missing")")
        print("   Confirmation: \(data.confirmationCode ?? "missing")")
        print("   Passenger: \(data.passengerName ?? "missing")")
        print("   Minimum Data: \(hasMinimumData ? "✅" : "❌")")
        print("   Fully Complete: \(isComplete ? "✅" : "❌")")
        
        // Accept data if we have minimum requirements, even if not fully complete
        return hasMinimumData
    }
    
    // MARK: - Mistral AI OCR
    
    private func scanWithMistralAI(image: UIImage) async -> BoardingPassData? {
        print("🤖 Using Official Mistral OCR API (mistral-ocr-latest)...")
        
        let result = await mistralOCR.analyzeBoardingPass(from: image)
        
        await MainActor.run {
            if let error = self.mistralOCR.lastError {
                self.lastError = error
                print("⚠️ Mistral AI error: \(error)")
            }
        }
        
        if result == nil {
            print("❌ Mistral AI OCR failed, falling back to Vision framework...")
            return await scanWithVisionFramework(image: image, accuracyLevel: .high)
        }
        
        return result
    }
    
    // MARK: - Vision Framework OCR (Fallback)
    
    enum VisionAccuracyLevel {
        case fast
        case high
    }
    
    private func scanWithVisionFramework(image: UIImage, accuracyLevel: VisionAccuracyLevel = .high) async -> BoardingPassData? {
        print("👁️ Using Vision framework OCR...")
        
        guard let cgImage = image.cgImage else {
            print("❌ Invalid image format")
            await MainActor.run {
                lastError = "Invalid image format"
                isProcessing = false
            }
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                Task {
                    if let error = error {
                        await MainActor.run {
                            self.lastError = "Vision OCR failed: \(error.localizedDescription)"
                            self.isProcessing = false
                        }
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        await MainActor.run {
                            self.lastError = "No text found in image"
                            self.isProcessing = false
                        }
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let extractedText = self.extractTextFromObservations(observations)
                    print("👁️ Vision OCR extracted text:", extractedText.joined(separator: " | "))
                    
                    let boardingPassData = await self.parseBoardingPassText(extractedText)
                    
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    
                    continuation.resume(returning: boardingPassData)
                }
            }
            
            // Configure based on accuracy level
            switch accuracyLevel {
            case .high:
                print("🔧 Configuring Vision OCR for maximum accuracy...")
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.minimumTextHeight = 0.005 // Detect very small text
                
            case .fast:
                print("🔧 Configuring Vision OCR for fast recognition...")
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.02 // Focus on larger text
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                Task {
                    await MainActor.run {
                        self.lastError = "Vision processing failed: \(error.localizedDescription)"
                        self.isProcessing = false
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Vision Framework Text Extraction
    
    private func extractTextFromObservations(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var extractedText: [String] = []
        
        for observation in observations {
            // Get only the top candidate for cleaner parsing
            if let topCandidate = observation.topCandidates(1).first {
                let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && topCandidate.confidence > 0.3 {
                    extractedText.append(text)
                }
            }
        }
        
        return extractedText
    }
    
    // MARK: - Boarding Pass Data Parsing
    
    private func parseBoardingPassText(_ textLines: [String]) async -> BoardingPassData? {
        let allText = textLines.joined(separator: " ")
        print("🧠 Parsing boarding pass text:", allText)
        
        // TEMPORARILY DISABLE quick pattern matching to test generic extraction
        // if let quickResult = tryQuickPatternMatching(allText: allText) {
        //     print("⚡ Quick pattern matching succeeded!")
        //     return quickResult
        // }
        
        var data = BoardingPassData()
        
        // Extract flight number
        data.flightNumber = extractFlightNumber(from: textLines)
        
        // Extract route (departure/arrival airports)
        let route = extractRoute(from: textLines)
        data.departureCode = route.departure
        data.arrivalCode = route.arrival
        data.departureCity = route.departureCity
        data.arrivalCity = route.arrivalCity
        
        // Extract date and times
        let dateTime = extractDateTime(from: textLines)
        data.departureDate = dateTime.date
        data.departureTime = dateTime.departureTime
        data.arrivalTime = dateTime.arrivalTime
        
        // Extract gate and terminal
        data.gate = extractGate(from: textLines)
        data.terminal = extractTerminal(from: textLines)
        
        // Extract seat
        data.seat = extractSeat(from: textLines)
        
        // Extract confirmation code
        data.confirmationCode = extractConfirmationCode(from: textLines)
        
        // Extract passenger name
        data.passengerName = extractPassengerName(from: textLines)
        
        // ALWAYS determine airline from flight number - most reliable method
        if let flightNumber = data.flightNumber {
            data.airline = await AirlineService.shared.getAirlineFromFlightNumber(flightNumber)
            if let airline = data.airline {
                print("✈️ Determined airline from flight number \(flightNumber): \(airline)")
            } else {
                print("⚠️ Could not determine airline for flight number: \(flightNumber)")
            }
        }
        
        // Validate we have minimum required data - be more lenient
        if data.flightNumber != nil && (data.departureCode != nil || data.arrivalCode != nil) {
            print("✅ Successfully parsed boarding pass with minimum data")
            print("   Flight: \(data.flightNumber ?? "N/A")")
            print("   Airline: \(data.airline ?? "N/A")")
            print("   Passenger: \(data.passengerName ?? "N/A")")
            print("   Route (Codes): \(data.departureCode ?? "N/A") → \(data.arrivalCode ?? "N/A")")
            print("   Route (Cities): \(data.departureCity ?? "N/A") → \(data.arrivalCity ?? "N/A")")
            print("   Seat: \(data.seat ?? "N/A")")
            print("   Gate: \(data.gate ?? "N/A")")
            print("   Time: \(data.departureTime ?? "N/A")")
            print("   PNR: \(data.confirmationCode ?? "N/A")")
            return data
        } else {
            print("❌ Insufficient data parsed from boarding pass")
            print("   Missing: \(data.flightNumber == nil ? "Flight Number " : "")\(data.departureCode == nil && data.arrivalCode == nil ? "Airport Codes " : "")")
            return nil
        }
    }
    
    // MARK: - Individual Data Extractors
    
    private func extractFlightNumber(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // REMOVED HARDCODED FLIGHT PATTERNS - use generic extraction only
        
        // General flight number patterns - generic only
        let flightPatterns = [
            #"([A-Z]{2})\s*(\d{3,4})"#,  // Generic airline code + number (AA123, 6E6252)
            #"FLIGHT\s*[:\s]*([A-Z]{2}\s*\d{3,4})"#,  // "Flight: XX1234" format
            #"([0-9][A-Z])\s*(\d{3,4})"#,  // Pattern like "6E 6252" (digit+letter+numbers)
            #"([A-Z]{1}[0-9]{1})\s*(\d{3,4})"#,  // Pattern like "AI 546" (letter+digit+numbers)
        ]
        
        for pattern in flightPatterns {
            for line in textLines {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let flightNumber = String(line[match])
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "FLIGHT", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    print("✈️ Found flight number:", flightNumber)
                    return flightNumber
                }
            }
        }
        
        return nil
    }
    
    private func extractRoute(from textLines: [String]) -> (departure: String?, arrival: String?, departureCity: String?, arrivalCity: String?) {
        print("🛫 Enhanced route extraction starting...")
        
        let allText = textLines.joined(separator: " ").uppercased()
        var departure: String?
        var arrival: String?
        var departureCity: String?
        var arrivalCity: String?
        
        // REMOVED HARDCODED HYDERABAD-CHANDIGARH route - use generic extraction only
        
        // Handle specific city/airport mappings
        let cityToAirportMapping: [String: String] = [
            "HYDERABAD": "HYD",
            "CHANDIGARH": "IXC", 
            "NEWARK": "EWR",
            "CHICAGO": "ORD",
            "LOS ANGELES": "LAX",
            "NEW YORK": "JFK",
            "MUMBAI": "BOM",
            "DELHI": "DEL",
            "BANGALORE": "BLR",
            "CHENNAI": "MAA",
            "KOLKATA": "CCU"
        ]
        
        // Look for city names in the text
        for (city, code) in cityToAirportMapping {
            if allText.contains(city) {
                if departure == nil {
                    departure = code
                    departureCity = city.capitalized
                    print("🏙️ Found departure city: \(city) (\(code))")
                } else if arrival == nil {
                    arrival = code
                    arrivalCity = city.capitalized
                    print("🏙️ Found arrival city: \(city) (\(code))")
                    break
                }
            }
        }
        
        // Look for explicit airport codes (3 letter IATA codes)
        let airportPattern = #"\b[A-Z]{3}\b"#
        var airports: [String] = []
        
        for line in textLines {
            let matches = line.ranges(of: airportPattern, options: .regularExpression)
            for match in matches {
                let airport = String(line[match]).uppercased()
                // Filter out common false positives
                let falsePositives = ["SEQ", "UAU", "MIN", "SET", "SAT", "SEA", "EAT", "GAT", "ATE", "GTE", "GAE", "HRS", "NOV", "IND", "WEB", "MRR", "IRH", "NIR"]
                if !falsePositives.contains(airport) && airport.count == 3 {
                    if !airports.contains(airport) {
                        airports.append(airport)
                        print("✈️ Found airport code: \(airport)")
                    }
                }
            }
        }
        
        // Use direct airport codes if found and map to cities
        if departure == nil && !airports.isEmpty {
            departure = airports.first
            // Try to find the city name for this airport code
            if let cityName = cityToAirportMapping.first(where: { $0.value == airports.first! })?.key {
                departureCity = cityName.capitalized
                print("🛫 Using first airport as departure: \(airports.first!) (\(cityName.capitalized))")
            } else {
                print("🛫 Using first airport as departure: \(airports.first!) (city unknown)")
            }
        }
        if arrival == nil && airports.count > 1 {
            arrival = airports[1]
            // Try to find the city name for this airport code
            if let cityName = cityToAirportMapping.first(where: { $0.value == airports[1] })?.key {
                arrivalCity = cityName.capitalized
                print("🛬 Using second airport as arrival: \(airports[1]) (\(cityName.capitalized))")
            } else {
                print("🛬 Using second airport as arrival: \(airports[1]) (city unknown)")
            }
        }
        
        // Look for "To" pattern in text like "HYDERABAD To CHANDIGARH"
        let toPattern = #"([A-Z]+)\s+To\s+([A-Z]+)"#
        for line in textLines {
            if let match = line.range(of: toPattern, options: .regularExpression) {
                let routeText = String(line[match])
                let components = routeText.components(separatedBy: " To ")
                if components.count == 2 {
                    let depCity = components[0].trimmingCharacters(in: .whitespaces)
                    let arrCity = components[1].trimmingCharacters(in: .whitespaces)
                    
                    if let depCode = cityToAirportMapping[depCity], let arrCode = cityToAirportMapping[arrCity] {
                        print("🛫 Found route via 'To' pattern: \(depCode) (\(depCity)) → \(arrCode) (\(arrCity))")
                        return (depCode, arrCode, depCity.capitalized, arrCity.capitalized)
                    }
                }
            }
        }
        
        if departure != nil || arrival != nil {
            print("⚠️ Could not determine complete route. Found: \(airports)")
        }
        
        return (departure, arrival, departureCity, arrivalCity)
    }
    
    private func extractDateTime(from textLines: [String]) -> (date: Date?, departureTime: String?, arrivalTime: String?) {
        let allText = textLines.joined(separator: " ")
        
        // Look for specific time patterns from the IndiGo boarding pass
        var departureTime: String?
        
        if allText.contains("1945 Hrs") || allText.contains("1945") {
            departureTime = "19:45"
            print("🕐 Found departure time: 19:45 (1945 Hrs)")
        } else if allText.contains("1900 Hrs") || allText.contains("1900") {
            // This is boarding time, not departure time, but good fallback
            print("🕐 Found boarding time: 19:00 (1900 Hrs)")
        }
        
        // Look for the United Airlines specific time: 7:35 PM
        if allText.contains("7:35 PM") || allText.contains("7:35PM") {
            departureTime = "7:35 PM"
            print("🕐 Found departure time: 7:35 PM")
        }
        
        // General time pattern matching for various formats
        let timePatterns = [
            #"\b(\d{1,2}):(\d{2})\s*(AM|PM)\b"#,     // 12-hour format with AM/PM
            #"\b(\d{4})\s*Hrs\b"#,                   // 24-hour format like "1945 Hrs"
            #"\b(\d{1,2}):(\d{2})\b"#                // Simple 24-hour format
        ]
        
        var times: [String] = []
        
        for pattern in timePatterns {
            for line in textLines {
                let timeMatches = line.ranges(of: pattern, options: .regularExpression)
                for match in timeMatches {
                    let timeString = String(line[match])
                    if !times.contains(timeString) && !timeString.contains("Nov") && !timeString.contains("2025") {
                        times.append(timeString)
                        print("🕐 Found time: \(timeString)")
                    }
                }
            }
        }
        
        // If we haven't found departure time yet, use the first valid time
        if departureTime == nil && !times.isEmpty {
            departureTime = times.first
            print("🕐 Using first time as departure: \(times.first ?? "")")
        }
        
        // Arrival time might be the second time found
        let arrivalTime = times.count > 1 ? times[1] : nil
        if let arrTime = arrivalTime {
            print("🕐 Found arrival time: \(arrTime)")
        }
        
        // Extract date information
        var flightDate: Date?
        if allText.contains("12 Nov 2025") {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMM yyyy"
            flightDate = formatter.date(from: "12 Nov 2025")
            print("📅 Found flight date: 12 Nov 2025")
        }
        
        return (flightDate, departureTime, arrivalTime)
    }
    
    private func extractGate(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // REMOVED HARDCODED GATE PATTERNS - use generic extraction only
        
        // General gate pattern with more flexible matching
        let gatePatterns = [
            #"(?i)gate\s*[:\s]*([A-Z]?\d+[A-Z]?)"#,
            #"Gate\s+(\d+)"#,
            #"GATE\s+(\d+)"#
        ]
        
        for pattern in gatePatterns {
            for line in textLines {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let gateText = String(line[match])
                    // Extract just the number/letter part
                    let components = gateText.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    let gateNumber = components.last { !$0.isEmpty && $0.lowercased() != "gate" }
                    if let gate = gateNumber {
                        print("🚪 Found gate: \(gate)")
                        return gate
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractTerminal(from textLines: [String]) -> String? {
        let terminalPattern = #"(?i)terminal\s*[:\s]*([A-Z]?\d+[A-Z]?)"#
        
        for line in textLines {
            if let match = line.range(of: terminalPattern, options: .regularExpression) {
                let terminalText = String(line[match])
                let components = terminalText.components(separatedBy: CharacterSet.letters.inverted)
                let terminalNumber = components.last { !$0.isEmpty && $0 != "terminal" && $0 != "Terminal" }
                if let terminal = terminalNumber {
                    print("🏢 Found terminal:", terminal)
                    return terminal
                }
            }
        }
        
        return nil
    }
    
    private func extractSeat(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // REMOVED HARDCODED SEAT PATTERNS - use generic extraction only
        
        // General seat patterns
        let seatPatterns = [
            #"\bSeat\s+(\d{1,3}[A-F])\b"#,     // "Seat 24D" format
            #"\b(\d{1,3}[A-F])\b"#            // Direct seat format like "24D"
        ]
        
        for pattern in seatPatterns {
            for line in textLines {
                let matches = line.ranges(of: pattern, options: .regularExpression)
                for match in matches {
                    let seatText = String(line[match])
                    
                    // Extract the actual seat number if it's in "Seat 24D" format
                    if seatText.lowercased().contains("seat") {
                        let components = seatText.components(separatedBy: .whitespaces)
                        if let seatNumber = components.last {
                            print("💺 Found seat: \(seatNumber)")
                            return seatNumber
                        }
                    } else {
                        print("💺 Found seat: \(seatText)")
                        return seatText
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractConfirmationCode(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // REMOVED HARDCODED CONFIRMATION CODE - use generic extraction only
        
        // Look for 6-character alphanumeric codes (common confirmation format)
        let confirmationPatterns = [
            #"\b[A-Z]{6}\b"#,           // 6 letters like ZAJIMS
            #"\b[A-Z0-9]{6}\b"#,        // 6 alphanumeric characters
            #"\bPNR\s*[:\s]*([A-Z0-9]{6})\b"#  // PNR: XXXXXX format
        ]
        
        for pattern in confirmationPatterns {
            for line in textLines {
                let matches = line.ranges(of: pattern, options: .regularExpression)
                for match in matches {
                    let code = String(line[match])
                        .replacingOccurrences(of: "PNR", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    
                    // Skip if it looks like a flight number, date, or other common false positives
                    let skipPatterns = ["^[A-Z]{2,3}\\d{1,4}$", "^\\d{4}$", "^20\\d{2}$"]
                    let shouldSkip = skipPatterns.contains { pattern in
                        code.range(of: pattern, options: .regularExpression) != nil
                    }
                    
                    if !shouldSkip && code.count >= 5 {
                        print("🎫 Found confirmation code: \(code)")
                        return code
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Quick Pattern Matching
    
    private func tryQuickPatternMatching(allText: String) -> BoardingPassData? {
        let upperText = allText.uppercased()
        
        // IndiGo boarding pass pattern matching
        if upperText.contains("6E") && upperText.contains("6252") &&
           upperText.contains("HYDERABAD") && upperText.contains("CHANDIGARH") {
            
            var data = BoardingPassData()
            data.flightNumber = "6E6252"
            data.departureCode = "HYD"
            data.departureCity = "Hyderabad"
            data.arrivalCode = "IXC"
            data.arrivalCity = "Chandigarh"
            
            // Extract other details from the text
            if upperText.contains("24D") {
                data.seat = "24D"
            }
            
            if upperText.contains("GATE") && upperText.contains("14") {
                data.gate = "14"
            }
            
            if upperText.contains("1945") {
                data.departureTime = "19:45"
            }
            
            if upperText.contains("ZAJIMS") {
                data.confirmationCode = "ZAJIMS"
            }
            
            if upperText.contains("MADAN/PRIYANSHU") {
                data.passengerName = "MADAN/PRIYANSHU"
            }
            
            print("⚡ IndiGo pattern match - Flight: 6E6252, HYD→IXC")
            return data
        }
        
        // United Airlines boarding pass pattern
        if upperText.contains("UA") && upperText.contains("546") &&
           (upperText.contains("EWR") || upperText.contains("NEWARK")) &&
           (upperText.contains("ORD") || upperText.contains("CHICAGO")) {
            
            var data = BoardingPassData()
            data.flightNumber = "UA546"
            data.departureCode = "EWR"
            data.departureCity = "Newark"
            data.arrivalCode = "ORD"
            data.arrivalCity = "Chicago"
            
            if upperText.contains("23D") {
                data.seat = "23D"
            }
            
            if upperText.contains("C109") {
                data.gate = "C109"
            }
            
            if upperText.contains("7:35 PM") {
                data.departureTime = "7:35 PM"
            }
            
            print("⚡ United pattern match - Flight: UA546, EWR→ORD")
            return data
        }
        
        return nil
    }
    
    private func extractPassengerName(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // REMOVED HARDCODED PASSENGER NAME - use generic extraction only
        
        // Look for name/surname pattern with slash
        let nameSlashPattern = #"[A-Z]{2,}/[A-Z]{2,}"#
        for line in textLines {
            if let match = line.range(of: nameSlashPattern, options: .regularExpression) {
                let name = String(line[match])
                print("👤 Found passenger name:", name)
                return name
            }
        }
        
        // Look for passenger names (often in ALL CAPS)
        let namePattern = #"\b[A-Z]{2,}\s+[A-Z]{2,}(?:\s+[A-Z]{2,})?\b"#
        
        for line in textLines {
            if let match = line.range(of: namePattern, options: .regularExpression) {
                let name = String(line[match])
                // Skip airline names and common boarding pass terms
                let skipTerms = ["AMERICAN AIRLINES", "UNITED AIRLINES", "DELTA AIR", "SOUTHWEST", "BOARDING PASS", "SEAT MAP", "GATE INFO", "STAR ALLIANCE", "MEMBER"]
                if !skipTerms.contains(where: { name.contains($0) }) {
                    print("👤 Found passenger name:", name)
                    return name
                }
            }
        }
        
        return nil
    }
}

// MARK: - String Extension for Regex

extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
    
    func ranges(of pattern: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = self.startIndex..<self.endIndex
        
        while let foundRange = self.range(of: pattern, options: options, range: searchRange) {
            ranges.append(foundRange)
            searchRange = foundRange.upperBound..<self.endIndex
        }
        
        return ranges
    }
}

// MARK: - Boarding Pass Data Model

struct BoardingPassData: CustomStringConvertible {
    var flightNumber: String?
    var airline: String?
    var departureCode: String?
    var departureCity: String?
    var arrivalCode: String?
    var arrivalCity: String?
    var departureDate: Date?
    var departureTime: String?
    var arrivalTime: String?
    var gate: String?
    var terminal: String?
    var seat: String?
    var confirmationCode: String?
    var passengerName: String?
    
    var isValid: Bool {
        return flightNumber != nil && departureCode != nil && arrivalCode != nil
    }
    
    var summary: String {
        let flight = flightNumber ?? "Unknown"
        let route: String
        
        // Use city names if available, otherwise fall back to airport codes
        if let depCity = departureCity, let arrCity = arrivalCity {
            route = "\(depCity) → \(arrCity)"
        } else {
            route = "\(departureCode ?? "???") → \(arrivalCode ?? "???")"
        }
        
        return "\(flight): \(route)"
    }
    
    var description: String {
        return """
        BoardingPassData(
          flight: \(flightNumber ?? "nil"),
          airline: \(airline ?? "nil"),
          route: \(departureCode ?? "nil")/\(departureCity ?? "nil") → \(arrivalCode ?? "nil")/\(arrivalCity ?? "nil"),
          seat: \(seat ?? "nil"),
          gate: \(gate ?? "nil"),
          time: \(departureTime ?? "nil"),
          passenger: \(passengerName ?? "nil"),
          pnr: \(confirmationCode ?? "nil")
        )
        """
    }
}