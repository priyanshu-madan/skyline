//
//  UnifiedBoardingPassService.swift
//  SkyLine
//
//  Unified boarding pass parsing service that orchestrates fallback chains
//  between OpenRouter, Apple Intelligence, and Vision Framework
//

import Foundation
import UIKit
import Network

// MARK: - Parsing Configuration
// Note: ParsingMethod is now defined in BoardingPassConfig.swift to avoid duplication

struct ParsingResult {
    let method: ParsingMethod
    let data: BoardingPassData?
    let confidence: Double
    let processingTime: TimeInterval
    let error: String?
    let tokenUsage: Int?
    let estimatedCost: Double?
}

struct UsageStatistics: Codable {
    var totalParsingAttempts: Int = 0
    var successfulParsingsByMethod: [String: Int] = [:]
    var averageProcessingTimeByMethod: [String: Double] = [:]
    var totalTokensUsed: Int = 0
    var estimatedTotalCost: Double = 0.0
    var lastUpdated: Date = Date()
    
    mutating func recordUsage(_ result: ParsingResult) {
        totalParsingAttempts += 1
        
        if result.data != nil {
            let methodKey = result.method.rawValue
            successfulParsingsByMethod[methodKey, default: 0] += 1
        }
        
        // Update average processing time
        let methodKey = result.method.rawValue
        let currentAvg = averageProcessingTimeByMethod[methodKey] ?? 0.0
        let currentCount = successfulParsingsByMethod[methodKey] ?? 0
        
        if currentCount > 0 {
            averageProcessingTimeByMethod[methodKey] = 
                (currentAvg * Double(currentCount - 1) + result.processingTime) / Double(currentCount)
        } else {
            averageProcessingTimeByMethod[methodKey] = result.processingTime
        }
        
        // Record costs and token usage
        if let tokens = result.tokenUsage {
            totalTokensUsed += tokens
        }
        if let cost = result.estimatedCost {
            estimatedTotalCost += cost
        }
        
        lastUpdated = Date()
    }
}

// MARK: - Main Unified Service

@MainActor
class UnifiedBoardingPassService: ObservableObject {
    static let shared = UnifiedBoardingPassService()
    
    @Published var isProcessing = false
    @Published var lastResult: ParsingResult?
    @Published var usageStatistics = UsageStatistics()
    
    private let openRouterService = OpenRouterBoardingPassService.shared
    private let appleIntelligenceService = AppleIntelligenceBoardingPassService.shared
    private let visionService = BoardingPassScanner.shared
    
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    private init() {
        print("🔧 UnifiedBoardingPassService initialized")
        setupNetworkMonitoring()
        loadUsageStatistics()
    }
    
    // MARK: - Public Interface
    
    func parseImage(_ image: UIImage, config: ParsingConfig = ParsingConfig.default) async -> BoardingPassData? {
        print("🚀 Unified: Starting boarding pass parsing with method: \(config.parsingMethod.displayName)")
        
        await MainActor.run {
            isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        // Determine which methods to try
        let methodsToTry = config.enableFallbacks ? config.fallbackOrder : [config.parsingMethod]
        
        for method in methodsToTry {
            if let result = await tryParsingWithMethod(method, image: image, config: config) {
                await MainActor.run {
                    lastResult = result
                    usageStatistics.recordUsage(result)
                }
                saveUsageStatistics()
                
                if let data = result.data {
                    print("✅ Unified: Successfully parsed with \(method.displayName) in \(String(format: "%.2f", result.processingTime))s")
                    print("🔍 Unified: Final BoardingPassData:")
                    print("   ✈️  Flight: \(data.flightNumber ?? "N/A")")
                    print("   🏢 Airline: \(data.airline ?? "N/A")")
                    print("   👤 Passenger: \(data.passengerName ?? "N/A")")
                    print("   🛫 Route: \(data.departureCode ?? "N/A") (\(data.departureCity ?? "N/A")) → \(data.arrivalCode ?? "N/A") (\(data.arrivalCity ?? "N/A"))")
                    print("   🕐 Times: \(data.departureTime ?? "N/A") → \(data.arrivalTime ?? "N/A")")
                    print("   📅 Date: \(data.departureDate?.description ?? "N/A")")
                    print("   💺 Seat: \(data.seat ?? "N/A") | 🚪 Gate: \(data.gate ?? "N/A") | 🏢 Terminal: \(data.terminal ?? "N/A")")
                    print("   🎫 Confirmation: \(data.confirmationCode ?? "N/A")")
                    print("   ✅ Valid: \(data.isValid)")
                    return data
                }
            }
        }
        
        print("❌ Unified: All parsing methods failed")
        return nil
    }
    
    func getSuccessRateForMethod(_ method: ParsingMethod) -> Double {
        let methodKey = method.rawValue
        let successes = usageStatistics.successfulParsingsByMethod[methodKey] ?? 0
        let total = usageStatistics.totalParsingAttempts
        
        guard total > 0 else { return 0.0 }
        return Double(successes) / Double(total)
    }
    
    func resetStatistics() {
        usageStatistics = UsageStatistics()
        saveUsageStatistics()
    }
    
    // MARK: - Private Implementation
    
    private func tryParsingWithMethod(_ method: ParsingMethod, image: UIImage, config: ParsingConfig) async -> ParsingResult? {
        let startTime = Date()
        
        // Check network availability for cloud-based methods
        if method == .openRouter && !isNetworkAvailable {
            print("⚠️ Unified: Skipping OpenRouter due to network unavailability")
            return ParsingResult(
                method: method,
                data: nil,
                confidence: 0.0,
                processingTime: 0.0,
                error: "Network unavailable",
                tokenUsage: nil,
                estimatedCost: nil
            )
        }
        
        var result: BoardingPassData?
        var error: String?
        var tokenUsage: Int?
        var estimatedCost: Double?
        
        do {
            switch method {
            case .openRouter:
                result = await openRouterService.parseImage(image)
                error = openRouterService.lastError
                tokenUsage = openRouterService.lastTokenUsage?.totalTokens
                if let tokens = tokenUsage,
                   let model = openRouterService.lastUsedModel {
                    estimatedCost = Double(tokens) * model.estimatedCostPer1KTokens / 1000.0
                }
                
            case .appleIntelligence:
                result = await appleIntelligenceService.analyzeBoardingPass(from: image)
                error = appleIntelligenceService.lastError
                
            case .visionFramework:
                result = await visionService.scanBoardingPass(from: image)
                error = visionService.lastError
            }
        } catch {
            print("❌ Unified: Error with \(method.displayName): \(error.localizedDescription)")
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        let confidence = result != nil ? 0.8 : 0.0 // Simple confidence estimation
        
        return ParsingResult(
            method: method,
            data: result,
            confidence: confidence,
            processingTime: processingTime,
            error: error,
            tokenUsage: tokenUsage,
            estimatedCost: estimatedCost
        )
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    // MARK: - Statistics Persistence
    
    private func loadUsageStatistics() {
        guard let data = UserDefaults.standard.data(forKey: "UnifiedBoardingPassService.UsageStatistics"),
              let stats = try? JSONDecoder().decode(UsageStatistics.self, from: data) else {
            return
        }
        
        usageStatistics = stats
    }
    
    private func saveUsageStatistics() {
        guard let data = try? JSONEncoder().encode(usageStatistics) else {
            return
        }
        
        UserDefaults.standard.set(data, forKey: "UnifiedBoardingPassService.UsageStatistics")
    }
}

// MARK: - Configuration Models
// Note: ParsingConfig and OpenRouterParsingConfig are now defined in BoardingPassConfig.swift