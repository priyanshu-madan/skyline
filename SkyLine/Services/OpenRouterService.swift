//
//  OpenRouterService.swift
//  SkyLine
//
//  Secure service for communicating with OpenRouter API via Cloudflare Worker proxy
//

import Foundation

// MARK: - Response Models

// Worker-specific response wrapper (from Cloudflare Worker)
struct WorkerResponse: Codable {
    let success: Bool
    let data: WorkerOpenRouterData?
    let usage: WorkerUsageInfo?
    let error: String?
    let message: String?
}

struct WorkerOpenRouterData: Codable {
    let id: String
    let model: String
    let choices: [WorkerChoice]
    let usage: WorkerTokenUsage
}

struct WorkerChoice: Codable {
    let message: WorkerMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct WorkerMessage: Codable {
    let role: String
    let content: String
}

struct WorkerTokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct WorkerUsageInfo: Codable {
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
            throw WorkerError.invalidURL
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
            throw WorkerError.invalidResponse
        }

        print("📥 OpenRouter: Received response - Status: \(httpResponse.statusCode)")

        // Parse response
        let decoder = JSONDecoder()
        let workerResponse = try decoder.decode(WorkerResponse.self, from: data)

        // Check for errors
        if !workerResponse.success {
            if let error = workerResponse.error {
                if error.contains("Rate limit exceeded") {
                    let resetAt = workerResponse.usage?.resetAt ?? "unknown"
                    throw WorkerError.rateLimitExceeded(resetAt: resetAt)
                }
                throw WorkerError.apiError(error)
            }
            throw WorkerError.unknownError
        }

        // Extract response text
        guard let data = workerResponse.data,
              let firstChoice = data.choices.first else {
            throw WorkerError.noResponse
        }

        // Log usage info
        if let usage = workerResponse.usage {
            print("✅ OpenRouter: Success - \(usage.requestsRemaining) requests remaining")
            print("💰 OpenRouter: Tokens used - \(data.usage.totalTokens)")
        }

        return firstChoice.message.content
    }

    /// Send a prompt with an image to OpenRouter API via secure Cloudflare Worker
    /// - Parameters:
    ///   - prompt: The prompt to send to the AI
    ///   - imageBase64: Base64-encoded image data
    ///   - model: The model to use (defaults to gpt-4o for vision)
    ///   - maxTokens: Maximum tokens in response (defaults to 2000)
    /// - Returns: The AI's response text
    func sendPromptWithImage(
        _ prompt: String,
        imageBase64: String,
        model: String = "openai/gpt-4o",
        maxTokens: Int = 2000
    ) async throws -> String {
        guard let url = URL(string: workerURL) else {
            throw WorkerError.invalidURL
        }

        // Get user ID for rate limiting
        let userId = AuthenticationService.shared.authenticationState.user?.id ?? "anonymous"

        // Prepare request body with image
        let requestBody: [String: Any] = [
            "prompt": prompt,
            "model": model,
            "userId": userId,
            "maxTokens": maxTokens,
            "imageBase64": imageBase64
        ]

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120 // 2 minutes for vision models

        print("📤 OpenRouter: Sending image request to worker...")
        print("📤 OpenRouter: Model: \(model), Tokens: \(maxTokens)")

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse
        }

        print("📥 OpenRouter: Received response - Status: \(httpResponse.statusCode)")

        // Parse response
        let decoder = JSONDecoder()
        let workerResponse = try decoder.decode(WorkerResponse.self, from: data)

        // Check for errors
        if !workerResponse.success {
            if let error = workerResponse.error {
                if error.contains("Rate limit exceeded") {
                    let resetAt = workerResponse.usage?.resetAt ?? "unknown"
                    throw WorkerError.rateLimitExceeded(resetAt: resetAt)
                }
                throw WorkerError.apiError(error)
            }
            throw WorkerError.unknownError
        }

        // Extract response text
        guard let data = workerResponse.data,
              let firstChoice = data.choices.first else {
            throw WorkerError.noResponse
        }

        // Log usage info
        if let usage = workerResponse.usage {
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

// Worker-specific errors
enum WorkerError: LocalizedError {
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
