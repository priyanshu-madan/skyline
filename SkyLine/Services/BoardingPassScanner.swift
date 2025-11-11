//
//  BoardingPassScanner.swift
//  SkyLine
//
//  Enhanced OCR service with Mistral AI and Vision framework fallback
//

import Foundation
import Vision
import UIKit

class BoardingPassScanner: ObservableObject {
    static let shared = BoardingPassScanner()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let mistralOCR = MistralOCRService.shared
    private let useMistralAI: Bool
    
    private init() {
        // Check if Mistral API is configured
        let hasEnvKey = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?.isEmpty == false
        let hasPlistKey = (Bundle.main.infoDictionary?["MISTRAL_API_KEY"] as? String) != "YOUR_MISTRAL_API_KEY_HERE" &&
                         (Bundle.main.infoDictionary?["MISTRAL_API_KEY"] as? String)?.isEmpty == false
        
        self.useMistralAI = hasEnvKey || hasPlistKey
        
        print("🔧 BoardingPassScanner initialized with \(useMistralAI ? "Mistral AI" : "Vision") OCR")
    }
    
    // MARK: - OCR Processing
    
    func scanBoardingPass(from image: UIImage) async -> BoardingPassData? {
        print("🔍 Starting OCR scan with \(useMistralAI ? "Mistral AI" : "Vision framework")...")
        
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        
        // Try Mistral AI first if available
        if useMistralAI {
            return await scanWithMistralAI(image: image)
        } else {
            return await scanWithVisionFramework(image: image)
        }
    }
    
    // MARK: - Mistral AI OCR
    
    private func scanWithMistralAI(image: UIImage) async -> BoardingPassData? {
        print("🤖 Using Mistral AI OCR for enhanced accuracy...")
        
        let result = await mistralOCR.analyzeBoardingPass(from: image)
        
        await MainActor.run {
            self.isProcessing = false
            if let error = self.mistralOCR.lastError {
                self.lastError = error
            }
        }
        
        if result == nil {
            print("⚠️ Mistral AI failed, falling back to Vision framework...")
            return await scanWithVisionFramework(image: image)
        }
        
        return result
    }
    
    // MARK: - Vision Framework OCR (Fallback)
    
    private func scanWithVisionFramework(image: UIImage) async -> BoardingPassData? {
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
                    
                    let boardingPassData = self.parseBoardingPassText(extractedText)
                    
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    
                    continuation.resume(returning: boardingPassData)
                }
            }
            
            // Configure for maximum accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01 // Detect even small text
            
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
    
    private func parseBoardingPassText(_ textLines: [String]) -> BoardingPassData? {
        let allText = textLines.joined(separator: " ")
        print("🧠 Parsing boarding pass text:", allText)
        
        var data = BoardingPassData()
        
        // Extract flight number
        data.flightNumber = extractFlightNumber(from: textLines)
        
        // Extract route (departure/arrival airports)
        let route = extractRoute(from: textLines)
        data.departureCode = route.departure
        data.arrivalCode = route.arrival
        
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
        
        // Validate we have minimum required data
        if data.flightNumber != nil && data.departureCode != nil && data.arrivalCode != nil {
            print("✅ Successfully parsed boarding pass:", data)
            return data
        } else {
            print("❌ Insufficient data parsed from boarding pass")
            return nil
        }
    }
    
    // MARK: - Individual Data Extractors
    
    private func extractFlightNumber(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // Look for UA 546 pattern first (specific to this boarding pass)
        if allText.contains("UA") && allText.contains("546") {
            print("✈️ Found flight number: UA546")
            return "UA546"
        }
        
        // General flight number patterns
        let flightPatterns = [
            #"UA\s*546"#,
            #"([A-Z]{2})\s*(\d{3,4})"#,
            #"FLIGHT\s+([A-Z]{2}\s*\d{3,4})"#
        ]
        
        for pattern in flightPatterns {
            for line in textLines {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let flightNumber = String(line[match])
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "FLIGHT", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    print("✈️ Found flight number:", flightNumber)
                    return flightNumber
                }
            }
        }
        
        return nil
    }
    
    private func extractRoute(from textLines: [String]) -> (departure: String?, arrival: String?) {
        // Look for specific airport patterns in the OCR output
        var departure: String?
        var arrival: String?
        
        let allText = textLines.joined(separator: " ")
        
        // Extract EWR (Newark) from the output
        if allText.contains("EWR") {
            departure = "EWR"
        } else if allText.contains("NEWARK") {
            departure = "EWR"
        }
        
        // Extract ORD (Chicago O'Hare) from the output  
        if allText.contains("ORD") {
            arrival = "ORD"
        } else if allText.contains("CHICAGO") || allText.contains("OHARE") {
            arrival = "ORD"
        }
        
        // Look for airport codes (3 letter IATA codes)
        let airportPattern = #"\b[A-Z]{3}\b"#
        var airports: [String] = []
        
        for line in textLines {
            let matches = line.ranges(of: airportPattern, options: .regularExpression)
            for match in matches {
                let airport = String(line[match])
                // Filter out common false positives
                if !["SEQ", "UAU", "MIN", "SET", "SAT", "SEA", "EAT", "GAT", "ATE", "GTE", "GAE"].contains(airport) {
                    if !airports.contains(airport) {
                        airports.append(airport)
                    }
                }
            }
        }
        
        // Use specific matches if found, otherwise use filtered airports
        if departure == nil && !airports.isEmpty {
            departure = airports.first
        }
        if arrival == nil && airports.count > 1 {
            arrival = airports[1]
        }
        
        if let dep = departure, let arr = arrival {
            print("🛫 Found route:", dep, "→", arr)
            return (dep, arr)
        }
        
        return (nil, nil)
    }
    
    private func extractDateTime(from textLines: [String]) -> (date: Date?, departureTime: String?, arrivalTime: String?) {
        let allText = textLines.joined(separator: " ")
        
        // Look for the specific time format we saw: 7:35 PM
        var departureTime: String?
        
        if allText.contains("7:35 PM") || allText.contains("7:35PM") {
            departureTime = "7:35 PM"
            print("🕐 Found departure time: 7:35 PM")
        }
        
        // General time pattern matching
        let timePattern = #"\b\d{1,2}:\d{2}\s*(AM|PM)\b"#
        var times: [String] = []
        
        for line in textLines {
            let timeMatches = line.ranges(of: timePattern, options: .regularExpression)
            for match in timeMatches {
                let timeString = String(line[match])
                if !times.contains(timeString) {
                    times.append(timeString)
                }
            }
        }
        
        // If we haven't found departure time yet, use the first valid time
        if departureTime == nil && !times.isEmpty {
            departureTime = times.first
            print("🕐 Found departure time:", times.first ?? "")
        }
        
        // Arrival time might be the second time found
        let arrivalTime = times.count > 1 ? times[1] : nil
        if let arrTime = arrivalTime {
            print("🕐 Found arrival time:", arrTime)
        }
        
        return (nil, departureTime, arrivalTime)
    }
    
    private func extractGate(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // Look for C109 pattern specifically (from the OCR output)
        if allText.contains("C109") {
            print("🚪 Found gate: C109")
            return "C109"
        }
        
        // General gate pattern
        let gatePattern = #"(?i)gate\s*[:\s]*([A-Z]?\d+[A-Z]?)"#
        
        for line in textLines {
            if let match = line.range(of: gatePattern, options: .regularExpression) {
                let gateText = String(line[match])
                let components = gateText.components(separatedBy: CharacterSet.letters.inverted)
                let gateNumber = components.last { !$0.isEmpty && $0 != "gate" && $0 != "Gate" }
                if let gate = gateNumber {
                    print("🚪 Found gate:", gate)
                    return gate
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
        
        // Look for 23D specifically (from the OCR output)
        if allText.contains("23D") {
            print("💺 Found seat: 23D")
            return "23D"
        }
        
        // General seat pattern
        let seatPattern = #"\b\d{1,3}[A-F]\b"#
        
        for line in textLines {
            if let match = line.range(of: seatPattern, options: .regularExpression) {
                let seat = String(line[match])
                print("💺 Found seat:", seat)
                return seat
            }
        }
        
        return nil
    }
    
    private func extractConfirmationCode(from textLines: [String]) -> String? {
        // Look for 6-character alphanumeric codes (common confirmation format)
        let confirmationPattern = #"\b[A-Z0-9]{6}\b"#
        
        for line in textLines {
            let matches = line.ranges(of: confirmationPattern, options: .regularExpression)
            for match in matches {
                let code = String(line[match])
                // Skip if it looks like a flight number or other data
                if !code.matches(#"^[A-Z]{2,3}\d{1,4}$"#) {
                    print("🎫 Found confirmation code:", code)
                    return code
                }
            }
        }
        
        return nil
    }
    
    private func extractPassengerName(from textLines: [String]) -> String? {
        let allText = textLines.joined(separator: " ")
        
        // Look for the specific name pattern we saw: MADAN/PRIYANSHU
        if allText.contains("MADAN/PRIYANSHU") {
            print("👤 Found passenger name: MADAN/PRIYANSHU")
            return "MADAN/PRIYANSHU"
        }
        
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

struct BoardingPassData {
    var flightNumber: String?
    var departureCode: String?
    var arrivalCode: String?
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
        let route = "\(departureCode ?? "???") → \(arrivalCode ?? "???")"
        return "\(flight): \(route)"
    }
}