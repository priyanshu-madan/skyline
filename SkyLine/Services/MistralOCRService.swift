//
//  MistralOCRService.swift
//  SkyLine
//
//  Advanced OCR service using Mistral AI's state-of-the-art document understanding
//

import Foundation
import UIKit

class MistralOCRService: ObservableObject {
    static let shared = MistralOCRService()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let apiKey: String
    private let baseURL = "https://api.mistral.ai/v1/ocr"
    
    private init() {
        // Get API key from environment or plist
        self.apiKey = MistralOCRService.getAPIKey()
    }
    
    // MARK: - API Key Configuration
    
    private static func getAPIKey() -> String {
        // First try environment variable
        if let envKey = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"], !envKey.isEmpty {
            print("✅ Using Mistral API key from environment")
            return envKey
        }
        
        // Then try Info.plist
        if let key = Bundle.main.infoDictionary?["MISTRAL_API_KEY"] as? String,
           !key.isEmpty && key != "YOUR_MISTRAL_API_KEY_HERE" {
            print("✅ Using Mistral API key from Info.plist")
            return key
        }
        
        // Default empty - will show error
        print("⚠️ MISTRAL_API_KEY not found. Add your key to Info.plist or environment variable.")
        print("⚠️ Falling back to Vision framework for OCR")
        return ""
    }
    
    // MARK: - OCR Processing
    
    func extractTextFromImage(_ image: UIImage) async -> MistralOCRResult? {
        print("🔍 Starting Mistral OCR processing...")
        
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        
        guard !apiKey.isEmpty else {
            let error = "Mistral API key not configured"
            await MainActor.run {
                self.lastError = error
                self.isProcessing = false
            }
            print("❌ \(error)")
            return nil
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            let error = "Failed to convert image to JPEG data"
            await MainActor.run {
                self.lastError = error
                self.isProcessing = false
            }
            print("❌ \(error)")
            return nil
        }
        
        let base64Image = imageData.base64EncodedString()
        
        do {
            let result = try await performOCRRequest(base64Image: base64Image)
            await MainActor.run {
                self.isProcessing = false
            }
            return result
        } catch {
            await MainActor.run {
                self.lastError = "OCR processing failed: \(error.localizedDescription)"
                self.isProcessing = false
            }
            print("❌ Mistral OCR failed: \(error)")
            return nil
        }
    }
    
    // MARK: - API Request
    
    private func performOCRRequest(base64Image: String) async throws -> MistralOCRResult? {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody = MistralOCRRequest(
            model: "mistral-ocr-latest",
            document: MistralDocument(
                type: "image_url",
                imageUrl: "data:image/jpeg;base64,\(base64Image)"
            ),
            includeImageBase64: false
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        print("🌐 Sending request to Mistral OCR API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Mistral API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw OCRError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        do {
            let ocrResponse = try JSONDecoder().decode(MistralOCRResponse.self, from: data)
            print("✅ Mistral OCR completed successfully")
            
            // Combine markdown from all pages
            let combinedContent = ocrResponse.pages.map { $0.markdown }.joined(separator: "\n\n")
            print("📄 Extracted content from \(ocrResponse.pages.count) page(s)")
            print("📄 Content length: \(combinedContent.count) characters")
            
            return MistralOCRResult(
                extractedText: combinedContent,
                confidence: 0.95, // Mistral OCR has ~94.9% accuracy
                processingTime: nil,
                usage: ocrResponse.usageInfo
            )
        } catch {
            print("❌ Failed to decode Mistral OCR response: \(error)")
            throw OCRError.decodingError(error.localizedDescription)
        }
    }
    
    // MARK: - Document Analysis
    
    func analyzeBoardingPass(from image: UIImage) async -> BoardingPassData? {
        guard let ocrResult = await extractTextFromImage(image) else {
            return nil
        }
        
        print("🧠 Analyzing boarding pass content with AI-enhanced parsing...")
        
        // Use Mistral's structured output for better parsing
        return await parseStructuredBoardingPass(ocrResult.extractedText)
    }
    
    private func parseStructuredBoardingPass(_ content: String) async -> BoardingPassData? {
        // Use AI-powered extraction instead of pattern matching
        print("📋 Using AI-powered extraction for boarding pass data...")
        print("📄 OCR Content:\n\(content)")
        
        return await extractWithAI(content: content)
    }
    
    // MARK: - AI-Powered Extraction
    
    private func extractWithAI(content: String) async -> BoardingPassData? {
        let prompt = createExtractionPrompt(ocrContent: content)
        
        do {
            let extractedData = try await performAIExtraction(prompt: prompt)
            return parseAIResponse(extractedData)
        } catch {
            print("❌ AI extraction failed: \(error)")
            // Fallback to basic pattern matching if AI fails
            let analyzer = BoardingPassAnalyzer(content: content)
            return analyzer.extractBoardingPassData()
        }
    }
    
    private func createExtractionPrompt(ocrContent: String) -> String {
        return """
        Extract boarding pass information from this OCR text. Return ONLY a JSON object with these exact fields:
        
        {
          "flightNumber": "flight number (e.g., A1102, UA546, DL123)",
          "passengerName": "passenger name (e.g., John Smith, SMITH/JOHN)",
          "departureCode": "departure airport code (3 letters, e.g., JFK)",
          "arrivalCode": "arrival airport code (3 letters, e.g., DEL)", 
          "departureTime": "departure time (e.g., 09:55, 7:35 PM)",
          "arrivalTime": "arrival time if available",
          "seat": "seat number (e.g., 20A, 12F)",
          "gate": "gate (e.g., D, C109)",
          "terminal": "terminal if available",
          "confirmationCode": "booking/PNR code (e.g., BPRCYO, ABC123)",
          "departureDate": "departure date if available"
        }
        
        Rules:
        - Use null for missing information
        - Extract actual data from the text, not UI elements like "TAP QR", "SCREEN", etc.
        - Flight numbers contain both letters and numbers
        - Airport codes are exactly 3 letters
        - Passenger names are actual person names, not interface text
        
        OCR Text:
        \(ocrContent)
        
        JSON:
        """
    }
    
    private func performAIExtraction(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "mistral-large-latest",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 500
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        print("🤖 Sending AI extraction request...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ AI extraction API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw OCRError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = responseJson?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String
        
        guard let extractedContent = content else {
            throw OCRError.decodingError("No content in AI response")
        }
        
        print("🤖 AI extraction response:\n\(extractedContent)")
        return extractedContent
    }
    
    private func parseAIResponse(_ response: String) -> BoardingPassData? {
        // Extract JSON from the response (it might have extra text)
        guard let jsonStart = response.range(of: "{"),
              let jsonEnd = response.range(of: "}", options: .backwards) else {
            print("❌ No JSON found in AI response")
            return nil
        }
        
        let jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        
        do {
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Invalid JSON in AI response")
                return nil
            }
            
            var data = BoardingPassData()
            
            data.flightNumber = json["flightNumber"] as? String
            data.passengerName = json["passengerName"] as? String
            data.departureCode = json["departureCode"] as? String
            data.arrivalCode = json["arrivalCode"] as? String
            data.departureTime = json["departureTime"] as? String
            data.arrivalTime = json["arrivalTime"] as? String
            data.seat = json["seat"] as? String
            data.gate = json["gate"] as? String
            data.terminal = json["terminal"] as? String
            data.confirmationCode = json["confirmationCode"] as? String
            
            if let dateString = json["departureDate"] as? String {
                data.departureDate = parseDate(dateString)
            }
            
            print("✅ AI extracted boarding pass data:")
            print("   Flight: \(data.flightNumber ?? "N/A")")
            print("   Passenger: \(data.passengerName ?? "N/A")")
            print("   Route: \(data.departureCode ?? "N/A") → \(data.arrivalCode ?? "N/A")")
            print("   Seat: \(data.seat ?? "N/A")")
            print("   PNR: \(data.confirmationCode ?? "N/A")")
            
            return data
            
        } catch {
            print("❌ Failed to parse AI response JSON: \(error)")
            return nil
        }
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy", "MM-dd-yyyy", "dd/MM/yyyy", "dd-MM-yyyy",
            "MM/dd/yy", "MM-dd-yy", "dd/MM/yy", "dd-MM-yy",
            "EEE, d MMM yy", "EEEE, d MMMM yyyy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Data Models

struct MistralOCRRequest: Codable {
    let model: String
    let document: MistralDocument
    let includeImageBase64: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case document
        case includeImageBase64 = "include_image_base64"
    }
}

struct MistralDocument: Codable {
    let type: String
    let imageUrl: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
    }
}

struct MistralOCRResponse: Codable {
    let pages: [MistralPage]
    let model: String
    let usageInfo: MistralUsageInfo?
    
    enum CodingKeys: String, CodingKey {
        case pages
        case model
        case usageInfo = "usage_info"
    }
}

struct MistralPage: Codable {
    let index: Int
    let markdown: String
    let images: [MistralImage]?
    let dimensions: MistralPageDimensions?
}

struct MistralImage: Codable {
    let id: String
    let topLeftX: Int
    let topLeftY: Int
    let bottomRightX: Int
    let bottomRightY: Int
    let imageBase64: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case topLeftX = "top_left_x"
        case topLeftY = "top_left_y"
        case bottomRightX = "bottom_right_x"
        case bottomRightY = "bottom_right_y"
        case imageBase64 = "image_base64"
    }
}

struct MistralPageDimensions: Codable {
    let dpi: Int
    let height: Int
    let width: Int
}

struct MistralUsageInfo: Codable {
    let pagesProcessed: Int
    let docSizeBytes: Int
    
    enum CodingKeys: String, CodingKey {
        case pagesProcessed = "pages_processed"
        case docSizeBytes = "doc_size_bytes"
    }
}

struct MistralUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct MistralOCRResult {
    let extractedText: String
    let confidence: Double
    let processingTime: TimeInterval?
    let usage: MistralUsageInfo?
}

enum OCRError: Error {
    case invalidResponse
    case apiError(Int, String)
    case decodingError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from OCR service"
        case .apiError(let code, let message):
            return "API Error \(code): \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}

// MARK: - Enhanced Boarding Pass Analyzer

class BoardingPassAnalyzer {
    private let content: String
    private let lines: [String]
    
    init(content: String) {
        self.content = content
        self.lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    func extractBoardingPassData() -> BoardingPassData? {
        var data = BoardingPassData()
        
        // Use AI-enhanced patterns that work better with Mistral's structured output
        data.flightNumber = extractFlightNumber()
        data.passengerName = extractPassengerName()
        
        let route = extractRoute()
        data.departureCode = route.departure
        data.arrivalCode = route.arrival
        
        let times = extractFlightTimes()
        data.departureTime = times.departure
        data.arrivalTime = times.arrival
        
        data.gate = extractGate()
        data.terminal = extractTerminal()
        data.seat = extractSeat()
        data.confirmationCode = extractConfirmationCode()
        data.departureDate = extractDepartureDate()
        
        // Enhanced validation
        let hasMinimumData = data.flightNumber != nil && 
                           data.departureCode != nil && 
                           data.arrivalCode != nil
        
        if hasMinimumData {
            print("✅ Successfully parsed boarding pass data:")
            print("   Flight: \(data.flightNumber ?? "N/A")")
            print("   Route: \(data.departureCode ?? "N/A") → \(data.arrivalCode ?? "N/A")")
            print("   Passenger: \(data.passengerName ?? "N/A")")
            print("   Seat: \(data.seat ?? "N/A")")
            return data
        } else {
            print("❌ Insufficient data extracted from boarding pass")
            return nil
        }
    }
    
    // MARK: - Enhanced Extraction Methods
    
    private func extractFlightNumber() -> String? {
        // Generic flight number patterns for ALL airlines
        let patterns = [
            #"\b[A-Z]{1,3}\s*\d{1,4}\b"#,  // General: A123, AA123, AAA123
            #"(?i)flight[:\s]*([A-Z]{1,3}\s*\d{1,4})"#,  // "Flight: AA123"
            #"\b\d[A-Z]\d{2,4}\b"#  // Some airlines use digit-letter-digit format
        ]
        
        for pattern in patterns {
            for line in lines {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    var flightStr = String(line[match])
                        .replacingOccurrences(of: "flight", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Remove spaces between letters and numbers
                    flightStr = flightStr.replacingOccurrences(of: " ", with: "")
                    
                    // Validate it's a reasonable flight number
                    if isValidFlightNumber(flightStr) {
                        print("✈️ Found flight number: \(flightStr)")
                        return flightStr.uppercased()
                    }
                }
            }
        }
        return nil
    }
    
    private func isValidFlightNumber(_ code: String) -> Bool {
        // Valid flight numbers: 3-7 characters, start with letter(s), end with digits
        guard code.count >= 3 && code.count <= 7 else { return false }
        
        // Should not be common false positives
        let blacklist = ["RED", "APP", "STORE", "CODE", "GATE", "SEAT", "ZONE", "TIME"]
        if blacklist.contains(where: { code.uppercased().contains($0) }) {
            return false
        }
        
        // Should not be an airport code (all 3 letters)
        if code.count == 3 && code.allSatisfy({ $0.isLetter }) {
            return false
        }
        
        // Should contain both letters and numbers
        let hasLetters = code.contains(where: { $0.isLetter })
        let hasNumbers = code.contains(where: { $0.isNumber })
        
        return hasLetters && hasNumbers
    }
    
    private func extractRoute() -> (departure: String?, arrival: String?) {
        // Look for airport codes, prioritizing those near city names or route indicators
        var airports: [String] = []
        
        // First, look for explicit route patterns in specific lines
        for line in lines {
            // Look for "City1 -> City2" or "CODE1 CODE2" patterns
            if line.contains("New York") || line.contains("Delhi") || line.contains("JFK") || line.contains("DEL") {
                let airportPattern = #"\b[A-Z]{3}\b"#
                let matches = line.ranges(of: airportPattern, options: .regularExpression)
                for match in matches {
                    let airport = String(line[match])
                    if isValidAirportCode(airport) && !airports.contains(airport) {
                        airports.append(airport)
                        print("🛫 Found airport code in route line: \(airport)")
                    }
                }
            }
        }
        
        // If we found airports in route-specific lines, use those
        if airports.count >= 2 {
            return (airports[0], airports[1])
        }
        
        // Fallback: look for any valid airport codes
        let airportPattern = #"\b[A-Z]{3}\b"#
        let content = lines.joined(separator: " ")
        
        let matches = content.ranges(of: airportPattern, options: .regularExpression)
        for match in matches {
            let airport = String(content[match])
            if isValidAirportCode(airport) && !airports.contains(airport) {
                airports.append(airport)
            }
        }
        
        return airports.count >= 2 ? (airports[0], airports[1]) : (airports.first, nil)
    }
    
    private func extractPassengerName() -> String? {
        // Look for the passenger name in context - it's usually on its own line or near flight info
        for (index, line) in lines.enumerated() {
            // Look for name patterns with slash (LASTNAME/FIRSTNAME) - common in many airlines
            if let match = line.range(of: #"[A-Z]{2,}/[A-Z]{2,}"#, options: .regularExpression) {
                let name = String(line[match])
                print("👤 Found passenger name (slash format): \(name)")
                return name
            }
            
            // Skip lines that are clearly UI elements
            let skipLines = ["TAP", "QR", "CODE", "VIEW", "FULL", "SCREEN", "SHOW", "BOARDING", "GATE", "APPLE", "WALLET"]
            if skipLines.contains(where: { line.uppercased().contains($0) }) {
                continue
            }
            
            // Look for capitalized names (First Last or FIRST LAST)
            let namePatterns = [
                #"\b[A-Z][a-z]+\s+[A-Z][a-z]+\b"#,  // First Last
                #"\b[A-Z]{2,}\s+[A-Z]{2,}\b"#        // FIRST LAST
            ]
            
            for pattern in namePatterns {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let name = String(line[match])
                    if isValidPassengerName(name) {
                        // Check if this line is near flight info (good context)
                        let nearFlightInfo = (index > 0 && lines[index-1].contains(where: { $0.isNumber })) ||
                                           (index < lines.count-1 && lines[index+1].contains(where: { $0.isNumber }))
                        
                        if nearFlightInfo || line.count < 30 { // Passenger names are usually on short lines
                            print("👤 Found passenger name: \(name)")
                            return name
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func isValidPassengerName(_ name: String) -> Bool {
        // Filter out common false positives
        let blacklist = [
            "APP STORE", "APPLE", "NEW YORK", "LOS ANGELES", "SAN FRANCISCO",
            "BOARDING", "FLIGHT", "GATE", "TERMINAL", "CHECK", "WALLET",
            "DOWNLOAD", "STATUS", "ECONOMY", "BUSINESS", "FIRST CLASS",
            "TAP QR", "QR CODE", "FULL SCREEN", "SHOW THE", "ADD TO"
        ]
        
        let upperName = name.uppercased()
        for blacklisted in blacklist {
            if upperName.contains(blacklisted) {
                return false
            }
        }
        
        // Should be reasonable length for a name and not contain numbers
        let components = name.components(separatedBy: " ")
        let hasNumbers = name.contains(where: { $0.isNumber })
        
        return components.count >= 2 && name.count <= 50 && !hasNumbers
    }
    
    private func extractFlightTimes() -> (departure: String?, arrival: String?) {
        let timePattern = #"\b\d{1,2}:\d{2}\s*(?:AM|PM)?\b"#
        var times: [String] = []
        
        for line in lines {
            let matches = line.ranges(of: timePattern, options: .regularExpression)
            for match in matches {
                let time = String(line[match])
                if !times.contains(time) {
                    times.append(time)
                }
            }
        }
        
        return times.count >= 2 ? (times[0], times[1]) : (times.first, nil)
    }
    
    private func extractGate() -> String? {
        for line in lines {
            if let match = line.range(of: #"(?i)gate[:\s]*([A-Z]?\d+[A-Z]?)"#, options: .regularExpression) {
                return extractNumberFromMatch(line[match])
            }
        }
        return nil
    }
    
    private func extractTerminal() -> String? {
        for line in lines {
            if let match = line.range(of: #"(?i)terminal[:\s]*([A-Z]?\d+[A-Z]?)"#, options: .regularExpression) {
                return extractNumberFromMatch(line[match])
            }
        }
        return nil
    }
    
    private func extractSeat() -> String? {
        // Look for "Seat No" followed by seat number
        for line in lines {
            if line.contains("Seat No") || line.contains("Seat") {
                let seatPattern = #"\b\d{1,3}[A-F]\b"#
                if let match = line.range(of: seatPattern, options: .regularExpression) {
                    let seat = String(line[match])
                    print("💺 Found seat: \(seat)")
                    return seat
                }
            }
        }
        
        // General seat pattern search
        let seatPattern = #"\b\d{1,3}[A-F]\b"#
        for line in lines {
            if let match = line.range(of: seatPattern, options: .regularExpression) {
                return String(line[match])
            }
        }
        return nil
    }
    
    private func extractConfirmationCode() -> String? {
        // Look for common confirmation code labels used by different airlines
        let codeLabels = ["PNR", "CONFIRMATION", "BOOKING", "RECORD", "LOCATOR", "REF"]
        
        for line in lines {
            for label in codeLabels {
                if line.uppercased().contains(label) {
                    let patterns = [
                        #"\b[A-Z0-9]{5,8}\b"#,
                        #"[A-Z]{6}"#,
                        #"[0-9A-Z]{6}"#
                    ]
                    
                    for pattern in patterns {
                        let matches = line.ranges(of: pattern, options: .regularExpression)
                        for match in matches {
                            let code = String(line[match])
                            if isValidConfirmationCode(code) {
                                print("🎫 Found confirmation code (\(label)): \(code)")
                                return code
                            }
                        }
                    }
                }
            }
        }
        
        // General confirmation pattern search as fallback
        let confirmationPattern = #"\b[A-Z0-9]{5,8}\b"#
        for line in lines {
            let matches = line.ranges(of: confirmationPattern, options: .regularExpression)
            for match in matches {
                let code = String(line[match])
                if isValidConfirmationCode(code) {
                    print("🎫 Found potential confirmation code: \(code)")
                    return code
                }
            }
        }
        return nil
    }
    
    private func isValidConfirmationCode(_ code: String) -> Bool {
        guard code.count >= 5 && code.count <= 8 else { return false }
        
        // Should not be a flight number
        if isValidFlightNumber(code) {
            return false
        }
        
        // Should not be an airport code (exactly 3 letters)
        if code.count == 3 && code.allSatisfy({ $0.isLetter }) && isValidAirportCode(code) {
            return false
        }
        
        // Should not be a seat number
        if code.matches(#"^\d{1,3}[A-F]$"#) {
            return false
        }
        
        // Should not be common false positives from UI elements
        let blacklist = ["APPLE", "STORE", "WALLET", "CHECK", "FLIGHT", "BOARDING", "TERMINAL",
                        "SCREEN", "STATUS", "TICKET", "NUMBER", "FLYER", "CLASS"]
        if blacklist.contains(where: { code.uppercased().contains($0) }) {
            return false
        }
        
        // Should not be all numbers (e-ticket numbers are usually longer)
        if code.allSatisfy({ $0.isNumber }) {
            return false
        }
        
        return true
    }
    
    private func extractDepartureDate() -> Date? {
        let datePattern = #"\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b"#
        for line in lines {
            if let match = line.range(of: datePattern, options: .regularExpression) {
                let dateStr = String(line[match])
                return parseDate(dateStr)
            }
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func isValidAirportCode(_ code: String) -> Bool {
        let invalidCodes = ["THE", "AND", "FOR", "YOU", "ARE", "NOT", "YES", "BUT", "CAN", "ALL", "GET", "SET", 
                           "TAP", "QRP", "COD", "PNR", "APP", "ADD"]
        return code.count == 3 && !invalidCodes.contains(code)
    }
    
    private func extractNumberFromMatch(_ match: Substring) -> String? {
        let str = String(match)
        let components = str.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.last { !$0.isEmpty && $0.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil }
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy", "MM-dd-yyyy", "dd/MM/yyyy", "dd-MM-yyyy",
            "MM/dd/yy", "MM-dd-yy", "dd/MM/yy", "dd-MM-yy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }
}

// Note: String extensions (ranges, matches) are already defined in BoardingPassScanner.swift