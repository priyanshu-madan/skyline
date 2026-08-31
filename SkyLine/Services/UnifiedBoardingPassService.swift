//
//  UnifiedBoardingPassService.swift
//  SkyLine
//
//  Orchestrates boarding pass parsing.
//
//  The chain is, in order:
//
//    1. `BoardingPassBarcodeService` - decodes the PDF417/Aztec barcode on the
//       pass and parses the IATA BCBP payload inside it. On device, no model,
//       no network, milliseconds. When it decodes, its fields are authoritative
//       and it short-circuits the rest of the chain.
//    2. `OpenRouterBoardingPassService` - the full fallback, for the common
//       case where the barcode is not IN THE PHOTO at all: a screenshot of the
//       top half of a pass, a photograph of a phone screen at an angle, a
//       confirmation email that never had a barcode. This step UPLOADS THE
//       IMAGE. See `remoteFallbackEnabled`.
//    3. `AppleIntelligenceBoardingPassService` - on-device, last resort, for
//       when there is no network. Its accuracy is not trusted (it is built on
//       Vision text recognition, which the owner has rejected for extraction),
//       so it runs only after the remote step has failed or been skipped.
//
//  Step 1 wins every field it can fill. A language model may never overwrite a
//  checksummed barcode value - see `BoardingPassBarcodeService.overlay`.
//

import Foundation
import UIKit
import Network

// MARK: - Parsing steps

/// A step in the chain.
///
/// `ParsingMethod` lives in `BoardingPassConfig.swift` and describes only the
/// two model-backed methods. The barcode step is not one of them - it is not
/// configurable, not optional and not a model - so it is represented here
/// instead of being bolted onto that enum.
enum BoardingPassParsingStep: Equatable {
    case barcode
    case configured(ParsingMethod)

    /// Stable key for the persisted usage statistics. Must not change: it is
    /// the key in a dictionary that has already been written to disk.
    var key: String {
        switch self {
        case .barcode: return "barcode"
        case .configured(let method): return method.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .barcode: return "Barcode (BCBP)"
        case .configured(let method): return method.displayName
        }
    }
}

struct ParsingResult {
    let step: BoardingPassParsingStep
    let data: BoardingPassData?
    let confidence: Double
    let processingTime: TimeInterval
    let error: String?
    let tokenUsage: Int?
    let estimatedCost: Double?

    /// The model-backed method this result came from, or nil for the barcode
    /// step. Kept so existing callers that reason about `ParsingMethod` still
    /// compile.
    var method: ParsingMethod? {
        if case .configured(let method) = step { return method }
        return nil
    }
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

        let methodKey = result.step.key

        if result.data != nil {
            successfulParsingsByMethod[methodKey, default: 0] += 1
        }
        
        // Update average processing time
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

// MARK: - Default configuration

extension ParsingConfig {

    /// The default the app actually uses.
    ///
    /// Named `onDevice` for what it starts with, not for all of it: the barcode
    /// step ahead of this order is on-device and answers most scans, and only a
    /// photo with no readable barcode reaches `.openRouter`.
    ///
    /// `ParsingConfig.default` in `BoardingPassConfig.swift` names `.openRouter`
    /// as the FIRST and only-considered method, which is what made every scan
    /// an upload. It is not read by this file.
    static let onDevice = ParsingConfig(
        parsingMethod: .openRouter,
        openRouterConfig: OpenRouterParsingConfig.default,
        enableFallbacks: true,
        fallbackOrder: [.openRouter, .appleIntelligence]
    )
}

// MARK: - Enrichment policy

/// How the fields BCBP cannot carry get filled once the barcode HAS decoded:
/// gate, terminal, boarding and departure/arrival times, airline and city
/// display names.
enum BarcodeEnrichmentPolicy: Sendable {

    /// Leave them nil. The saved flight is exactly what the barcode said and
    /// nothing else, and the user fills the rest in by hand.
    case none

    /// On-device Vision text recognition, reading only labelled values off the
    /// card - `GATE A12`, `BOARDING 08:35` - and never a field the barcode
    /// already holds. See `BoardingPassPrintedFieldReader`.
    case onDeviceText

    /// Send the photo to the remote model even though the barcode already
    /// decoded, purely to read the gate and the clock times off it.
    case remote
}

// MARK: - Main Unified Service

@MainActor
class UnifiedBoardingPassService: ObservableObject {
    static let shared = UnifiedBoardingPassService()

    /// Whether a photo with no readable barcode may be sent off the device.
    ///
    /// What this costs when it runs: the photograph of the boarding pass, which
    /// carries the passenger's name, record locator and frequent flyer number,
    /// plus the signed-in user's id, goes to a Cloudflare Worker on the
    /// developer's own account and from there to openrouter.ai and OpenAI.
    ///
    /// What it buys: a flight from a photo that has no barcode in it at all -
    /// a screenshot of the top half of a pass, a confirmation email. That is a
    /// large fraction of what people actually photograph, and the barcode step
    /// cannot help with any of it.
    ///
    /// The ordering is what makes this acceptable: a pass whose barcode is in
    /// frame never reaches this step. Set to `false` to make the app strictly
    /// offline, at the cost of failing on barcode-less images.
    ///
    /// A plain constant rather than a `UserDefaults` value or a launch
    /// argument, for the same reason `DebugFlags` is: a stale setting must not
    /// be able to survive in a simulator's preferences and quietly change what
    /// leaves the device months later.
    nonisolated static let remoteFallbackEnabled = true

    /// How to fill the printed-only fields when the barcode DID decode.
    ///
    /// `.onDeviceText` is the default because it is free, offline, and cannot
    /// touch a barcode field. It is a judgement call worth knowing about: the
    /// owner rejected Vision text recognition as an EXTRACTION engine, and this
    /// is not that - it reads `GATE A12` off a pass whose flight is already
    /// known exactly. `.remote` would be more accurate and would make every
    /// scan an upload, which is the property the chain ordering exists to
    /// avoid. `.none` fills nothing.
    nonisolated static let barcodeEnrichment: BarcodeEnrichmentPolicy = .onDeviceText

    @Published var isProcessing = false
    @Published var lastResult: ParsingResult?
    @Published var usageStatistics = UsageStatistics()

    private let barcodeService = BoardingPassBarcodeService.shared
    private let openRouterService = OpenRouterBoardingPassService.shared
    private let appleIntelligenceService = AppleIntelligenceBoardingPassService.shared
    
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    private init() {
        print("🔧 UnifiedBoardingPassService initialized")
        setupNetworkMonitoring()
        loadUsageStatistics()
    }
    
    // MARK: - Public Interface

    /// Parse a photographed boarding pass.
    ///
    /// - Parameters:
    ///   - image: the photo. It stays on the device unless the barcode step
    ///     fails and `remoteFallbackEnabled` is on - see step 2.
    ///   - config: which model-backed methods may run AFTER the barcode step.
    ///     The barcode step itself is not configurable.
    ///   - referenceDate: "now", used to resolve the barcode's yearless Julian
    ///     flight date. Injected for tests.
    func parseImage(
        _ image: UIImage,
        config: ParsingConfig = .onDevice,
        referenceDate: Date = Date()
    ) async -> BoardingPassData? {
        print("🚀 Unified: Starting boarding pass parsing, barcode first")

        isProcessing = true
        defer { isProcessing = false }

        // A new scan starts with no verdict. Without this the previous attempt's
        // result is still published while this one runs, so the UI can render a
        // stale failure over a scan that is about to succeed.
        lastResult = nil

        // --- Step 1: the barcode. Always, first, regardless of config.
        let barcodeResult = await tryBarcode(image: image, referenceDate: referenceDate)
        // NOT published yet. For a pass that was never checked in there is no
        // barcode to find, so this "failure" is the expected path, not a result
        // worth showing anyone. It is published only if it is the final word.
        let _ = barcodeResult
        usageStatistics.recordUsage(barcodeResult)
        saveUsageStatistics()

        if let data = barcodeResult.data, data.isValid {
            lastResult = barcodeResult
            // Step 3: the printed-only fields. Under `.onDeviceText` they are
            // already in `data`; under `.remote` they cost an upload, so that
            // is a separate, explicit call rather than something that happens
            // by accident.
            if Self.barcodeEnrichment == .remote,
               let enriched = await enrichRemotely(barcodeData: data, image: image, config: config) {
                print("✅ Unified: Parsed from barcode, printed fields from the remote parser")
                logSummary(enriched)
                return enriched
            }

            print("✅ Unified: Parsed from barcode in \(String(format: "%.2f", barcodeResult.processingTime))s - image stayed on the device")
            logSummary(data)
            return data
        }

        // Past this line the barcode did not decode: it is not in frame, the
        // photo is a screenshot of the top half of a pass, or it is an email
        // that never had one. Only a model can read those, and the only model
        // the owner trusts for it is remote.
        print("🔎 Unified: No usable barcode (\(barcodeResult.error ?? "unknown")); falling back to the model chain")

        // --- Steps 2+: model-backed methods, for a pass with no readable code.
        let methodsToTry = config.enableFallbacks ? config.fallbackOrder : [config.parsingMethod]

        for method in methodsToTry {
            guard let result = await tryParsingWithMethod(method, image: image, config: config) else { continue }

            lastResult = result
            usageStatistics.recordUsage(result)
            saveUsageStatistics()

            guard var data = result.data else { continue }

            // Whatever the barcode did manage to read outranks this.
            if let barcodeData = barcodeResult.data {
                data = BoardingPassBarcodeService.overlay(barcode: barcodeData, onto: data)
            }

            data = await Self.enriched(data)
            print("✅ Unified: Parsed with \(method.displayName) in \(String(format: "%.2f", result.processingTime))s")
            logSummary(data)
            return data
        }

        // A partial barcode read still beats nothing: it is exact as far as it
        // goes, and the caller can see which fields are missing.
        if var data = barcodeResult.data {
            data = await Self.enriched(data)
            lastResult = barcodeResult
            print("⚠️ Unified: Returning partial barcode data; no method completed it")
            logSummary(data)
            return data
        }

        // Only now is the scan genuinely a failure, so publish the reason.
        if lastResult?.data == nil { lastResult = barcodeResult }
        print("❌ Unified: All parsing methods failed")
        return nil
    }

    func getSuccessRateForMethod(_ method: ParsingMethod) -> Double {
        successRate(forKey: method.rawValue)
    }

    /// How often the on-device barcode step succeeded. Worth watching: if this
    /// is high, nothing else in the chain needs to exist.
    func getBarcodeSuccessRate() -> Double {
        successRate(forKey: BoardingPassParsingStep.barcode.key)
    }

    private func successRate(forKey key: String) -> Double {
        let successes = usageStatistics.successfulParsingsByMethod[key] ?? 0
        let total = usageStatistics.totalParsingAttempts
        guard total > 0 else { return 0.0 }
        return Double(successes) / Double(total)
    }
    
    func resetStatistics() {
        usageStatistics = UsageStatistics()
        saveUsageStatistics()
    }
    
    // MARK: - Private Implementation

    private func tryBarcode(image: UIImage, referenceDate: Date) async -> ParsingResult {
        let startTime = Date()
        let data = await barcodeService.parseImage(
            image,
            referenceDate: referenceDate,
            includePrintedFields: Self.barcodeEnrichment == .onDeviceText
        )
        let error = barcodeService.lastError

        return ParsingResult(
            step: .barcode,
            data: data,
            // A BCBP parse either matched every mandatory field width or threw.
            // There is nothing probabilistic about it, hence 1.0 rather than
            // the 0.8 the model-backed steps report.
            confidence: data != nil ? 1.0 : 0.0,
            processingTime: Date().timeIntervalSince(startTime),
            error: data != nil ? nil : error,
            tokenUsage: nil,
            estimatedCost: nil
        )
    }

    /// Runs the remote parser over a photo whose barcode ALREADY decoded, to
    /// recover gate, terminal and clock times.
    ///
    /// Only reachable under `barcodeEnrichment == .remote`. The barcode's
    /// fields are reasserted over the answer afterwards, so the model can
    /// contribute the printed values and nothing else.
    private func enrichRemotely(
        barcodeData: BoardingPassData,
        image: UIImage,
        config: ParsingConfig
    ) async -> BoardingPassData? {
        guard let result = await tryParsingWithMethod(.openRouter, image: image, config: config),
              let remote = result.data else {
            return nil
        }
        lastResult = result
        usageStatistics.recordUsage(result)
        saveUsageStatistics()
        return BoardingPassBarcodeService.overlay(barcode: barcodeData, onto: remote)
    }

    private func tryParsingWithMethod(_ method: ParsingMethod, image: UIImage, config: ParsingConfig) async -> ParsingResult? {
        let startTime = Date()

        if method == .openRouter && !Self.remoteFallbackEnabled {
            print("🚫 Unified: Remote fallback is disabled; the image stays on the device")
            return ParsingResult(
                step: .configured(method),
                data: nil,
                confidence: 0.0,
                processingTime: 0.0,
                error: "Remote parsing is disabled",
                tokenUsage: nil,
                estimatedCost: nil
            )
        }

        // Check network availability for cloud-based methods
        if method == .openRouter && !isNetworkAvailable {
            print("⚠️ Unified: Skipping OpenRouter due to network unavailability")
            return ParsingResult(
                step: .configured(method),
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

        switch method {
        case .openRouter:
            // THE IMAGE LEAVES THE DEVICE HERE.
            //
            // A photograph of a boarding pass carries the passenger's name,
            // record locator and frequent flyer number. It goes to a Cloudflare
            // Worker on the developer's personal account
            // (skyline-openrouter-proxy.pmadan-illinois.workers.dev), tagged
            // with the signed-in user's id, and from there to openrouter.ai and
            // OpenAI. Nothing before this line has sent anything anywhere.
            //
            // The trade: this is the only step that can read a pass whose
            // barcode is not in the photo, which is most screenshots and every
            // confirmation email. Step 1 answers the rest without a network.
            print("📤 Unified: UPLOADING the boarding pass image to the remote parser - no barcode was readable")
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
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        let confidence = result != nil ? 0.8 : 0.0 // Simple confidence estimation
        
        return ParsingResult(
            step: .configured(method),
            data: result,
            confidence: confidence,
            processingTime: processingTime,
            error: error,
            tokenUsage: tokenUsage,
            estimatedCost: estimatedCost
        )
    }

    /// Console summary.
    ///
    /// Passenger name and record locator are deliberately absent: they identify
    /// a real person and a real booking, and a device log is not the place for
    /// either.
    private func logSummary(_ data: BoardingPassData) {
        print("🔍 Unified: \(data.flightNumber ?? "N/A") \(data.departureCode ?? "???") → \(data.arrivalCode ?? "???")")
        print("   📅 \(data.departureDate?.description ?? "no date") | 🕐 \(data.departureTime ?? "--:--") → \(data.arrivalTime ?? "--:--")")
        print("   💺 \(data.seat ?? "-") | 🚪 \(data.gate ?? "-") | 🏢 \(data.terminal ?? "-") | valid: \(data.isValid)")
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

    /// Fills the names a code implies: the airline behind "UA323", and the city
    /// behind "PHL".
    ///
    /// Every one of these lookups already existed and none of them were on the
    /// scan path - so a pass that read perfectly still showed "Unknown" for its
    /// airline and nothing at all for its cities, while the app happily
    /// resolved the same codes elsewhere.
    ///
    /// Only ever fills a blank. A barcode carries the carrier designator
    /// directly and a user may have corrected a city by hand; neither should be
    /// overwritten by a lookup.
    static func enriched(_ data: BoardingPassData) async -> BoardingPassData {
        var filled = await fillingAirlineName(in: data)

        if isBlank(filled.departureCity), let code = filled.departureCode, !code.isEmpty {
            filled.departureCity = await AirportService.shared.getAirportInfo(for: code).city
        }
        if isBlank(filled.arrivalCity), let code = filled.arrivalCode, !code.isEmpty {
            filled.arrivalCity = await AirportService.shared.getAirportInfo(for: code).city
        }

        if let from = filled.departureCity, let to = filled.arrivalCity {
            print("🏙️ Unified: Filled cities \(from) → \(to) from airport codes")
        }
        return filled
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("Unknown") == .orderedSame
    }

    /// Derives the airline's name from the flight number when the parse did not
    /// supply one.
    ///
    /// `AirlineService` already maps UA to United Airlines and knows twenty more
    /// besides, but nothing on the remote path ever asked it - the lookup was
    /// wired only to the field's own onChange handler, so it fired when a user
    /// EDITED the flight number and never when a scan produced one. A pass that
    /// read perfectly still showed "Unknown" for its airline.
    ///
    /// A barcode carries the carrier designator directly, so this fills a gap
    /// rather than overriding anything: it runs only when the name is missing.
    static func fillingAirlineName(in data: BoardingPassData) async -> BoardingPassData {
        guard isBlank(data.airline),
              let flightNumber = data.flightNumber, !flightNumber.isEmpty else {
            return data
        }

        guard let name = await AirlineService.shared.getAirlineFromFlightNumber(flightNumber) else {
            return data
        }

        var filled = data
        filled.airline = name
        print("🏢 Unified: Filled airline '\(name)' from flight number \(flightNumber)")
        return filled
    }

}

// MARK: - Configuration Models
// Note: ParsingConfig and OpenRouterParsingConfig are defined in
// BoardingPassConfig.swift. `ParsingConfig.onDevice` above is the default this
// service uses; `ParsingConfig.default` there still names the remote method and
// is not read by this file.
