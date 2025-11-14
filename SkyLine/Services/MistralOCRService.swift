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
        
        // Require API key since Vision is disabled
        print("❌ MISTRAL_API_KEY is required! Add your key to Info.plist or environment variable.")
        print("❌ Vision framework is disabled - Mistral OCR is the only option")
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
        
        // Preprocess image for better OCR accuracy
        let enhancedImage = preprocessImageForOCR(image)
        
        guard let imageData = enhancedImage.jpegData(compressionQuality: 0.9) else {
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
        print("🌐 Using Official Mistral OCR API...")
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "mistral-ocr-latest",
            "document": [
                "type": "image_url",
                "image_url": "data:image/jpeg;base64,\(base64Image)"
            ],
            "include_image_base64": true
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        print("🌐 Sending boarding pass to Mistral OCR API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Rate limit exceeded"
            print("⚠️ Mistral OCR rate limit hit: \(errorMessage)")
            throw OCRError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Mistral OCR API error (\(httpResponse.statusCode)): \(errorMessage)")
            print("❌ Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            throw OCRError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        do {
            let ocrResponse = try JSONDecoder().decode(MistralOCRAPIResponse.self, from: data)
            print("✅ Mistral OCR completed successfully")
            
            // Extract text content from pages (markdown field)
            let rawMarkdown = ocrResponse.pages.map { $0.markdown }.joined(separator: "\n")
            
            // Clean markdown formatting for better text parsing
            let extractedText = cleanMarkdownText(rawMarkdown)
            
            print("📄 Extracted content from \(ocrResponse.pages.count) page(s)")
            print("📄 Content length: \(extractedText.count) characters")
            print("📄 Raw markdown:\n\(rawMarkdown)")
            print("📄 Cleaned OCR Content:\n\(extractedText)")
            
            // Convert usage info to expected format
            let convertedUsage = ocrResponse.usageInfo.map { ocrUsage in
                MistralUsageInfo(
                    pagesProcessed: ocrUsage.pagesProcessed,
                    docSizeBytes: ocrUsage.docSizeBytes
                )
            }
            
            return MistralOCRResult(
                extractedText: extractedText,
                confidence: 0.95, // Mistral OCR has 94.89% overall accuracy
                processingTime: nil,
                usage: convertedUsage
            )
        } catch {
            print("❌ Failed to decode Mistral OCR response: \(error)")
            print("❌ Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            throw OCRError.decodingError(error.localizedDescription)
        }
    }
    
    // MARK: - Document Analysis
    
    func analyzeBoardingPass(from image: UIImage) async -> BoardingPassData? {
        guard let ocrResult = await extractTextFromImage(image) else {
            return nil
        }
        
        // Check if OCR result looks like gibberish
        if isOCRResultGibberish(ocrResult.extractedText) {
            print("⚠️ Mistral OCR result appears to be gibberish, returning nil for fallback")
            return nil
        }
        
        print("🧠 Analyzing boarding pass content with AI-enhanced parsing...")
        
        // Use Mistral's structured output for better parsing
        return await parseStructuredBoardingPass(ocrResult.extractedText)
    }
    
    private func isOCRResultGibberish(_ text: String) -> Bool {
        let cleanText = text.uppercased()
        
        // Check for common gibberish patterns from the failed OCR
        let gibberishPatterns = [
            "220V", "100V", "90V", "D3W", "NI-333DO", "3NIB1NOB",
            "UH2MAY199MAQAM", "QABA9HQYH", "TA2X", "233V132"
        ]
        
        let gibberishCount = gibberishPatterns.filter { cleanText.contains($0) }.count
        
        // If we find more than 2 gibberish patterns, it's likely bad OCR
        if gibberishCount > 2 {
            print("🚨 OCR gibberish detected: found \(gibberishCount) gibberish patterns")
            return true
        }
        
        // Check if the text contains very few recognizable boarding pass elements
        let boardingPassPatterns = [
            "FLIGHT", "GATE", "SEAT", "BOARDING", "DEPARTURE", "ARRIVAL",
            "PASSENGER", "TIME", "DATE", "TERMINAL", "ZONE", "CONFIRMATION"
        ]
        
        let validPatternCount = boardingPassPatterns.filter { cleanText.contains($0) }.count
        let hasFlightNumber = cleanText.range(of: #"[A-Z]{2}\d{3,4}"#, options: .regularExpression) != nil
        let hasAirportCodes = cleanText.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) != nil
        
        // If we have very few boarding pass indicators, it's likely bad OCR
        if validPatternCount == 0 && !hasFlightNumber && !hasAirportCodes {
            print("🚨 OCR quality check failed: no recognizable boarding pass elements found")
            return true
        }
        
        return false
    }
    
    private func parseStructuredBoardingPass(_ content: String) async -> BoardingPassData? {
        // Use AI-powered extraction instead of pattern matching
        print("📋 Using AI-powered extraction for boarding pass data...")
        print("📄 OCR Content:\n\(content)")
        
        return await extractWithAI(content: content)
    }
    
    // MARK: - AI-Powered Extraction
    
    private func extractWithAI(content: String) async -> BoardingPassData? {
        print("🤖 Starting enhanced AI extraction with multiple strategies...")
        
        // Strategy 1: Try pattern matching first (faster, no API calls)
        print("🔍 Trying pattern matching first to avoid unnecessary API calls...")
        let analyzer = BoardingPassAnalyzer(content: content)
        if let patternResult = analyzer.extractBoardingPassData() {
            print("⚡ Pattern matching succeeded - no API calls needed!")
            return patternResult
        }
        
        // Strategy 2: Standard AI extraction (only if pattern matching failed)
        if let result = await tryExtractionStrategy(content: content, strategy: .standard) {
            print("✅ Standard AI extraction successful")
            return result
        }
        
        // Strategy 3: Aggressive extraction with forced field finding (reduced frequency)
        if let result = await tryExtractionStrategy(content: content, strategy: .enhanced) {
            print("✅ Enhanced extraction successful")
            return result
        }
        
        print("⚠️ All strategies failed")
        return nil
    }
    
    private enum ExtractionStrategy {
        case standard
        case aggressive 
        case enhanced
    }
    
    private func tryExtractionStrategy(content: String, strategy: ExtractionStrategy) async -> BoardingPassData? {
        do {
            let prompt = createExtractionPrompt(ocrContent: content, strategy: strategy)
            let extractedData = try await performAIExtraction(prompt: prompt)
            let result = parseAIResponse(extractedData)
            
            // Validate that we got meaningful data
            if let data = result, isExtractionValid(data) {
                return data
            }
            
            return nil
        } catch {
            print("❌ \(strategy) extraction failed: \(error)")
            return nil
        }
    }
    
    private func isExtractionValid(_ data: BoardingPassData) -> Bool {
        // Consider extraction valid if we have at least flight number and one airport
        let hasFlightNumber = data.flightNumber?.isEmpty == false
        let hasDeparture = data.departureCode?.isEmpty == false || data.departureCity?.isEmpty == false
        let hasArrival = data.arrivalCode?.isEmpty == false || data.arrivalCity?.isEmpty == false
        
        return hasFlightNumber && hasDeparture && hasArrival
    }
    
    private func getBasePrompt(strategy: ExtractionStrategy) -> String {
        switch strategy {
        case .standard:
            return "Extract boarding pass information from this OCR text. Look carefully for all flight details."
            
        case .aggressive:
            return """
            IMPORTANT: This is a boarding pass that DEFINITELY contains flight information. You MUST find the flight details even if they're partially obscured or formatted unusually.
            
            Search AGGRESSIVELY for:
            - Flight numbers (letters + numbers like AA123, DL456, UA789)
            - Airport codes (3-letter codes like JFK, LAX, DEL, LHR)
            - City names (New York, Los Angeles, Delhi, London, etc.)
            - Times (like 09:30, 2:15 PM, 14:45)
            - Passenger names (often in LAST/FIRST format)
            - Gate numbers (like A12, B7, Gate 15)
            - Seat assignments (like 12A, 34F)
            
            If you see partial information, make reasonable inferences. For example:
            - If you see "JF" near other airport info, it might be "JFK"
            - If you see "Los Angel" it's likely "Los Angeles"
            - If you see "Depar" followed by time, that's departure time
            
            DO NOT give up if the text is messy - boarding passes always have this information.
            """
            
        case .enhanced:
            return """
            You are an expert boarding pass reader. This OCR text contains a boarding pass with flight information that may be:
            - Split across multiple lines
            - Contains OCR errors or partial characters
            - Has mixed formatting
            - Includes UI elements and noise
            
            EXTRACTION RULES:
            1. Flight numbers: Look for 2-3 letters followed by 1-4 numbers (AA123, DL456)
            2. Airport codes: 3 capital letters that are real airport codes
            3. Cities: Match airport codes to their cities (JFK=New York, LAX=Los Angeles)
            4. Times: Any time format (24hr, 12hr with AM/PM)
            5. Names: Usually in format LAST/FIRST or First Last
            
            Be aggressive in finding information - boarding passes ALWAYS contain flight details.
            """
        }
    }
    
    private func createExtractionPrompt(ocrContent: String, strategy: ExtractionStrategy = .standard) -> String {
        let basePrompt = getBasePrompt(strategy: strategy)
        return """
        \(basePrompt)
        
        Return ONLY a JSON object with these exact fields:
        
        {
          "flightNumber": "flight number (e.g., A1102, UA546, DL123)",
          "passengerName": "passenger name (e.g., John Smith, SMITH/JOHN)",
          "departureCode": "departure airport code (3 letters, e.g., JFK)",
          "departureCity": "departure city name (e.g., New York, Los Angeles)",
          "arrivalCode": "arrival airport code (3 letters, e.g., DEL)",
          "arrivalCity": "arrival city name (e.g., Delhi, London)", 
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
        - Airport codes are exactly 3 letters (JFK, LAX, DEL, LHR)
        - City names should be the actual city names (New York, Delhi, London, Paris)
        - Passenger names are actual person names, not interface text
        - Match airport codes with their corresponding cities when possible
        
        OCR Text:
        \(ocrContent)
        
        JSON:
        """
    }
    
    private func performAIExtraction(prompt: String) async throws -> String {
        // Add exponential backoff retry for rate limits
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            do {
                return try await performSingleAIExtraction(prompt: prompt)
            } catch OCRError.apiError(429, _) {
                retryCount += 1
                if retryCount >= maxRetries {
                    print("❌ Max retries reached for rate limit, giving up")
                    throw OCRError.apiError(429, "Rate limit exceeded after \(maxRetries) retries")
                }
                
                let delay = pow(2.0, Double(retryCount)) // Exponential backoff: 2s, 4s, 8s
                print("⏳ Rate limited, waiting \(Int(delay))s before retry \(retryCount)/\(maxRetries)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw OCRError.apiError(429, "Should not reach here")
    }
    
    private func performSingleAIExtraction(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "mistral-small-latest",  // Use smaller model to reduce rate limits
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 300  // Reduce token usage
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        print("🤖 Sending AI extraction request...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Rate limit exceeded"
            print("⚠️ Rate limit hit (429)")
            throw OCRError.apiError(429, errorMessage)
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
        
        print("🤖 AI extraction response:\n```json\n\(extractedContent)\n```")
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
            data.departureCity = json["departureCity"] as? String
            data.arrivalCode = json["arrivalCode"] as? String
            data.arrivalCity = json["arrivalCity"] as? String
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
            print("   Route (Codes): \(data.departureCode ?? "N/A") → \(data.arrivalCode ?? "N/A")")
            print("   Route (Cities): \(data.departureCity ?? "N/A") → \(data.arrivalCity ?? "N/A")")
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
    
    // MARK: - Text Processing
    
    private func cleanMarkdownText(_ markdown: String) -> String {
        var cleanedText = markdown
        
        // Remove markdown headers
        cleanedText = cleanedText.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        
        // Remove markdown table formatting
        cleanedText = cleanedText.replacingOccurrences(of: #"\|"#, with: " ", options: .regularExpression)
        cleanedText = cleanedText.replacingOccurrences(of: #"---+"#, with: " ", options: .regularExpression)
        
        // Remove markdown bold/italic formatting
        cleanedText = cleanedText.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        cleanedText = cleanedText.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        
        // Remove image references
        cleanedText = cleanedText.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "", options: .regularExpression)
        
        // Clean up excessive whitespace and newlines
        cleanedText = cleanedText.replacingOccurrences(of: #"\n\s*\n"#, with: " ", options: .regularExpression)
        cleanedText = cleanedText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Remove common OCR noise patterns
        cleanedText = cleanedText.replacingOccurrences(of: #"[^A-Za-z0-9\s\-/:.,()]"#, with: " ", options: .regularExpression)
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Image Preprocessing
    
    private func preprocessImageForOCR(_ image: UIImage) -> UIImage {
        print("📸 Preprocessing image for enhanced OCR accuracy...")
        
        guard let cgImage = image.cgImage else {
            print("⚠️ Could not get CGImage, using original")
            return image
        }
        
        // Create a new image context with better quality settings
        let scale = min(2.0, max(1.0, image.scale)) // Ensure good resolution but not excessive
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            print("⚠️ Could not create graphics context, using original")
            return image
        }
        
        // Set high-quality rendering
        context.interpolationQuality = .high
        context.setShouldAntialias(false) // Disable antialiasing for sharper text
        context.setAllowsAntialiasing(false)
        
        // Draw the image with high quality settings
        let rect = CGRect(origin: .zero, size: size)
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: rect)
        }
        
        guard let processedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            print("⚠️ Could not create processed image, using original")
            return image
        }
        
        print("✅ Image preprocessed for better OCR (scale: \(scale))")
        return processedImage
    }
}

// MARK: - Data Models

struct MistralOCRAPIResponse: Codable {
    let pages: [MistralOCRPage]
    let model: String
    let usageInfo: MistralOCRUsageInfo?
    
    enum CodingKeys: String, CodingKey {
        case pages
        case model
        case usageInfo = "usage_info"
    }
}

struct MistralOCRPage: Codable {
    let index: Int
    let markdown: String  // Mistral OCR returns "markdown" not "content"
    let images: [MistralOCRImage]?
    let dimensions: MistralOCRPageDimensions?
}

struct MistralOCRImage: Codable {
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

struct MistralOCRPageDimensions: Codable {
    let dpi: Int
    let height: Int
    let width: Int
}

struct MistralOCRUsageInfo: Codable {
    let pagesProcessed: Int
    let docSizeBytes: Int
    
    enum CodingKeys: String, CodingKey {
        case pagesProcessed = "pages_processed"
        case docSizeBytes = "doc_size_bytes"
    }
}

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
        // Enhanced flight number patterns for ALL airlines including spaced formats
        let patterns = [
            #"\b[A-Z]{1,3}\s*\d{1,4}\b"#,  // General: A123, AA123, AAA123, 6E 6252
            #"(?i)flight[:\s]*([A-Z]{1,3}\s*\d{1,4})"#,  // "Flight: AA123"
            #"\b\d[A-Z]\d{2,4}\b"#,  // Some airlines use digit-letter-digit format
            #"\b[0-9][A-Z]\s+\d{3,4}\b"#,  // IndiGo format: 6E 6252
            #"[A-Z]{2}\s+\d{3,4}"# // Two letters space numbers: AI 123, UK 955
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
        print("🛫 Enhanced route extraction starting...")
        var foundAirports: [String] = []
        
        // Step 1: Look for city names and map them to airport codes
        let cityToCode = getCityToAirportMapping()
        for line in lines {
            let upperLine = line.uppercased()
            for (city, code) in cityToCode {
                if upperLine.contains(city.uppercased()) {
                    if !foundAirports.contains(code) {
                        foundAirports.append(code)
                        print("🏙️ Found city \(city) → \(code)")
                    }
                }
            }
        }
        
        // Step 2: Look for direct airport codes
        let airportPattern = #"\b[A-Z]{3}\b"#
        let content = lines.joined(separator: " ")
        let matches = content.ranges(of: airportPattern, options: .regularExpression)
        for match in matches {
            let airport = String(content[match])
            if isValidAirportCode(airport) && !foundAirports.contains(airport) {
                foundAirports.append(airport)
                print("✈️ Found airport code: \(airport)")
            }
        }
        
        // Step 3: Look for "To" patterns to determine direction
        let fullText = content.uppercased()
        if let toRange = fullText.range(of: " TO ") {
            let beforeTo = String(fullText[..<toRange.lowerBound])
            let afterTo = String(fullText[toRange.upperBound...])
            
            // Find airports before and after "TO"
            var departure: String? = nil
            var arrival: String? = nil
            
            for airport in foundAirports {
                if beforeTo.contains(airport) {
                    departure = airport
                }
                if afterTo.contains(airport) {
                    arrival = airport
                }
            }
            
            if departure != nil && arrival != nil {
                print("📍 Route identified via 'TO' pattern: \(departure!) → \(arrival!)")
                return (departure, arrival)
            }
        }
        
        // Step 4: Use order of appearance if we have exactly 2 airports
        if foundAirports.count >= 2 {
            print("📍 Route by order: \(foundAirports[0]) → \(foundAirports[1])")
            return (foundAirports[0], foundAirports[1])
        }
        
        print("⚠️ Could not determine complete route. Found: \(foundAirports)")
        return (foundAirports.first, foundAirports.count > 1 ? foundAirports[1] : nil)
    }
    
    private func getCityToAirportMapping() -> [String: String] {
        return [
            // Major Indian airports
            "HYDERABAD": "HYD", "SECUNDERABAD": "HYD",
            "CHANDIGARH": "IXC", 
            "DELHI": "DEL", "NEW DELHI": "DEL",
            "MUMBAI": "BOM", "BOMBAY": "BOM",
            "BANGALORE": "BLR", "BENGALURU": "BLR",
            "CHENNAI": "MAA", "MADRAS": "MAA",
            "KOLKATA": "CCU", "CALCUTTA": "CCU",
            "AHMEDABAD": "AMD",
            "PUNE": "PNQ",
            "GUWAHATI": "GAU",
            "KOCHI": "COK", "COCHIN": "COK",
            "THIRUVANANTHAPURAM": "TRV", "TRIVANDRUM": "TRV",
            "BHUBANESWAR": "BBI",
            "INDORE": "IDR",
            "SRINAGAR": "SXR",
            "JAMMU": "IXJ",
            "AMRITSAR": "ATQ",
            "GOA": "GOI", "PANAJI": "GOI",
            
            // International airports
            "NEW YORK": "JFK", "NYC": "JFK",
            "LOS ANGELES": "LAX", "LA": "LAX",
            "LONDON": "LHR", "HEATHROW": "LHR",
            "PARIS": "CDG",
            "DUBAI": "DXB",
            "SINGAPORE": "SIN",
            "TOKYO": "NRT",
            "HONG KONG": "HKG"
        ]
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
        var possibleSeats: [String] = []
        
        // Look for "Seat" context first (most reliable)
        for line in lines {
            if line.uppercased().contains("SEAT") {
                let seatPattern = #"\b\d{1,3}[A-F]\b"#
                let matches = line.ranges(of: seatPattern, options: .regularExpression)
                for match in matches {
                    let seat = String(line[match])
                    if isValidSeat(seat) {
                        print("💺 Found seat with context: \(seat)")
                        return seat
                    }
                }
            }
        }
        
        // Fallback: General seat pattern search (but filter out flight numbers)
        let seatPattern = #"\b\d{1,3}[A-F]\b"#
        let content = lines.joined(separator: " ")
        let matches = content.ranges(of: seatPattern, options: .regularExpression)
        
        for match in matches {
            let seat = String(content[match])
            if isValidSeat(seat) {
                possibleSeats.append(seat)
            }
        }
        
        // Return the first valid seat that's not a flight number
        for seat in possibleSeats {
            if !isFlightNumberPattern(seat) {
                print("💺 Found seat: \(seat)")
                return seat
            }
        }
        
        return possibleSeats.first
    }
    
    private func isValidSeat(_ seat: String) -> Bool {
        // Valid seat: 1-3 digits followed by a letter A-F
        guard seat.count >= 2 && seat.count <= 4 else { return false }
        
        // Should not be a flight number (which would have letters at the start)
        if seat.first?.isLetter == true { return false }
        
        // Should not be common false positives
        let blacklist = ["1A", "2A", "3A", "1B", "2B", "3B"] // Too short to be real seats
        return !blacklist.contains(seat)
    }
    
    private func isFlightNumberPattern(_ text: String) -> Bool {
        // Check if this looks like a flight number (letters followed by numbers)
        let flightPattern = #"^[A-Z]{1,3}\d+"#
        return text.range(of: flightPattern, options: .regularExpression) != nil
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