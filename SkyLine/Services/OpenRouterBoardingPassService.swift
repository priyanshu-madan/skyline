//
//  OpenRouterBoardingPassService.swift
//  SkyLine
//
//  Advanced boarding pass parsing using OpenRouter API with multiple LLM providers
//

import Foundation
import UIKit

// MARK: - OpenRouter Configuration

struct OpenRouterConfig {
    let apiKey: String
    let baseURL: String = "https://openrouter.ai/api/v1"
    let preferredModel: OpenRouterModel
    let fallbackModels: [OpenRouterModel]
    let maxTokens: Int
    let temperature: Double
    
    static let `default` = OpenRouterConfig(
        apiKey: "", // Will be loaded from Info.plist
        preferredModel: .gpt4o,
        fallbackModels: [.claude35Sonnet, .gpt4oMini],
        maxTokens: 2000,
        temperature: 0.1
    )
}

enum OpenRouterModel: String, CaseIterable {
    case gpt4Vision = "openai/gpt-4-vision-preview"
    case gpt4o = "openai/gpt-4o"
    case gpt4oMini = "openai/gpt-4o-mini"
    case claude35Sonnet = "anthropic/claude-3.5-sonnet"
    case claude3Haiku = "anthropic/claude-3-haiku"
    case gpt35Turbo = "openai/gpt-3.5-turbo"
    
    var displayName: String {
        switch self {
        case .gpt4Vision: return "GPT-4 Vision"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .claude35Sonnet: return "Claude 3.5 Sonnet"
        case .claude3Haiku: return "Claude 3 Haiku"
        case .gpt35Turbo: return "GPT-3.5 Turbo"
        }
    }
    
    var supportsVision: Bool {
        switch self {
        case .gpt4Vision, .gpt4o, .gpt4oMini, .claude35Sonnet:
            return true
        case .claude3Haiku, .gpt35Turbo:
            return false
        }
    }
    
    var estimatedCostPer1KTokens: Double {
        switch self {
        case .gpt4Vision: return 0.01
        case .gpt4o: return 0.005
        case .gpt4oMini: return 0.00015
        case .claude35Sonnet: return 0.003
        case .claude3Haiku: return 0.00025
        case .gpt35Turbo: return 0.0005
        }
    }
}

// MARK: - API Request/Response Models

struct OpenRouterRequest: Codable {
    let model: String
    let messages: [OpenRouterMessage]
    let maxTokens: Int
    let temperature: Double
    let responseFormat: ResponseFormat?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
    
    struct ResponseFormat: Codable {
        let type: String = "json_object"
    }
}

struct OpenRouterMessage: Codable {
    let role: String
    let content: [MessageContent]
}

struct MessageContent: Codable {
    let type: String
    let text: String?
    let imageUrl: ImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    struct ImageURL: Codable {
        let url: String
    }
}

struct OpenRouterResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?
    let error: OpenRouterError?
    
    struct Choice: Codable {
        let message: ResponseMessage
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct ResponseMessage: Codable {
        let role: String
        let content: String
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenRouterError: Codable {
    let message: String
    let code: String?
}

// MARK: - Boarding Pass Response Model

struct OpenRouterBoardingPassData: Codable {
    let success: Bool
    let confidence: Double
    let flightNumber: String?
    let airline: String?
    let passengerName: String?
    let departureAirport: String?
    let arrivalAirport: String?
    let departureTime: String?
    let arrivalTime: String?
    let flightDate: String?
    let flightDateRaw: String?
    let departureDate: String?
    let arrivalDate: String?
    let departureDateRaw: String?
    let arrivalDateRaw: String?
    let seat: String?
    let gate: String?
    let terminal: String?
    let ticketNumber: String?
    let confirmationCode: String?
    let boardingTime: String?
    let flightDuration: String?
    let errors: [String]?
    let extractedText: String?
}

// MARK: - Main Service

@MainActor
class OpenRouterBoardingPassService: ObservableObject {
    static let shared = OpenRouterBoardingPassService()
    
    @Published var isProcessing = false
    @Published var lastUsedModel: OpenRouterModel?
    @Published var lastTokenUsage: OpenRouterResponse.Usage?
    @Published var lastError: String?
    
    var config: OpenRouterConfig
    private let session = URLSession.shared
    
    private init() {
        // API key not needed - using Cloudflare Worker proxy
        self.config = OpenRouterConfig(
            apiKey: "not-needed-using-worker",
            preferredModel: .gpt4o,
            fallbackModels: [.claude35Sonnet, .gpt4oMini],
            maxTokens: 2000,
            temperature: 0.1
        )
        print("🔧 OpenRouterBoardingPassService initialized with Cloudflare Worker proxy")
    }
    
    // MARK: - Public Interface
    
    func parseImage(_ image: UIImage) async -> BoardingPassData? {
        print("🚀 OpenRouter: Starting boarding pass analysis via Cloudflare Worker")

        await MainActor.run {
            isProcessing = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Try preferred model first, then fallbacks
        let modelsToTry = [config.preferredModel] + config.fallbackModels

        for model in modelsToTry {
            if let result = await tryParsingWithModel(model, image: image) {
                await MainActor.run {
                    lastUsedModel = model
                }
                return result
            }
        }

        print("❌ OpenRouter: All models failed to parse boarding pass")
        await MainActor.run {
            lastError = "All parsing attempts failed"
        }
        return nil
    }
    
    func updateApiKey(_ apiKey: String) {
        config = OpenRouterConfig(
            apiKey: apiKey,
            preferredModel: config.preferredModel,
            fallbackModels: config.fallbackModels,
            maxTokens: config.maxTokens,
            temperature: config.temperature
        )
        
        // Store in Keychain for persistence
        KeychainHelper.store(apiKey, for: "openrouter_api_key")
    }
    
    func loadApiKey() {
        if let apiKey = KeychainHelper.retrieve(for: "openrouter_api_key") {
            updateApiKey(apiKey)
        }
    }
    
    private func loadApiKeyFromInfoPlist() {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["OPENROUTER_API_KEY"] as? String,
              !apiKey.isEmpty && apiKey != "YOUR_OPENROUTER_API_KEY_HERE" else {
            print("⚠️ OpenRouter: API key not found in Info.plist or is placeholder")
            return
        }
        
        updateApiKey(apiKey)
        print("✅ OpenRouter: API key loaded from Info.plist")
    }
    
    func updatePreferredModel(_ model: OpenRouterModel) {
        config = OpenRouterConfig(
            apiKey: config.apiKey,
            preferredModel: model,
            fallbackModels: config.fallbackModels,
            maxTokens: config.maxTokens,
            temperature: config.temperature
        )
    }
    
    // MARK: - Private Implementation
    
    private func tryParsingWithModel(_ model: OpenRouterModel, image: UIImage) async -> BoardingPassData? {
        print("🧠 OpenRouter: Trying model \(model.displayName)")
        
        guard model.supportsVision else {
            print("⚠️ OpenRouter: Model \(model.displayName) doesn't support vision")
            return nil
        }
        
        // Optimize image for API
        guard let optimizedImage = preprocessImage(image),
              let base64Image = optimizedImage.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
            print("❌ OpenRouter: Failed to process image")
            return nil
        }
        
        // Create request
        let request = createRequest(for: model, base64Image: base64Image)
        
        do {
            let response = try await sendRequest(request)
            return await processResponse(response, model: model)
        } catch {
            print("❌ OpenRouter: Request failed for \(model.displayName): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func preprocessImage(_ image: UIImage) -> UIImage? {
        // Resize image to reduce API costs while maintaining readability
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return resizedImage
        }
        
        return image
    }
    
    private func createRequest(for model: OpenRouterModel, base64Image: String) -> OpenRouterRequest {
        let systemPrompt = """
        You are a specialized document-extraction engine for airline boarding passes and flight tickets.

        Your task:
        - Analyze the provided image (boarding pass or airline ticket).
        - Extract ONLY information that is explicitly visible.
        - Do NOT guess, infer, or assume missing values.

        CRITICAL:
        - Output MUST be valid JSON only.
        - Follow the schema EXACTLY.
        - If a value is missing, unreadable, or ambiguous, set it to null.

        OUTPUT SCHEMA (STRICT):

        {
          "success": boolean,
          "confidence": number,
          "flightNumber": string | null,
          "airline": string | null,
          "passengerName": string | null,
          "departureAirport": string | null,
          "arrivalAirport": string | null,
          "departureTime": string | null,
          "arrivalTime": string | null,
          "flightDate": string | null,
          "flightDateRaw": string | null,
          "departureDate": string | null,
          "arrivalDate": string | null,
          "departureDateRaw": string | null,
          "arrivalDateRaw": string | null,
          "seat": string | null,
          "gate": string | null,
          "terminal": string | null,
          "ticketNumber": string | null,
          "confirmationCode": string | null,
          "boardingTime": string | null,
          "flightDuration": string | null,
          "errors": string[],
          "extractedText": string
        }

        EXTRACTION RULES (NON-NEGOTIABLE):

        GENERAL
        1. Do NOT guess or infer values.
        2. Never hallucinate airport codes, dates, times, or airlines.
        3. If the document is clearly NOT a boarding pass, set success = false.

        PASSENGER
        4. Extract passenger name exactly as printed.
        5. Remove titles such as MR, MS, MRS, DR.
        6. Preserve original order (e.g., LAST/FIRST).

        AIRPORTS
        7. Use 3-letter IATA codes ONLY if explicitly printed.
        8. If only a city or airport name is shown, set airport fields to null.

        DATES (INTELLIGENT CALCULATION REQUIRED)
        9. departureDate: Convert to YYYY-MM-DD ONLY if day, month, and year are explicitly present.
        10. arrivalDate: Use your intelligence to calculate the correct arrival date:
            - If both departure and arrival dates are shown, extract both separately
            - If only one date is visible, calculate arrival date using your knowledge of:
              * Airport timezones (LAX=PST/PDT, JFK=EST/EDT, NRT=JST, etc.)
              * Typical flight durations between airports
              * International date line crossings
              * Time zone differences
            - Examples:
              * LAX 11:30 PM → JFK 7:30 AM: arrival date = departure date + 1 day
              * SFO 2:00 PM → NRT 4:30 PM: arrival date = departure date + 1 day (crosses date line)
              * JFK 9:00 AM → LAX 12:30 PM: arrival date = same as departure date (timezone compensation)
        11. departureDateRaw: Include the exact departure date text as it appears on the boarding pass.
        12. arrivalDateRaw: Include the exact arrival date text if shown separately.
        13. flightDate: Convert to YYYY-MM-DD ONLY if day, month, and year are explicitly present (legacy field).
        14. flightDateRaw: Include the exact date text as it appears on the boarding pass (legacy field).
        15. If uncertain about arrival date calculation, set arrivalDate to null rather than guessing.
        16. PRIORITY: Use departureDate/arrivalDate over legacy flightDate when possible.

        TIMES
        17. Convert times to 24-hour HH:mm format ONLY if clearly readable.
        18. Examples:
            - "2:30 PM" → "14:30"
            - "1425" → "14:25"
        19. If uncertain, set time fields to null.
        
        FLIGHT DURATION (INTELLIGENT CALCULATION REQUIRED)
        20. flightDuration: Calculate the actual flight duration using your intelligence:
            - Use your knowledge of airport timezones and flight routes
            - Consider time zone differences between departure and arrival airports
            - Account for international date line crossings
            - Format as "XH YYM" (e.g., "5H 25M", "12H 45M", "1H 05M")
            - Examples:
              * LAX 11:30 PM Dec 23 → JFK 7:30 AM Dec 24: duration = "5H 00M" (PST to EST)
              * SFO 2:00 PM Dec 23 → NRT 4:30 PM Dec 24: duration = "11H 30M" (crosses date line)
              * JFK 9:00 AM Dec 23 → LAX 12:30 PM Dec 23: duration = "6H 30M" (EST to PST)
            - If you cannot accurately calculate duration, set to null
            - ONLY calculate if you have both departure and arrival times

        FLIGHT
        21. Extract flight number exactly (e.g., WY0153, AA123).
        22. Extract airline name ONLY if explicitly printed.

        SEAT / GATE / TERMINAL
        23. Extract only if clearly labeled (SEAT, GATE, TERMINAL).
        24. If multiple values exist, choose the most clearly labeled one.

        TICKET / CONFIRMATION
        25. ticketNumber: Extract ticket number if labeled as:
            - Ticket No
            - Ticket Number
            - E-Ticket
        26. confirmationCode: Extract confirmation code if labeled as:
            - PNR
            - Booking Ref
            - Record Locator
            - Confirmation
        27. Extract ONLY if explicitly visible and clearly labeled.

        DEBUGGING
        28. extractedText should include ONLY relevant flight-related text.
        29. Do NOT dump all OCR text.

        CONFIDENCE SCORING (MANDATORY):

        Start at 0.3
        +0.1 if flightNumber is present
        +0.1 if airline is present
        +0.1 if passengerName is present
        +0.1 if departureAirport is present
        +0.1 if arrivalAirport is present
        +0.1 if departureDate OR flightDate is present
        +0.1 if departureTime is present
        +0.1 if flightDuration is successfully calculated
        Cap at 1.0
        """
        
        let userMessage = OpenRouterMessage(
            role: "user",
            content: [
                MessageContent(type: "text", text: "Analyze the following boarding pass image and extract all available flight information.", imageUrl: nil),
                MessageContent(type: "image_url", text: nil, imageUrl: MessageContent.ImageURL(url: "data:image/jpeg;base64,\(base64Image)"))
            ]
        )
        
        let systemMessage = OpenRouterMessage(
            role: "system",
            content: [
                MessageContent(type: "text", text: systemPrompt, imageUrl: nil)
            ]
        )
        
        return OpenRouterRequest(
            model: model.rawValue,
            messages: [systemMessage, userMessage],
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            responseFormat: OpenRouterRequest.ResponseFormat()
        )
    }
    
    private func sendRequest(_ request: OpenRouterRequest) async throws -> OpenRouterResponse {
        // Use Cloudflare Worker proxy instead of calling OpenRouter directly
        guard let url = URL(string: "https://skyline-openrouter-proxy.pmadan-illinois.workers.dev") else {
            throw URLError(.badURL)
        }

        // Get user ID for rate limiting
        let userId = AuthenticationService.shared.authenticationState.user?.id ?? "anonymous"

        // Convert our request to worker format
        let base64Image = extractBase64ImageFromRequest(request)
        let systemPrompt = extractSystemPromptFromRequest(request)
        let userPrompt = extractUserPromptFromRequest(request)

        let fullPrompt = """
        \(systemPrompt)

        USER REQUEST:
        \(userPrompt)
        """

        var workerRequest: [String: Any] = [
            "prompt": fullPrompt,
            "model": request.model,
            "userId": userId,
            "maxTokens": request.maxTokens
        ]

        // Add image if present
        if let imageData = base64Image {
            workerRequest["imageBase64"] = imageData
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: workerRequest)
        urlRequest.timeoutInterval = 120 // 2 minutes for vision models

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ OpenRouter: HTTP \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ OpenRouter: Error response: \(errorData)")
            }
            throw URLError(.badServerResponse)
        }

        do {
            // Parse worker response
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let success = json?["success"] as? Bool, success,
                  let responseData = json?["data"] as? [String: Any] else {
                throw NSError(domain: "OpenRouterError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Worker returned error"])
            }

            // Convert worker response back to OpenRouterResponse format
            let openRouterResponseData = try JSONSerialization.data(withJSONObject: responseData)
            let openRouterResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: openRouterResponseData)

            if let error = openRouterResponse.error {
                print("❌ OpenRouter: API error: \(error.message)")
                throw NSError(domain: "OpenRouterError", code: 0, userInfo: [NSLocalizedDescriptionKey: error.message])
            }

            return openRouterResponse
        } catch {
            print("❌ OpenRouter: Failed to decode response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ OpenRouter: Raw response: \(responseString)")
            }
            throw error
        }
    }

    // Helper functions to extract data from request
    private func extractBase64ImageFromRequest(_ request: OpenRouterRequest) -> String? {
        for message in request.messages {
            for content in message.content {
                if content.type == "image_url", let imageUrl = content.imageUrl?.url {
                    // Extract base64 from data URL
                    if imageUrl.hasPrefix("data:image/") {
                        if let base64Range = imageUrl.range(of: "base64,") {
                            return String(imageUrl[base64Range.upperBound...])
                        }
                    }
                }
            }
        }
        return nil
    }

    private func extractSystemPromptFromRequest(_ request: OpenRouterRequest) -> String {
        for message in request.messages {
            if message.role == "system" {
                for content in message.content {
                    if let text = content.text {
                        return text
                    }
                }
            }
        }
        return ""
    }

    private func extractUserPromptFromRequest(_ request: OpenRouterRequest) -> String {
        for message in request.messages {
            if message.role == "user" {
                for content in message.content {
                    if content.type == "text", let text = content.text {
                        return text
                    }
                }
            }
        }
        return ""
    }
    
    private func processResponse(_ response: OpenRouterResponse, model: OpenRouterModel) async -> BoardingPassData? {
        guard let choice = response.choices.first else {
            print("❌ OpenRouter: No choices in response")
            return nil
        }

        await MainActor.run {
            lastTokenUsage = response.usage
        }

        if let usage = response.usage {
            let estimatedCost = Double(usage.totalTokens) * model.estimatedCostPer1KTokens / 1000.0
            print("💰 OpenRouter: Used \(usage.totalTokens) tokens, estimated cost: $\(String(format: "%.4f", estimatedCost))")
        }

        // Clean up response content - remove markdown code blocks if present
        var cleanedContent = choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json and ``` markers
        if cleanedContent.hasPrefix("```json") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedContent.hasPrefix("```") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```", with: "", options: [], range: cleanedContent.startIndex..<cleanedContent.index(cleanedContent.startIndex, offsetBy: 3))
        }
        if cleanedContent.hasSuffix("```") {
            let endIndex = cleanedContent.index(cleanedContent.endIndex, offsetBy: -3)
            cleanedContent = String(cleanedContent[..<endIndex])
        }
        cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let boardingPassData = try JSONDecoder().decode(OpenRouterBoardingPassData.self, from: cleanedContent.data(using: .utf8) ?? Data())
            
            guard boardingPassData.success else {
                print("⚠️ OpenRouter: Model indicated parsing failure")
                if let errors = boardingPassData.errors {
                    print("⚠️ OpenRouter: Errors: \(errors.joined(separator: ", "))")
                }
                return nil
            }
            
            print("✅ OpenRouter: Successfully parsed boarding pass with \(Int(boardingPassData.confidence * 100))% confidence")
            print("📋 OpenRouter: Raw API Response Details:")
            print("   ✈️  Flight: \(boardingPassData.flightNumber ?? "N/A")")
            print("   🏢 Airline: \(boardingPassData.airline ?? "N/A")")
            print("   👤 Passenger: \(boardingPassData.passengerName ?? "N/A")")
            print("   🛫 Departure: \(boardingPassData.departureAirport ?? "N/A") at \(boardingPassData.departureTime ?? "N/A")")
            print("   🛬 Arrival: \(boardingPassData.arrivalAirport ?? "N/A") at \(boardingPassData.arrivalTime ?? "N/A")")
            print("   📅 Departure Date: '\(boardingPassData.departureDate ?? "N/A")' (Raw: '\(boardingPassData.departureDateRaw ?? "N/A")')")
            print("   📅 Arrival Date: '\(boardingPassData.arrivalDate ?? "N/A")' (Raw: '\(boardingPassData.arrivalDateRaw ?? "N/A")')")
            print("   📅 Legacy Flight Date: '\(boardingPassData.flightDate ?? "N/A")' (Raw: '\(boardingPassData.flightDateRaw ?? "N/A")')")
            print("   💺 Seat: \(boardingPassData.seat ?? "N/A")")
            print("   🚪 Gate: \(boardingPassData.gate ?? "N/A")")
            print("   🏢 Terminal: \(boardingPassData.terminal ?? "N/A")")
            print("   🎟️ Ticket Number: \(boardingPassData.ticketNumber ?? "N/A")")
            print("   🎫 Confirmation: \(boardingPassData.confirmationCode ?? "N/A")")
            print("   🕐 Boarding: \(boardingPassData.boardingTime ?? "N/A")")
            print("   ⏱️ Flight Duration: \(boardingPassData.flightDuration ?? "N/A")")
            if let errors = boardingPassData.errors, !errors.isEmpty {
                print("   ⚠️  Errors: \(errors.joined(separator: ", "))")
            }
            if let extractedText = boardingPassData.extractedText {
                print("   📝 Raw Text: \(extractedText.prefix(200))...")
            }
            
            let convertedData = convertToStandardFormat(boardingPassData)
            print("📊 OpenRouter: Converted to StandardFormat:")
            print("   Flight: \(convertedData.flightNumber ?? "N/A")")
            print("   Route: \(convertedData.departureCode ?? "N/A") → \(convertedData.arrivalCode ?? "N/A")")
            print("   Times: \(convertedData.departureTime ?? "N/A") → \(convertedData.arrivalTime ?? "N/A")")
            
            return convertedData
            
        } catch {
            print("❌ OpenRouter: Failed to parse JSON response: \(error)")
            print("❌ OpenRouter: Raw content: \(choice.message.content)")
            return nil
        }
    }
    
    private func convertToStandardFormat(_ data: OpenRouterBoardingPassData) -> BoardingPassData {
        var boardingPassData = BoardingPassData()
        
        boardingPassData.flightNumber = data.flightNumber
        boardingPassData.airline = data.airline
        boardingPassData.departureCode = data.departureAirport
        boardingPassData.arrivalCode = data.arrivalAirport
        boardingPassData.departureTime = data.departureTime
        boardingPassData.arrivalTime = data.arrivalTime
        boardingPassData.gate = data.gate
        boardingPassData.terminal = data.terminal
        boardingPassData.seat = data.seat
        boardingPassData.confirmationCode = data.confirmationCode
        boardingPassData.passengerName = data.passengerName
        boardingPassData.flightDuration = data.flightDuration
        
        // Parse departure and arrival dates separately
        // Priority: departureDate/arrivalDate over legacy flightDate
        
        // Parse departure date
        if let departureDate = parseDateString(data.departureDate, fallback: data.departureDateRaw, source: "departure") {
            boardingPassData.departureDate = departureDate
            print("📅 OpenRouter: Set departure date: \(departureDate)")
        } else if let legacyDate = parseDateString(data.flightDate, fallback: data.flightDateRaw, source: "legacy flight") {
            boardingPassData.departureDate = legacyDate
            print("📅 OpenRouter: Set departure date from legacy field: \(legacyDate)")
        } else {
            print("⚠️ OpenRouter: No departure date available to parse")
        }
        
        // Parse arrival date (use intelligent calculation from OpenRouter)
        if let arrivalDate = parseDateString(data.arrivalDate, fallback: data.arrivalDateRaw, source: "arrival") {
            boardingPassData.arrivalDate = arrivalDate
            print("📅 OpenRouter: Set arrival date: \(arrivalDate)")
        } else if let departureDate = boardingPassData.departureDate {
            // Fallback: use departure date if arrival date couldn't be calculated
            boardingPassData.arrivalDate = departureDate
            print("📅 OpenRouter: Using departure date as fallback for arrival date")
        } else {
            print("⚠️ OpenRouter: No arrival date available to parse")
        }
        
        return boardingPassData
    }
    
    private func parseDateString(_ primary: String?, fallback: String?, source: String) -> Date? {
        var dateStringToUse: String?
        var dateSource = ""
        
        if let primaryDate = primary, !primaryDate.isEmpty && primaryDate != "N/A" {
            dateStringToUse = primaryDate
            dateSource = "\(source) (primary)"
        } else if let fallbackDate = fallback, !fallbackDate.isEmpty && fallbackDate != "N/A" {
            dateStringToUse = fallbackDate
            dateSource = "\(source) (fallback)"
        }
        
        guard let dateString = dateStringToUse else {
            return nil
        }
        
        print("🗓️ OpenRouter: Attempting to parse \(source) date string: '\(dateString)' from \(dateSource)")
        
        var parsedDate: Date?
        
        // Try ISO8601 first
        let iso8601Formatter = ISO8601DateFormatter()
        parsedDate = iso8601Formatter.date(from: dateString)
        
        if parsedDate != nil {
            print("✅ OpenRouter: Successfully parsed \(source) date with ISO8601 format")
        } else {
            // Try common date formats including boarding pass specific formats
            let dateFormats = [
                "yyyy-MM-dd",
                "MM/dd/yyyy",
                "dd/MM/yyyy", 
                "MMM dd, yyyy",
                "dd MMM yyyy",
                "MMMM dd, yyyy",
                "yyyy/MM/dd",
                "dd-MM-yyyy",
                "MM-dd-yyyy",
                "ddMMM",        // 08APR
                "ddMMMM",       // 08APRIL
                "MMM dd",       // APR 08
                "MMMM dd",      // APRIL 08
                "dd-MMM",       // 08-APR
                "dd MMM",       // 08 APR
                "MMM-dd",       // APR-08
                "MMMdd",        // APR08
                "dd/MMM",       // 08/APR
                "MMM/dd"        // APR/08
            ]
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: dateString) {
                    parsedDate = date
                    print("✅ OpenRouter: Successfully parsed \(source) date with format: \(format)")
                    break
                }
            }
            
            // If we still don't have a date and the string looks like it might need a year
            if parsedDate == nil && (dateString.contains("APR") || dateString.contains("JAN") || dateString.contains("FEB") || 
                                   dateString.contains("MAR") || dateString.contains("MAY") || dateString.contains("JUN") ||
                                   dateString.contains("JUL") || dateString.contains("AUG") || dateString.contains("SEP") ||
                                   dateString.contains("OCT") || dateString.contains("NOV") || dateString.contains("DEC")) {
                // Try adding current year for partial dates like "08APR"
                let currentYear = Calendar.current.component(.year, from: Date())
                let dateStringWithYear = "\(dateString)\(currentYear)"
                
                let yearFormats = ["ddMMMMyyyy", "MMMddyyyy"]
                for format in yearFormats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: dateStringWithYear) {
                        parsedDate = date
                        print("✅ OpenRouter: Successfully parsed \(source) date with year added: \(format)")
                        break
                    }
                }
            }
        }
        
        if parsedDate == nil {
            print("❌ OpenRouter: Failed to parse \(source) date string: '\(dateString)' from \(dateSource) - tried all formats")
        }
        
        return parsedDate
    }
}

// MARK: - Keychain Helper

class KeychainHelper {
    static func store(_ value: String, for key: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func retrieve(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}