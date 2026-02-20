//
//  AIItineraryService.swift
//  SkyLine
//
//  AI-powered itinerary parsing and creation using OpenRouter API
//

import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
class AIItineraryService: ObservableObject {
    static let shared = AIItineraryService()

    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var currentStatus = "Ready"
    @Published var isGeneratingItinerary = false
    
    private var config: OpenRouterConfig
    private let session = URLSession.shared
    
    private init() {
        self.config = .default
        print("✅ AIItineraryService: Initialized (using Cloudflare Worker proxy)")
    }
    
    // MARK: - Main Processing Methods
    
    /// Process an image to extract itinerary information
    func processImage(_ image: UIImage) async -> Result<ParsedItinerary, AIItineraryError> {
        isProcessing = true
        currentStatus = "Processing image..."
        processingProgress = 0.1
        
        let startTime = Date()
        
        do {
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw AIItineraryError.imageProcessingFailed("Failed to convert image to data")
            }
            
            processingProgress = 0.3
            currentStatus = "Analyzing content with AI..."
            
            // Create specialized prompt for itinerary extraction
            let prompt = createItineraryExtractionPrompt()
            
            // Use OpenRouter's vision models
            let request = createVisionRequest(prompt: prompt, imageData: imageData)
            let response = await sendRequest(request)
            
            processingProgress = 0.7
            currentStatus = "Parsing AI response..."
            
            switch response {
            case .success(let aiResponse):
                let parsedItinerary = try parseAIResponse(aiResponse, sourceType: .image, processingTime: Date().timeIntervalSince(startTime))
                
                processingProgress = 1.0
                currentStatus = "Complete"
                isProcessing = false
                
                return .success(parsedItinerary)
                
            case .failure(let error):
                isProcessing = false
                currentStatus = "Failed"
                return .failure(error)
            }
            
        } catch {
            isProcessing = false
            currentStatus = "Failed"
            return .failure(.aiProcessingFailed(error.localizedDescription))
        }
    }
    
    /// Process text content (from PDF, Excel, etc.)
    func processText(_ text: String, sourceType: ItinerarySourceType) async -> Result<ParsedItinerary, AIItineraryError> {
        isProcessing = true
        currentStatus = "Processing text..."
        processingProgress = 0.1
        
        let startTime = Date()
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isProcessing = false
            return .failure(.invalidInput("Text content is empty"))
        }
        
        do {
            processingProgress = 0.3
            currentStatus = "Analyzing content with AI..."
            
            // Create specialized prompt for text-based itinerary extraction
            let prompt = createTextItineraryExtractionPrompt(text: text)
            
            // Use OpenRouter's text models
            let request = createTextRequest(prompt: prompt)
            let response = await sendRequest(request)
            
            processingProgress = 0.7
            currentStatus = "Parsing AI response..."
            
            switch response {
            case .success(let aiResponse):
                let parsedItinerary = try parseAIResponse(aiResponse, sourceType: sourceType, processingTime: Date().timeIntervalSince(startTime))
                
                processingProgress = 1.0
                currentStatus = "Complete"
                isProcessing = false
                
                return .success(parsedItinerary)
                
            case .failure(let error):
                isProcessing = false
                currentStatus = "Failed"
                return .failure(error)
            }
            
        } catch {
            isProcessing = false
            currentStatus = "Failed"
            return .failure(.aiProcessingFailed(error.localizedDescription))
        }
    }
    
    /// Generate custom itinerary based on user preferences
    /// Callback type for streaming itinerary generation - receives each activity as it's parsed
    typealias ActivityCallback = (ItineraryItem) -> Void

    /// Generate custom itinerary with streaming - activities appear one by one
    func generateCustomItineraryStreaming(
        destination: String,
        duration: Int,
        startDate: Date,
        endDate: Date,
        preferences: ItineraryPreferences,
        onActivity: @escaping ActivityCallback
    ) async -> Result<Void, AIItineraryError> {
        isProcessing = true
        // Don't show loading overlay for streaming - activities appear directly in timeline
        isGeneratingItinerary = false
        currentStatus = "Generating custom itinerary..."
        processingProgress = 0.1

        do {
            currentStatus = "Creating personalized itinerary..."

            let prompt = createCustomItineraryPrompt(
                destination: destination,
                duration: duration,
                startDate: startDate,
                endDate: endDate,
                preferences: preferences
            )

            var accumulatedResponse = ""
            var itemsBuffer: [ItineraryItem] = []

            // Use streaming to get response chunks
            let fullResponse = try await OpenRouterService.shared.sendPromptStreaming(
                prompt,
                model: config.preferredModel.rawValue,
                maxTokens: config.maxTokens * 3,
                onChunk: { chunk in
                    Task { @MainActor in
                        accumulatedResponse += chunk

                        print("📦 Streaming chunk received (\(accumulatedResponse.count) chars total)")

                        // Log first chunk to see response format
                        if accumulatedResponse.count < 500 && accumulatedResponse.count > 10 {
                            print("🔍 First chunk content: \(accumulatedResponse)")
                        }

                        // Try to parse activities from accumulated response
                        if let newItems = self.tryParsePartialActivities(accumulatedResponse, parsedCount: itemsBuffer.count) {
                            print("✨ Parsed \(newItems.count) new activities!")

                            for item in newItems {
                                // Call callback for each new activity
                                onActivity(item)
                                itemsBuffer.append(item)
                            }

                            // Update progress based on items received
                            let estimatedTotal = Double(duration * 4) // Rough estimate: 4 activities per day
                            self.processingProgress = 0.3 + (Double(itemsBuffer.count) / estimatedTotal) * 0.6
                        }
                    }
                }
            )

            print("📥 Streaming complete: \(accumulatedResponse.count) characters, \(itemsBuffer.count) activities parsed")

            processingProgress = 1.0
            currentStatus = "Complete"
            isProcessing = false
            // isGeneratingItinerary already false - no overlay for streaming

            return .success(())

        } catch {
            isProcessing = false
            isGeneratingItinerary = false
            currentStatus = "Failed"
            return .failure(.aiProcessingFailed(error.localizedDescription))
        }
    }

    /// Original non-streaming version (kept for backward compatibility)
    func generateCustomItinerary(destination: String, duration: Int, startDate: Date, endDate: Date, preferences: ItineraryPreferences) async -> Result<ParsedItinerary, AIItineraryError> {
        isProcessing = true
        isGeneratingItinerary = true
        currentStatus = "Generating custom itinerary..."
        processingProgress = 0.1

        let startTime = Date()

        do {
            processingProgress = 0.3
            currentStatus = "Creating personalized itinerary..."

            let prompt = createCustomItineraryPrompt(destination: destination, duration: duration, startDate: startDate, endDate: endDate, preferences: preferences)

            let request = createTextRequest(prompt: prompt)
            let response = await sendRequest(request)

            processingProgress = 0.7
            currentStatus = "Finalizing itinerary..."

            switch response {
            case .success(let aiResponse):
                let parsedItinerary = try parseAIResponse(aiResponse, sourceType: .manual, processingTime: Date().timeIntervalSince(startTime))

                processingProgress = 1.0
                currentStatus = "Complete"
                isProcessing = false
                isGeneratingItinerary = false

                return .success(parsedItinerary)

            case .failure(let error):
                isProcessing = false
                isGeneratingItinerary = false
                currentStatus = "Failed"
                return .failure(error)
            }

        } catch {
            isProcessing = false
            isGeneratingItinerary = false
            currentStatus = "Failed"
            return .failure(.aiProcessingFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Prompt Creation
    
    private func createItineraryExtractionPrompt() -> String {
        return """
        You are an expert travel itinerary parser. Analyze this image and extract a structured itinerary with the following information:

        REQUIREMENTS:
        1. Parse all activities, events, and time-based information
        2. Detect dates, times, and locations
        3. Categorize activities into types: food, activity, sightseeing, accommodation, transportation, shopping, note, photo
        4. Extract location details including addresses when available
        5. Estimate duration for activities when not explicitly stated
        6. Provide confidence scores for each parsed item

        RESPONSE FORMAT (JSON only, no additional text):
        {
          "tripTitle": "string or null",
          "destination": "string or null", 
          "detectedTimeZone": "string or null",
          "items": [
            {
              "title": "Activity name",
              "content": "Detailed description",
              "activityType": "food|activity|sightseeing|accommodation|transportation|shopping|note|photo",
              "dateTime": "2024-01-15T10:30:00Z",
              "location": {
                "name": "Location name",
                "address": "Full address or null",
                "latitude": 12.345 or null,
                "longitude": 67.890 or null,
                "city": "City name or null",
                "country": "Country name or null"
              },
              "estimatedDuration": 7200,
              "confidence": 0.95,
              "originalText": "Original text from image or null"
            }
          ]
        }

        IMPORTANT:
        - Use ISO 8601 format for all dates/times
        - Duration in seconds
        - Confidence between 0.0 and 1.0
        - If date/time is unclear, use reasonable defaults based on context
        - Include coordinates only if you're confident about the location
        """
    }
    
    private func createTextItineraryExtractionPrompt(text: String) -> String {
        return """
        You are an expert travel itinerary parser. Analyze this text content and extract a structured itinerary.

        TEXT CONTENT:
        \(text)

        REQUIREMENTS:
        1. Parse all activities, events, and time-based information
        2. Detect dates, times, and locations
        3. Categorize activities into types: food, activity, sightseeing, accommodation, transportation, shopping, note, photo
        4. Extract location details including addresses when available
        5. Estimate duration for activities when not explicitly stated
        6. Handle different formats (schedules, confirmations, notes)

        RESPONSE FORMAT (JSON only, no additional text):
        {
          "tripTitle": "string or null",
          "destination": "string or null", 
          "detectedTimeZone": "string or null",
          "items": [
            {
              "title": "Activity name",
              "content": "Detailed description",
              "activityType": "food|activity|sightseeing|accommodation|transportation|shopping|note|photo",
              "dateTime": "2024-01-15T10:30:00Z",
              "location": {
                "name": "Location name",
                "address": "Full address or null",
                "latitude": 12.345 or null,
                "longitude": 67.890 or null,
                "city": "City name or null",
                "country": "Country name or null"
              },
              "estimatedDuration": 7200,
              "confidence": 0.95,
              "originalText": "Original parsed text or null"
            }
          ]
        }

        IMPORTANT:
        - Use ISO 8601 format for all dates/times
        - Duration in seconds
        - Confidence between 0.0 and 1.0
        - Smart date/time inference from context
        """
    }
    
    private func createCustomItineraryPrompt(destination: String, duration: Int, startDate: Date, endDate: Date, preferences: ItineraryPreferences) -> String {
        // Format dates for the prompt
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        // Format for ISO8601 in examples
        let iso8601Formatter = ISO8601DateFormatter()
        let exampleDate = iso8601Formatter.string(from: startDate)

        return """
        CRITICAL: Your entire response must be ONLY valid JSON. Do not include any text, explanations, or markdown before or after the JSON. Start your response with { and end with }. No code blocks, no explanations.

        Create a detailed \(duration)-day itinerary for \(destination).

        TRIP DATES: \(startDateString) to \(endDateString)
        IMPORTANT: Use these EXACT dates. Start Day 1 activities on \(startDateString).

        USER PREFERENCES:
        - Budget: \(preferences.budget.rawValue)
        - Travel Style: \(preferences.travelStyle.rawValue)
        - Interests: \(preferences.interests.map(\.rawValue).joined(separator: ", "))
        - Pace: \(preferences.pace.rawValue)
        \(preferences.specialRequests.isEmpty ? "" : "- Special Requests: \(preferences.specialRequests)")

        REQUIREMENTS:
        1. Create realistic daily schedule with specific times
        2. Use ACTUAL trip dates (\(startDateString) to \(endDateString)) in ISO 8601 format
        3. Include mix of activities based on preferences
        4. Consider travel time between locations
        5. Include meal recommendations and detailed descriptions

        RESPOND WITH ONLY THIS JSON STRUCTURE (no other text):
        {
          "tripTitle": "\(duration)-Day \(destination) Itinerary",
          "destination": "\(destination)",
          "detectedTimeZone": "appropriate timezone",
          "items": [
            {
              "title": "Activity name",
              "content": "Detailed description with why it's recommended",
              "activityType": "food|activity|sightseeing|accommodation|transportation|shopping|note|photo",
              "dateTime": "\(exampleDate)",
              "location": {
                "name": "Location name",
                "address": "Full address when possible",
                "latitude": 12.345,
                "longitude": 67.890,
                "city": "\(destination.components(separatedBy: ",").first ?? destination)",
                "country": "Country name"
              },
              "estimatedDuration": 7200,
              "confidence": 1.0,
              "originalText": null
            }
          ]
        }

        CRITICAL: All dateTime values must be within the trip dates (\(startDateString) to \(endDateString)). Use ISO 8601 format with timezone.
        Create a realistic, enjoyable itinerary that matches the user's preferences and provides great local experiences.
        """
    }
    
    // MARK: - Request Creation
    
    private func createVisionRequest(prompt: String, imageData: Data) -> OpenRouterRequest {
        let base64Image = imageData.base64EncodedString()
        
        return OpenRouterRequest(
            model: config.preferredModel.rawValue,
            messages: [
                OpenRouterMessage(
                    role: "user",
                    content: [
                        MessageContent(type: "text", text: prompt, imageUrl: nil),
                        MessageContent(type: "image_url", text: nil, imageUrl: MessageContent.ImageURL(url: "data:image/jpeg;base64,\(base64Image)"))
                    ]
                )
            ],
            maxTokens: config.maxTokens * 2,
            temperature: config.temperature,
            responseFormat: OpenRouterRequest.ResponseFormat()
        )
    }
    
    private func createTextRequest(prompt: String) -> OpenRouterRequest {
        return OpenRouterRequest(
            model: config.preferredModel.rawValue,
            messages: [
                OpenRouterMessage(
                    role: "user",
                    content: [MessageContent(type: "text", text: prompt, imageUrl: nil)]
                )
            ],
            maxTokens: config.maxTokens * 3, // Increased to 6000 tokens for complex itineraries
            temperature: config.temperature,
            responseFormat: OpenRouterRequest.ResponseFormat()
        )
    }
    
    // MARK: - HTTP Request Handling

    private func sendRequest(_ request: OpenRouterRequest) async -> Result<String, AIItineraryError> {
        do {
            // Extract prompt from request
            let prompt = request.messages.first?.content.first(where: { $0.type == "text" })?.text ?? ""

            // Check if request includes an image
            let imageContent = request.messages.first?.content.first(where: { $0.type == "image_url" })

            let response: String

            if let imageUrl = imageContent?.imageUrl?.url,
               imageUrl.hasPrefix("data:image/jpeg;base64,") {
                // Extract base64 image data
                let base64Image = String(imageUrl.dropFirst("data:image/jpeg;base64,".count))

                // Use vision model endpoint with image
                let service = OpenRouterService.shared
                response = try await service.sendPromptWithImage(
                    prompt,
                    imageBase64: base64Image,
                    model: request.model,
                    maxTokens: request.maxTokens
                )
            } else {
                // Use text-only endpoint
                let service = OpenRouterService.shared
                print("📤 AIItinerary: Requesting \(request.maxTokens) tokens for model \(request.model)")

                // Use longer timeout for large requests (3 minutes for itinerary generation)
                let timeout: TimeInterval = request.maxTokens > 2000 ? 180 : 60

                response = try await service.sendPrompt(
                    prompt,
                    model: request.model,
                    maxTokens: request.maxTokens,
                    timeout: timeout
                )
                print("📥 AIItinerary: Received response length: \(response.count) characters")
                print("📥 AIItinerary: Response preview: \(String(response.prefix(200)))")
            }

            return .success(response)

        } catch {
            // Convert any error to AIItineraryError
            let errorMessage = error.localizedDescription

            if errorMessage.contains("Rate limit") {
                return .failure(.networkError(errorMessage))
            } else if errorMessage.contains("API Error") {
                return .failure(.aiProcessingFailed(errorMessage))
            } else {
                return .failure(.networkError("Request failed: \(errorMessage)"))
            }
        }
    }
    
    // MARK: - Response Parsing
    
    /// Try to parse complete activities from partial JSON response
    /// Returns array of new activities that haven't been parsed yet
    private func tryParsePartialActivities(_ partialResponse: String, parsedCount: Int) -> [ItineraryItem]? {
        // Clean the response
        let cleaned = cleanJSONResponse(partialResponse)

        // Try to extract the items array even if JSON is incomplete
        // Look for "items": [ ... ] (note: the field is called "items" not "activities")
        guard let itemsStart = cleaned.range(of: "\"items\"")?.upperBound,
              let arrayStart = cleaned[itemsStart...].range(of: "[")?.upperBound else {
            print("⚠️ Could not find 'items' array in response")
            return nil
        }

        let itemsString = String(cleaned[arrayStart...])
        print("🔍 Attempting to parse items from partial JSON (already parsed: \(parsedCount))")

        // Extract complete activity objects (those ending with "},")
        var items: [ItineraryItem] = []
        var currentObject = ""
        var braceCount = 0
        var inString = false
        var escapeNext = false

        for char in itemsString {
            if escapeNext {
                escapeNext = false
                currentObject.append(char)
                continue
            }

            if char == "\\" {
                escapeNext = true
                currentObject.append(char)
                continue
            }

            if char == "\"" {
                inString.toggle()
            }

            // Skip commas and whitespace when we're between objects (braceCount == 0)
            if !inString && braceCount == 0 && (char == "," || char.isWhitespace) {
                continue
            }

            currentObject.append(char)

            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1

                    // Found a complete object
                    if braceCount == 0 {
                        // Try to parse this activity
                        if let activityData = currentObject.data(using: .utf8) {
                            do {
                                let decoder = createItineraryDecoder()
                                let activity = try decoder.decode(ItineraryItem.self, from: activityData)
                                items.append(activity)
                                print("✅ Successfully parsed activity: \(activity.title)")
                            } catch {
                                print("❌ Failed to parse activity JSON: \(error)")
                                print("   JSON was: \(currentObject.prefix(200))")
                            }
                        }
                        currentObject = ""
                    }
                }
            }
        }

        // Return only new items (those after parsedCount)
        let newItems = Array(items.dropFirst(parsedCount))
        print("📊 Total activities found: \(items.count), New activities: \(newItems.count)")
        return newItems.isEmpty ? nil : newItems
    }

    /// Create a JSONDecoder configured for parsing itinerary data
    private func createItineraryDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        // Custom date decoding strategy that can handle multiple formats
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 first
            let iso8601Formatter = ISO8601DateFormatter()
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try common date formats
            let formatters = [
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd",
                "MM/dd/yyyy",
                "dd/MM/yyyy"
            ].map { format -> DateFormatter in
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                return formatter
            }

            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }

            // If all else fails, return current date
            print("⚠️ AIItinerary: Could not parse date string '\(dateString)', using current date")
            return Date()
        }

        return decoder
    }

    private func parseAIResponse(_ response: String, sourceType: ItinerarySourceType, processingTime: TimeInterval) throws -> ParsedItinerary {
        print("🔍 AIItinerary: Raw AI response: \(response.prefix(500))...")
        
        // Clean the response to extract JSON
        let cleanedResponse = cleanJSONResponse(response)
        print("🧹 AIItinerary: Cleaned response: \(cleanedResponse.prefix(500))...")
        
        guard !cleanedResponse.isEmpty else {
            throw AIItineraryError.parsingFailed("Empty response after cleaning")
        }
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw AIItineraryError.parsingFailed("Failed to convert response to data")
        }
        
        do {
            let decoder = createItineraryDecoder()
            let aiResponse = try decoder.decode(AIItineraryResponse.self, from: data)
            print("✅ AIItinerary: Successfully decoded AI response with \(aiResponse.items.count) items")
            
            // Convert AI response to our itinerary models with error handling
            let items = aiResponse.items.compactMap { aiItem -> ItineraryItem? in
                do {
                    return ItineraryItem(
                        title: aiItem.title.isEmpty ? "Untitled Activity" : aiItem.title,
                        content: aiItem.content,
                        activityType: TripEntryType(rawValue: aiItem.activityType) ?? .note,
                        dateTime: aiItem.dateTime,
                        location: aiItem.location.map { loc in
                            ItineraryLocation(
                                name: loc.name.isEmpty ? "Unknown Location" : loc.name,
                                address: loc.address,
                                latitude: loc.latitude,
                                longitude: loc.longitude,
                                country: loc.country,
                                city: loc.city
                            )
                        },
                        estimatedDuration: aiItem.estimatedDuration,
                        confidence: max(0.0, min(1.0, aiItem.confidence)), // Ensure confidence is between 0 and 1
                        originalText: aiItem.originalText
                    )
                } catch {
                    print("⚠️ AIItinerary: Failed to create ItineraryItem from \(aiItem.title): \(error)")
                    return nil
                }
            }
            
            // Create metadata with safe date handling
            let dates = items.map(\.dateTime)
            let metadata = ItineraryMetadata(
                tripTitle: aiResponse.tripTitle,
                destination: aiResponse.destination,
                detectedTimeZone: aiResponse.detectedTimeZone,
                estimatedStartDate: dates.isEmpty ? nil : dates.min(),
                estimatedEndDate: dates.isEmpty ? nil : dates.max(),
                totalItems: items.count
            )
            
            let processingInfo = ProcessingInfo(
                sourceType: sourceType,
                modelUsed: config.preferredModel.displayName,
                processingTime: processingTime,
                successfullyParsedItems: items.count
            )
            
            return ParsedItinerary(
                items: items,
                metadata: metadata,
                processingInfo: processingInfo
            )
            
        } catch {
            print("❌ AIItinerary: JSON decode error: \(error)")
            print("❌ AIItinerary: Problematic JSON: \(cleanedResponse)")
            throw AIItineraryError.parsingFailed("Failed to decode AI response: \(error.localizedDescription)")
        }
    }
    
    private func cleanJSONResponse(_ response: String) -> String {
        // Remove markdown code blocks and extra text
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Extract JSON from potential surrounding text
        // Find the first { and the matching closing }
        if let firstBrace = cleaned.firstIndex(of: "{") {
            // Count braces to find the matching closing brace
            var braceCount = 0
            var endIndex: String.Index?

            for index in cleaned[firstBrace...].indices {
                let char = cleaned[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = index
                        break
                    }
                }
            }

            if let endIndex = endIndex {
                cleaned = String(cleaned[firstBrace...endIndex])
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AI Response Models

private struct AIItineraryResponse: Codable {
    let tripTitle: String?
    let destination: String?
    let detectedTimeZone: String?
    let items: [AIItineraryItem]
}

private struct AIItineraryItem: Codable {
    let title: String
    let content: String
    let activityType: String
    let dateTime: Date
    let location: AILocation?
    let estimatedDuration: TimeInterval?
    let confidence: Double
    let originalText: String?
}

private struct AILocation: Codable {
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let city: String?
    let country: String?
}

// MARK: - Itinerary Preferences

struct ItineraryPreferences {
    let budget: BudgetLevel
    let travelStyle: TravelStyle
    let interests: [TravelInterest]
    let pace: TravelPace
    let specialRequests: String
    
    enum BudgetLevel: String, CaseIterable {
        case budget = "budget"
        case mid = "mid-range"
        case luxury = "luxury"
        
        var displayName: String {
            switch self {
            case .budget: return "Budget"
            case .mid: return "Mid-range"
            case .luxury: return "Luxury"
            }
        }
    }
    
    enum TravelStyle: String, CaseIterable {
        case cultural = "cultural"
        case adventure = "adventure"
        case relaxation = "relaxation"
        case foodie = "foodie"
        case business = "business"
        case family = "family"
        
        var displayName: String { rawValue.capitalized }
    }
    
    enum TravelInterest: String, CaseIterable {
        case history = "history"
        case art = "art"
        case food = "food"
        case nature = "nature"
        case nightlife = "nightlife"
        case shopping = "shopping"
        case architecture = "architecture"
        case museums = "museums"
        case beaches = "beaches"
        case sports = "sports"
        
        var displayName: String { rawValue.capitalized }
    }
    
    enum TravelPace: String, CaseIterable {
        case relaxed = "relaxed"
        case moderate = "moderate"
        case packed = "packed"
        
        var displayName: String { rawValue.capitalized }
    }
}

// MARK: - Error Types

enum AIItineraryError: Error, LocalizedError {
    case invalidInput(String)
    case imageProcessingFailed(String)
    case aiProcessingFailed(String)
    case parsingFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .imageProcessingFailed(let message):
            return "Image processing failed: \(message)"
        case .aiProcessingFailed(let message):
            return "AI processing failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}