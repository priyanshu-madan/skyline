//
//  OpenRouterService.swift
//  SkyLine
//
//  Secure service for communicating with OpenRouter API via Cloudflare Worker proxy
//

import Foundation

// MARK: - Response Models

struct OpenRouterResponse: Codable {
    let success: Bool
    let data: OpenRouterData?
    let usage: UsageInfo?
    let error: String?
    let message: String?
}

struct OpenRouterData: Codable {
    let id: String
    let model: String
    let choices: [Choice]
    let usage: TokenUsage
}

struct Choice: Codable {
    let message: Message
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct Message: Codable {
    let role: String
    let content: String
}

struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct UsageInfo: Codable {
    let requestsRemaining: Int
    let resetAt: String

    enum CodingKeys: String, CodingKey {
        case requestsRemaining
        case resetAt
    }
}

// MARK: - OpenRouter Service

class OpenRouterService {
    static let shared = OpenRouterService()

    private let workerURL = "https://skyline-openrouter-proxy.pmadan-illinois.workers.dev"

    private init() {}

    /// Send a prompt to OpenRouter API via secure Cloudflare Worker
    /// - Parameters:
    ///   - prompt: The prompt to send to the AI
    ///   - model: The model to use (defaults to gpt-4o-mini)
    ///   - maxTokens: Maximum tokens in response (defaults to 1000)
    /// - Returns: The AI's response text
    func sendPrompt(
        _ prompt: String,
        model: String = "openai/gpt-4o-mini",
        maxTokens: Int = 1000
    ) async throws -> String {
        guard let url = URL(string: workerURL) else {
            throw OpenRouterError.invalidURL
        }

        // Get user ID for rate limiting
        let userId = AuthenticationService.shared.authenticationState.user?.id ?? "anonymous"

        // Prepare request body
        let requestBody: [String: Any] = [
            "prompt": prompt,
            "model": model,
            "userId": userId,
            "maxTokens": maxTokens
        ]

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60 // 60 second timeout

        print("📤 OpenRouter: Sending request to worker...")
        print("📤 OpenRouter: Model: \(model), Tokens: \(maxTokens)")

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        print("📥 OpenRouter: Received response - Status: \(httpResponse.statusCode)")

        // Parse response
        let decoder = JSONDecoder()
        let openRouterResponse = try decoder.decode(OpenRouterResponse.self, from: data)

        // Check for errors
        if !openRouterResponse.success {
            if let error = openRouterResponse.error {
                if error.contains("Rate limit exceeded") {
                    let resetAt = openRouterResponse.usage?.resetAt ?? "unknown"
                    throw OpenRouterError.rateLimitExceeded(resetAt: resetAt)
                }
                throw OpenRouterError.apiError(error)
            }
            throw OpenRouterError.unknownError
        }

        // Extract response text
        guard let data = openRouterResponse.data,
              let firstChoice = data.choices.first else {
            throw OpenRouterError.noResponse
        }

        // Log usage info
        if let usage = openRouterResponse.usage {
            print("✅ OpenRouter: Success - \(usage.requestsRemaining) requests remaining")
            print("💰 OpenRouter: Tokens used - \(data.usage.totalTokens)")
        }

        return firstChoice.message.content
    }

    /// Parse flight information from text using AI
    /// - Parameter text: Itinerary or flight information text
    /// - Returns: Parsed flight data as JSON string
    func parseFlightInfo(_ text: String) async throws -> String {
        let prompt = """
        Extract flight information from the following text and return it as a JSON object.
        Include: flightNumber, airline, departure airport code, arrival airport code, departure date/time, arrival date/time, duration.
        Only return valid JSON, nothing else.

        Text:
        \(text)
        """

        return try await sendPrompt(prompt, model: "openai/gpt-4o-mini", maxTokens: 500)
    }

    /// Generate travel suggestions based on user's trip history
    /// - Parameter trips: Array of trip destinations
    /// - Returns: AI-generated travel suggestions
    func generateTravelSuggestions(based trips: [String]) async throws -> String {
        let destinations = trips.joined(separator: ", ")

        let prompt = """
        Based on someone who has traveled to: \(destinations)
        Suggest 3 new destinations they might enjoy and explain why briefly.
        Keep the response concise and friendly.
        """

        return try await sendPrompt(prompt, model: "openai/gpt-4o-mini", maxTokens: 300)
    }
}

// MARK: - Error Types

enum OpenRouterError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noResponse
    case apiError(String)
    case rateLimitExceeded(resetAt: String)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid worker URL configured"
        case .invalidResponse:
            return "Invalid response from server"
        case .noResponse:
            return "No response from AI"
        case .apiError(let message):
            return "API Error: \(message)"
        case .rateLimitExceeded(let resetAt):
            return "Rate limit exceeded. Resets at \(resetAt)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}
