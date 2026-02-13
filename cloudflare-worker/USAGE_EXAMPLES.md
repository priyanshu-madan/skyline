# OpenRouter Service Usage Examples

Examples of how to use the OpenRouter service in your SkyLine iOS app.

## Basic Usage

### Parse Flight Information from Itinerary

```swift
// In UploadItineraryView or BoardingPassConfirmationView
Task {
    do {
        let itineraryText = """
        CONFIRMATION CODE: ABC123
        Flight: AA2453
        From: Los Angeles (LAX)
        To: New York (JFK)
        Date: December 25, 2024
        Departure: 10:30 AM
        Arrival: 6:45 PM
        Duration: 5h 15m
        """

        let result = try await OpenRouterService.shared.parseFlightInfo(itineraryText)
        print("✅ Parsed flight info: \(result)")

        // Parse JSON result and create Flight object
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let flight = createFlightFromJSON(json)
            await flightStore.addFlight(flight)
        }
    } catch OpenRouterError.rateLimitExceeded(let resetAt) {
        print("⚠️ Rate limit hit - resets at \(resetAt)")
        showError("Daily limit reached. Try again tomorrow!")
    } catch {
        print("❌ Error: \(error)")
        showError("Failed to parse itinerary")
    }
}
```

### Generate Travel Suggestions

```swift
// In ProfileView or TripsView
@State private var suggestions: String = ""
@State private var isLoadingSuggestions = false

func loadTravelSuggestions() {
    isLoadingSuggestions = true

    Task {
        do {
            // Get all trip destinations
            let destinations = tripStore.trips.compactMap { $0.destination }

            let result = try await OpenRouterService.shared.generateTravelSuggestions(
                based: destinations
            )

            await MainActor.run {
                suggestions = result
                isLoadingSuggestions = false
            }
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
                print("❌ Failed to generate suggestions: \(error)")
            }
        }
    }
}

// In your View
VStack {
    Button("Get Travel Suggestions") {
        loadTravelSuggestions()
    }

    if isLoadingSuggestions {
        ProgressView()
    } else if !suggestions.isEmpty {
        Text(suggestions)
            .padding()
    }
}
```

### Custom AI Prompts

```swift
// Send any custom prompt
Task {
    let prompt = """
    Analyze this flight pattern and suggest the best frequent flyer program:
    - 10 flights LAX to JFK (American Airlines)
    - 5 flights SFO to ORD (United Airlines)
    - 3 flights LAX to SEA (Alaska Airlines)
    Keep response brief and actionable.
    """

    do {
        let result = try await OpenRouterService.shared.sendPrompt(
            prompt,
            model: "openai/gpt-4o-mini",
            maxTokens: 300
        )

        print("💡 Recommendation: \(result)")
    } catch {
        print("❌ Error: \(error)")
    }
}
```

## Advanced Usage

### Extract Multiple Flights from Long Text

```swift
func extractMultipleFlights(from text: String) async throws -> [Flight] {
    let prompt = """
    Extract all flights from this itinerary and return as JSON array:
    [{
      "flightNumber": "AA123",
      "airline": "American Airlines",
      "departure": "LAX",
      "arrival": "JFK",
      "departureDate": "2024-12-25T10:30:00",
      "arrivalDate": "2024-12-25T18:45:00",
      "duration": "5H 15M"
    }]

    Itinerary:
    \(text)
    """

    let result = try await OpenRouterService.shared.sendPrompt(
        prompt,
        model: "openai/gpt-4o-mini",
        maxTokens: 1500
    )

    // Parse JSON array and create Flight objects
    guard let data = result.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw NSError(domain: "Invalid JSON", code: -1)
    }

    return json.compactMap { createFlightFromJSON($0) }
}
```

### Smart Trip Description Generator

```swift
// Generate engaging trip descriptions
func generateTripDescription(destination: String, dates: String, activities: [String]) async -> String? {
    let prompt = """
    Write a brief, engaging 2-sentence description for a trip:
    Destination: \(destination)
    Dates: \(dates)
    Activities: \(activities.joined(separator: ", "))
    Make it personal and memorable.
    """

    do {
        return try await OpenRouterService.shared.sendPrompt(
            prompt,
            model: "openai/gpt-4o-mini",
            maxTokens: 100
        )
    } catch {
        print("Failed to generate description: \(error)")
        return nil
    }
}
```

### Context-Aware Flight Search

```swift
// Help users find flights based on natural language
func searchFlightsByDescription(_ query: String) async throws -> String {
    let allFlights = flightStore.flights.map { flight in
        "\(flight.flightNumber): \(flight.departure.code) to \(flight.arrival.code) on \(flight.departureDate ?? Date())"
    }.joined(separator: "\n")

    let prompt = """
    User query: "\(query)"

    Available flights:
    \(allFlights)

    Which flight(s) match the user's query? Return just the flight number(s).
    """

    return try await OpenRouterService.shared.sendPrompt(
        prompt,
        model: "openai/gpt-4o-mini",
        maxTokens: 100
    )
}

// Usage:
// "Find my flight to New York in December"
// "Which flight leaves earliest tomorrow?"
```

## Error Handling

### Comprehensive Error Handling

```swift
func handleAIRequest() async {
    do {
        let result = try await OpenRouterService.shared.sendPrompt(
            "Your prompt here"
        )
        // Handle success
        print("✅ Success: \(result)")

    } catch OpenRouterError.rateLimitExceeded(let resetAt) {
        // Rate limit hit - show friendly message
        await MainActor.run {
            showAlert(
                title: "Daily Limit Reached",
                message: "You've used all 100 AI requests for today. Resets at \(formatDate(resetAt))"
            )
        }

    } catch OpenRouterError.apiError(let message) {
        // API error from OpenRouter
        print("❌ API Error: \(message)")
        await MainActor.run {
            showAlert(title: "Error", message: "AI service temporarily unavailable")
        }

    } catch OpenRouterError.invalidURL {
        // Configuration error - wrong worker URL
        print("❌ Invalid worker URL configured")

    } catch OpenRouterError.noResponse {
        // No response from AI
        await MainActor.run {
            showAlert(title: "No Response", message: "AI didn't provide a response")
        }

    } catch {
        // Unknown error
        print("❌ Unknown error: \(error)")
        await MainActor.run {
            showAlert(title: "Error", message: "Something went wrong")
        }
    }
}
```

## Best Practices

### 1. Show Loading States

```swift
@State private var isLoading = false

Button("Parse Itinerary") {
    isLoading = true
    Task {
        defer { isLoading = false }
        // Make AI request
    }
}
.disabled(isLoading)
.overlay {
    if isLoading {
        ProgressView()
    }
}
```

### 2. Cache Results

```swift
// Cache AI results to avoid redundant requests
private var responseCache: [String: String] = [:]

func getCachedOrFetch(_ prompt: String) async throws -> String {
    // Check cache first
    if let cached = responseCache[prompt] {
        return cached
    }

    // Fetch from API
    let result = try await OpenRouterService.shared.sendPrompt(prompt)

    // Cache result
    responseCache[prompt] = result

    return result
}
```

### 3. Timeout Handling

```swift
func sendPromptWithTimeout(_ prompt: String, timeout: TimeInterval = 30) async throws -> String {
    try await withTimeout(seconds: timeout) {
        try await OpenRouterService.shared.sendPrompt(prompt)
    }
}
```

### 4. Batch Processing

```swift
// Process multiple items efficiently
func processMultipleItineraries(_ texts: [String]) async -> [String] {
    await withTaskGroup(of: (Int, String?).self) { group in
        for (index, text) in texts.enumerated() {
            group.addTask {
                do {
                    let result = try await OpenRouterService.shared.parseFlightInfo(text)
                    return (index, result)
                } catch {
                    print("Failed to process item \(index): \(error)")
                    return (index, nil)
                }
            }
        }

        var results: [String?] = Array(repeating: nil, count: texts.count)
        for await (index, result) in group {
            results[index] = result
        }

        return results.compactMap { $0 }
    }
}
```

## Model Selection

### When to Use Each Model

```swift
// Cost-effective for simple tasks
let result = try await OpenRouterService.shared.sendPrompt(
    prompt,
    model: "openai/gpt-4o-mini"  // ~$0.15 per 1M tokens
)

// More capable for complex reasoning
let result = try await OpenRouterService.shared.sendPrompt(
    prompt,
    model: "openai/gpt-4o"  // ~$5 per 1M tokens
)

// For very simple extraction tasks
let result = try await OpenRouterService.shared.sendPrompt(
    prompt,
    model: "openai/gpt-3.5-turbo"  // ~$0.50 per 1M tokens
)
```

## Testing

### Mock Service for Testing

```swift
// Create a mock service for testing
class MockOpenRouterService: OpenRouterService {
    override func sendPrompt(_ prompt: String, model: String, maxTokens: Int) async throws -> String {
        // Return mock response
        return """
        {
          "flightNumber": "TEST123",
          "departure": "LAX",
          "arrival": "JFK"
        }
        """
    }
}

// Use in tests
let mockService = MockOpenRouterService()
```

## Monitoring Usage

```swift
// Track your AI usage
class AIUsageTracker {
    static let shared = AIUsageTracker()

    private(set) var requestCount = 0
    private(set) var tokenCount = 0

    func trackRequest(tokens: Int) {
        requestCount += 1
        tokenCount += tokens

        // Log to analytics
        print("📊 AI Usage - Requests: \(requestCount), Tokens: \(tokenCount)")
    }
}
```

Remember: The free Cloudflare Worker tier gives you 100,000 requests/day, and your rate limit is set to 100 requests per user per day. Adjust these limits based on your needs and budget.
