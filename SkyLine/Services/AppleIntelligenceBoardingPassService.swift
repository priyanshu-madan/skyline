//
//  AppleIntelligenceBoardingPassService.swift
//  SkyLine
//
//  Apple Intelligence-powered boarding pass extraction using Foundation Models framework
//

import Foundation
import UIKit
import Vision

// Import Foundation Models if available
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Boarding Pass Information Structure

// Use @Generable if Foundation Models is available, otherwise regular struct
#if canImport(FoundationModels)
@Generable
#endif
struct IntelligentBoardingPassData {
    let flightNumber: String?
    let airline: String?
    let passengerName: String?
    let departureAirport: String?
    let departureCity: String?
    let departureCode: String?
    let arrivalAirport: String?
    let arrivalCity: String?
    let arrivalCode: String?
    let departureDate: String?
    let departureTime: String?
    let arrivalTime: String?
    let seat: String?
    let gate: String?
    let terminal: String?
    let confirmationCode: String?
    let boardingTime: String?
}

// MARK: - Apple Intelligence Boarding Pass Service

@available(iOS 18.0, *)
class AppleIntelligenceBoardingPassService: ObservableObject {
    static let shared = AppleIntelligenceBoardingPassService()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let visionFallback = BoardingPassScanner.shared
    
    private init() {}
    
    // MARK: - Main Analysis Method
    
    func analyzeBoardingPass(from image: UIImage) async -> BoardingPassData? {
        print("🧠 Starting Apple Intelligence boarding pass analysis...")
        
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        
        // Step 1: Extract text using Vision framework
        guard let extractedText = await extractTextFromImage(image) else {
            await MainActor.run {
                isProcessing = false
                lastError = "Failed to extract text from image"
            }
            return nil
        }
        
        // Step 2: Use Apple Intelligence to understand the boarding pass
        guard let intelligentData = await analyzeWithAppleIntelligence(extractedText) else {
            // Fallback to existing scanner if Apple Intelligence fails
            print("🔄 Apple Intelligence failed, falling back to Vision + pattern matching...")
            await MainActor.run { isProcessing = false }
            return await visionFallback.scanBoardingPass(from: image)
        }
        
        // Step 3: Convert to legacy format
        let boardingPassData = await convertToLegacyFormat(intelligentData)
        
        await MainActor.run {
            isProcessing = false
        }
        
        print("✅ Apple Intelligence boarding pass analysis completed successfully")
        return boardingPassData
    }
    
    // MARK: - Vision Text Extraction
    
    private func extractTextFromImage(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("❌ Vision text extraction error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let extractedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                print("👁️ Vision extracted text length: \(extractedText.count) characters")
                continuation.resume(returning: extractedText.isEmpty ? nil : extractedText)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Vision processing error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Apple Intelligence Analysis
    
    private func analyzeWithAppleIntelligence(_ text: String) async -> IntelligentBoardingPassData? {
        #if canImport(FoundationModels)
        do {
            print("🧠 Analyzing boarding pass with Apple Intelligence...")
            
            // Check if Foundation Models are available
            guard SystemLanguageModel.default.isAvailable else {
                print("⚠️ Foundation Models not available")
                return nil
            }
            
            // Create analysis prompt
            let analysisPrompt = createContextualPrompt(text: text, entities: [])
            
            // Create language model session
            let model = SystemLanguageModel.default
            let session = LanguageModelSession(model: model)
            
            // For now, use basic text response and parse manually
            // TODO: Implement proper guided generation when API is stable
            let response = try await session.respond(to: analysisPrompt)
            let textResponse = response.content
            
            print("🧠 Apple Intelligence response: \(textResponse)")
            
            // Parse the AI response into structured data
            let parsedData = parseAIResponse(textResponse)
            
            if let data = parsedData {
                // Enhance with dynamic airline mapping
                let enhancedData = await enhanceWithAirlineMapping(data)
                
                print("✅ Apple Intelligence extracted boarding pass data:")
                print("   Flight: \(enhancedData.flightNumber ?? "N/A")")
                print("   Airline: \(enhancedData.airline ?? "N/A")")
                print("   Passenger: \(enhancedData.passengerName ?? "N/A")")
                print("   Route: \(enhancedData.departureCode ?? "N/A") → \(enhancedData.arrivalCode ?? "N/A")")
                print("   Cities: \(enhancedData.departureCity ?? "N/A") → \(enhancedData.arrivalCity ?? "N/A")")
                print("   Seat: \(enhancedData.seat ?? "N/A")")
                print("   Gate: \(enhancedData.gate ?? "N/A")")
                
                return enhancedData
            }
            
            return parsedData
            
        } catch {
            print("❌ Apple Intelligence analysis failed: \(error)")
            await MainActor.run {
                lastError = "Apple Intelligence analysis failed: \(error.localizedDescription)"
            }
            return nil
        }
        #else
        print("⚠️ Foundation Models framework not available - falling back to Vision + patterns")
        return nil
        #endif
    }
    
    // MARK: - Response Parsing
    
    private func parseAIResponse(_ response: String) -> IntelligentBoardingPassData? {
        print("🧠 Parsing AI response...")
        
        // Create structured response using AI's understanding
        var flightNumber: String?
        var airline: String?
        var passengerName: String?
        var departureCode: String?
        var departureCity: String?
        var arrivalCode: String?
        var arrivalCity: String?
        var seat: String?
        var gate: String?
        var confirmationCode: String?
        var departureTime: String?
        var departureDate: String?
        var arrivalTime: String?
        
        // Parse key-value pairs from AI response
        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            if cleanLine.contains("flight") && cleanLine.contains(":") {
                flightNumber = extractValue(from: line)
            } else if cleanLine.contains("airline") && cleanLine.contains(":") {
                airline = extractValue(from: line)
            } else if cleanLine.contains("passenger") && cleanLine.contains(":") {
                passengerName = extractValue(from: line)
            } else if cleanLine.contains("departure code") && cleanLine.contains(":") {
                departureCode = extractValue(from: line)
            } else if cleanLine.contains("departure city") && cleanLine.contains(":") {
                departureCity = extractValue(from: line)
            } else if cleanLine.contains("arrival code") && cleanLine.contains(":") {
                arrivalCode = extractValue(from: line)
            } else if cleanLine.contains("arrival city") && cleanLine.contains(":") {
                arrivalCity = extractValue(from: line)
            } else if cleanLine.contains("seat") && cleanLine.contains(":") {
                seat = extractValue(from: line)
            } else if cleanLine.contains("gate") && cleanLine.contains(":") {
                gate = extractValue(from: line)
            } else if (cleanLine.contains("confirmation") || cleanLine.contains("pnr")) && cleanLine.contains(":") {
                confirmationCode = extractValue(from: line)
            } else if cleanLine.contains("departure time") && cleanLine.contains(":") {
                departureTime = extractValue(from: line)
            } else if cleanLine.contains("departure date") && cleanLine.contains(":") {
                departureDate = extractValue(from: line)
            } else if cleanLine.contains("arrival time") && cleanLine.contains(":") {
                arrivalTime = extractValue(from: line)
            }
        }
        
        // Create and return structured data
        // Post-process airport codes to fix any city names that slipped through
        let correctedDepartureCode = correctAirportCode(departureCode, cityName: departureCity)
        let correctedArrivalCode = correctAirportCode(arrivalCode, cityName: arrivalCity)
        
        if correctedDepartureCode != departureCode {
            print("🔧 Corrected departure code: \(departureCode ?? "nil") → \(correctedDepartureCode ?? "nil")")
        }
        if correctedArrivalCode != arrivalCode {
            print("🔧 Corrected arrival code: \(arrivalCode ?? "nil") → \(correctedArrivalCode ?? "nil")")
        }
        
        return IntelligentBoardingPassData(
            flightNumber: flightNumber,
            airline: airline,
            passengerName: passengerName,
            departureAirport: nil,
            departureCity: departureCity,
            departureCode: correctedDepartureCode,
            arrivalAirport: nil,
            arrivalCity: arrivalCity,
            arrivalCode: correctedArrivalCode,
            departureDate: departureDate,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            seat: seat,
            gate: gate,
            terminal: nil,
            confirmationCode: confirmationCode,
            boardingTime: nil
        )
    }
    
    private func extractValue(from line: String) -> String? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let rawValue = String(line[line.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clean up markdown formatting and other artifacts
        let cleanedValue = rawValue
            .replacingOccurrences(of: "**", with: "") // Remove markdown bold
            .replacingOccurrences(of: "*", with: "")  // Remove markdown emphasis
            .replacingOccurrences(of: "_", with: "")  // Remove markdown underline
            .replacingOccurrences(of: "`", with: "")  // Remove markdown code
            .replacingOccurrences(of: "null", with: "") // Remove literal "null"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
    
    private func correctAirportCode(_ code: String?, cityName: String?) -> String? {
        // If we already have a valid 3-letter code, return it
        if let code = code, code.count == 3, !code.uppercased().contains("NULL") {
            return code.uppercased()
        }
        
        // If no code but we have a city name, try to map it to IATA code
        guard let cityName = cityName else { return code }
        
        let cityToIATA: [String: String] = [
            "DUBAI": "DXB",
            "SEOUL": "ICN", // Default to Incheon for Seoul
            "MUMBAI": "BOM",
            "DELHI": "DEL",
            "HYDERABAD": "HYD",
            "CHANDIGARH": "IXC",
            "BANGALORE": "BLR",
            "CHENNAI": "MAA",
            "KOLKATA": "CCU",
            "PUNE": "PNQ",
            "AHMEDABAD": "AMD",
            "COCHIN": "COK",
            "KOCHI": "COK",
            "TRIVANDRUM": "TRV",
            "THIRUVANANTHAPURAM": "TRV",
            "GOA": "GOI",
            "JAIPUR": "JAI",
            "LUCKNOW": "LKO",
            "BHUBANESWAR": "BBI",
            "INDORE": "IDR",
            "NAGPUR": "NAG",
            "COIMBATORE": "CJB",
            "MADURAI": "IXM",
            "VIJAYAWADA": "VGA",
            "VISAKHAPATNAM": "VTZ",
            "TIRUPATI": "TIR",
            "RAIPUR": "RPR",
            "BHOPAL": "BHO",
            // International cities
            "LONDON": "LHR", // Default to Heathrow
            "NEW YORK": "JFK", // Default to JFK
            "CHICAGO": "ORD", // Default to O'Hare
            "LOS ANGELES": "LAX",
            "SAN FRANCISCO": "SFO",
            "PARIS": "CDG", // Default to Charles de Gaulle
            "FRANKFURT": "FRA",
            "AMSTERDAM": "AMS",
            "SINGAPORE": "SIN",
            "HONG KONG": "HKG",
            "TOKYO": "NRT", // Default to Narita
            "SYDNEY": "SYD",
            "MELBOURNE": "MEL"
        ]
        
        let uppercasedCity = cityName.uppercased()
        if let iataCode = cityToIATA[uppercasedCity] {
            print("🗺️ Mapped city '\(cityName)' to IATA code: \(iataCode)")
            return iataCode
        }
        
        // Try partial matches for common variations
        for (city, iata) in cityToIATA {
            if uppercasedCity.contains(city) || city.contains(uppercasedCity) {
                print("🗺️ Partial match: city '\(cityName)' matched '\(city)' → \(iata)")
                return iata
            }
        }
        
        // Return the original code if we can't map the city
        return code
    }
    
    private func createContextualPrompt(text: String, entities: [String]) -> String {
        return """
        You are an expert at extracting structured information from boarding pass documents. 
        Analyze the following boarding pass text and extract flight information.
        
        Text from boarding pass:
        \(text)
        
        Please extract the following information and format your response exactly as shown below.
        
        IMPORTANT: Use plain text only - no markdown formatting, no bold (**), no asterisks (*), no underscores (_).
        
        Flight Number: [extract flight number like 6E6252, UA546, AI123, KE952, or null if not found]
        Airline: [extract airline name like IndiGo, United Airlines, Air India, Korean Air, or null if not found]
        Passenger Name: [extract full passenger name, often in format LASTNAME/FIRSTNAME, or null if not found]
        Departure Code: [extract ONLY the 3-letter IATA departure airport code - FROM where the flight ORIGINATES. Look for "FROM", origin city, or first airport mentioned. Convert city names to codes: Dubai→DXB, Seoul→ICN, etc. If unclear, use null]
        Departure City: [extract the departure city name - FROM where the flight ORIGINATES like Dubai, Seoul, Hyderabad, Delhi, or null if not found]
        Arrival Code: [extract ONLY the 3-letter IATA arrival airport code - TO where the flight is GOING. Look for "TO", destination city, or second airport mentioned. Convert city names to codes: Dubai→DXB, Seoul→ICN, etc. If unclear, use null]
        Arrival City: [extract the arrival city name - TO where the flight is GOING like Dubai, Seoul, Chandigarh, Mumbai, or null if not found]
        Departure Time: [extract departure time in any format found like 21:30, 7:35 PM, 19:45, or null if not found]
        Departure Date: [extract departure date in any format found like 30JUN24, June 30 2024, 2024-06-30, or null if not found]
        Arrival Time: [extract arrival time in any format found - look for arrival, landing, or destination times. May be calculated from departure + flight duration, or null if not found]
        Seat: [extract seat number like 24D, 12A, or null if not found]
        Gate: [extract gate number like 14, C109, B23, or null if not found]
        Confirmation Code: [extract PNR/confirmation code, usually 6 alphanumeric characters, or null if not found]
        
        CRITICAL: Airport codes MUST be exactly 3 letters (IATA format). Common conversions:
        - Dubai/DUBAI → DXB
        - Seoul/SEOUL → ICN (Incheon) or GMP (Gimpo)
        - Mumbai/MUMBAI → BOM
        - Delhi/DELHI → DEL
        - Hyderabad → HYD
        - Chandigarh → IXC
        
        ROUTE EXTRACTION RULES:
        - Look for route patterns like "DUBAI TO SEOUL", "DXB-ICN", "FROM DUBAI TO SEOUL"
        - Flight KE952 is Korean Air - if you see this flight, departure is likely from Dubai (DXB) to Seoul (ICN)
        - If you see both Dubai/DXB and Seoul/ICN mentioned, determine which is origin vs destination
        - Korean Air flights often originate from Seoul, but international flights may start elsewhere
        - Look for boarding gate locations to help determine departure airport
        
        Be precise and only extract information that is clearly identifiable in the text. 
        Use "null" for any field not found.
        Use plain text values only - no formatting.
        """
    }
    
    // MARK: - Airline Dynamic Lookup
    
    private func enhanceWithAirlineMapping(_ data: IntelligentBoardingPassData) async -> IntelligentBoardingPassData {
        var enhancedData = data
        
        // Check if we should trust the extracted airline or use flight number lookup
        let shouldTrustExtractedAirline = isValidAirlineName(enhancedData.airline)
        
        if shouldTrustExtractedAirline {
            print("✈️ Using Apple Intelligence extracted airline: '\(enhancedData.airline!)'")
            return enhancedData // Keep the AI-extracted airline
        } else if let flightNumber = enhancedData.flightNumber {
            print("✈️ Invalid/missing airline '\(enhancedData.airline ?? "nil")', determining from flight number: \(flightNumber)")
            
            // Use dynamic airline service lookup based on flight number
            let airlineName = await AirlineService.shared.getAirlineFromFlightNumber(flightNumber)
            
            enhancedData = IntelligentBoardingPassData(
                flightNumber: enhancedData.flightNumber,
                airline: airlineName ?? enhancedData.airline,
                passengerName: enhancedData.passengerName,
                departureAirport: enhancedData.departureAirport,
                departureCity: enhancedData.departureCity,
                departureCode: enhancedData.departureCode,
                arrivalAirport: enhancedData.arrivalAirport,
                arrivalCity: enhancedData.arrivalCity,
                arrivalCode: enhancedData.arrivalCode,
                departureDate: enhancedData.departureDate,
                departureTime: enhancedData.departureTime,
                arrivalTime: enhancedData.arrivalTime,
                seat: enhancedData.seat,
                gate: enhancedData.gate,
                terminal: enhancedData.terminal,
                confirmationCode: enhancedData.confirmationCode,
                boardingTime: enhancedData.boardingTime
            )
        }
        
        return enhancedData
    }
    
    // MARK: - Validation Helpers
    
    private func isValidAirlineName(_ airline: String?) -> Bool {
        guard let airline = airline, !airline.isEmpty else {
            return false
        }
        
        // Filter out common Apple Intelligence errors and invalid patterns
        let invalidPatterns = [
            "null", "NULL", "nil", "NIL",
            "XSAT", "UNKNOWN", "N/A", "TBA",
            "AIRLINE", "FLIGHT", "CODE"
        ]
        
        let upperAirline = airline.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Check for invalid patterns
        if invalidPatterns.contains(where: { upperAirline.contains($0) }) {
            return false
        }
        
        // Must be at least 3 characters and contain letters
        if upperAirline.count < 3 || !upperAirline.contains(where: { $0.isLetter }) {
            return false
        }
        
        // Looks like a valid airline name
        return true
    }
    
    // MARK: - Data Conversion
    
    private func convertToLegacyFormat(_ intelligentData: IntelligentBoardingPassData) async -> BoardingPassData {
        // First enhance the data with dynamic airline mapping
        let enhancedData = await enhanceWithAirlineMapping(intelligentData)
        
        var legacyData = BoardingPassData()
        
        legacyData.flightNumber = enhancedData.flightNumber
        legacyData.airline = enhancedData.airline
        legacyData.passengerName = enhancedData.passengerName
        legacyData.departureCode = enhancedData.departureCode
        legacyData.departureCity = enhancedData.departureCity
        legacyData.arrivalCode = enhancedData.arrivalCode
        legacyData.arrivalCity = enhancedData.arrivalCity
        legacyData.seat = enhancedData.seat
        legacyData.gate = enhancedData.gate
        legacyData.terminal = enhancedData.terminal
        legacyData.confirmationCode = enhancedData.confirmationCode
        // Validate and set times - reject invalid times like "69:46"
        legacyData.departureTime = validateTime(enhancedData.departureTime)
        legacyData.arrivalTime = validateTime(enhancedData.arrivalTime)
        
        // Parse date if available
        if let dateString = enhancedData.departureDate {
            legacyData.departureDate = parseDate(from: dateString)
        }
        
        return legacyData
    }
    
    private func validateTime(_ timeString: String?) -> String? {
        guard let timeString = timeString,
              !timeString.isEmpty,
              timeString.lowercased() != "null" else {
            return nil
        }
        
        // Check for valid time patterns and reject invalid ones like "69:46"
        let timePatterns = [
            #"^([01]?[0-9]|2[0-3]):([0-5][0-9])$"#, // 24-hour format: 00:00 to 23:59
            #"^([01]?[0-9]|2[0-3])([0-5][0-9])$"#, // 4-digit 24-hour format: 0000 to 2359
            #"^(1[0-2]|[1-9]):([0-5][0-9])\s*(AM|PM)$"#, // 12-hour format with AM/PM
            #"^(1[0-2]|[1-9]):([0-5][0-9])\s*(am|pm)$"# // 12-hour format with lowercase am/pm
        ]
        
        for pattern in timePatterns {
            if timeString.range(of: pattern, options: .regularExpression) != nil {
                print("✅ Valid time format: \(timeString)")
                // Format 4-digit times to include colon (1425 -> 14:25)
                if timeString.count == 4 && timeString.allSatisfy({ $0.isNumber }) {
                    let hours = String(timeString.prefix(2))
                    let minutes = String(timeString.suffix(2))
                    let formattedTime = "\(hours):\(minutes)"
                    print("🔧 Formatted 4-digit time: \(timeString) -> \(formattedTime)")
                    return formattedTime
                }
                return timeString
            }
        }
        
        print("❌ Invalid time format rejected: \(timeString)")
        return nil
    }
    
    private func parseDate(from dateString: String) -> Date? {
        let formatters = [
            DateFormatter.boardingPassDate,
            DateFormatter.isoDate,
            DateFormatter.shortDate
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
}

// MARK: - Date Formatter Extensions

extension DateFormatter {
    static let boardingPassDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
    
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()
}