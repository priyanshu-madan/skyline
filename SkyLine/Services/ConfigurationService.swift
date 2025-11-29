//
//  ConfigurationService.swift
//  SkyLine
//
//  Service for loading and managing boarding pass configuration
//

import Foundation
import CloudKit

class ConfigurationService: ObservableObject {
    static let shared = ConfigurationService()
    
    @Published var config: BoardingPassConfig
    private let cloudKitService = CloudKitService.shared
    private let cacheKey = "cached_boarding_pass_config"
    
    private init() {
        self.config = ConfigurationService.loadDefaultConfig() ?? BoardingPassConfig.default
        loadConfiguration()
    }
    
    // MARK: - Configuration Loading
    
    /// Load configuration from JSON defaults and CloudKit overrides
    private func loadConfiguration() {
        config = Self.loadDefaultConfig() ?? BoardingPassConfig.default
        
        Task {
            await loadCloudKitOverrides()
        }
    }
    
    /// Load default configuration from JSON file
    private static func loadDefaultConfig() -> BoardingPassConfig? {
        guard let path = Bundle.main.path(forResource: "BoardingPassConfig", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(BoardingPassConfig.self, from: data) else {
            print("⚠️ Failed to load BoardingPassConfig.json, using defaults")
            return nil
        }
        
        print("✅ Loaded configuration from JSON file")
        return config
    }
    
    /// Load configuration overrides from CloudKit
    private func loadCloudKitOverrides() async {
        do {
            let predicate = NSPredicate(format: "configType == %@", "BoardingPassConfig")
            let query = CKQuery(recordType: "Configuration", predicate: predicate)
            
            let records = try await cloudKitService.database.records(matching: query)
            
            for result in records.matchResults {
                if let record = try? result.1.get(),
                   let configData = record["configData"] as? String,
                   let data = configData.data(using: .utf8),
                   let override = try? JSONDecoder().decode(BoardingPassConfig.self, from: data) {
                    
                    await MainActor.run {
                        self.config = override
                        self.saveCachedConfig()
                    }
                    print("☁️ Loaded configuration from CloudKit")
                    return
                }
            }
        } catch {
            print("❌ Failed to load configuration from CloudKit: \(error)")
        }
        
        // Try loading from cache if CloudKit fails
        loadCachedConfig()
    }
    
    // MARK: - Configuration Saving
    
    /// Save configuration override to CloudKit
    func saveConfigurationToCloudKit(_ config: BoardingPassConfig) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let configData = try encoder.encode(config)
            guard let configString = String(data: configData, encoding: .utf8) else {
                print("❌ Failed to convert config to string")
                return
            }
            
            let record = CKRecord(recordType: "Configuration")
            record["configType"] = "BoardingPassConfig"
            record["configData"] = configString
            record["lastModified"] = Date()
            
            _ = try await cloudKitService.database.save(record)
            
            await MainActor.run {
                self.config = config
                self.saveCachedConfig()
            }
            
            print("✅ Saved configuration to CloudKit")
        } catch {
            print("❌ Failed to save configuration to CloudKit: \(error)")
        }
    }
    
    // MARK: - Local Caching
    
    private func loadCachedConfig() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(BoardingPassConfig.self, from: data) {
            config = cached
            print("📱 Loaded cached configuration")
        }
    }
    
    private func saveCachedConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            print("💾 Saved configuration to cache")
        }
    }
    
    // MARK: - Configuration Access
    
    /// Get validation pattern for a specific field
    func getValidationPattern(for field: ValidationField) -> String {
        switch field {
        case .flightNumber:
            return config.validationRules.flightNumberPattern
        case .airportCode:
            return config.validationRules.airportCodePattern
        case .seatNumber:
            return config.validationRules.seatNumberPattern
        case .gate:
            return config.validationRules.gatePattern
        }
    }
    
    /// Get error message for a specific validation error
    func getErrorMessage(for error: ValidationError) -> String {
        switch error {
        case .flightNumberInvalid:
            return config.uiConfig.errorMessages.flightNumberInvalid
        case .airportCodeInvalid:
            return config.uiConfig.errorMessages.airportCodeInvalid
        case .airportCodeRequired:
            return config.uiConfig.errorMessages.airportCodeRequired
        case .airportCodeSameAsOther:
            return config.uiConfig.errorMessages.airportCodeSameAsOther
        case .confirmationCodeInvalid:
            return config.uiConfig.errorMessages.confirmationCodeInvalid
        case .seatNumberInvalid:
            return config.uiConfig.errorMessages.seatNumberInvalid
        case .gateInvalid:
            return config.uiConfig.errorMessages.gateInvalid
        case .terminalInvalid:
            return config.uiConfig.errorMessages.terminalInvalid
        case .arrivalBeforeDeparture:
            return config.uiConfig.errorMessages.arrivalBeforeDeparture
        case .flightTooLong:
            return config.uiConfig.errorMessages.flightTooLong
        case .departureTooOld:
            return config.uiConfig.errorMessages.departureTooOld
        }
    }
    
    /// Get placeholder text for a specific field
    func getPlaceholder(for field: PlaceholderField) -> String {
        switch field {
        case .flightNumber:
            return config.uiConfig.placeholders.flightNumber
        case .confirmationCode:
            return config.uiConfig.placeholders.confirmationCode
        case .airline:
            return config.uiConfig.placeholders.airline
        case .departureAirport:
            return config.uiConfig.placeholders.departureAirport
        case .arrivalAirport:
            return config.uiConfig.placeholders.arrivalAirport
        case .departureCity:
            return config.uiConfig.placeholders.departureCity
        case .arrivalCity:
            return config.uiConfig.placeholders.arrivalCity
        case .seat:
            return config.uiConfig.placeholders.seat
        case .gate:
            return config.uiConfig.placeholders.gate
        case .terminal:
            return config.uiConfig.placeholders.terminal
        case .passengerName:
            return config.uiConfig.placeholders.passengerName
        }
    }
    
    /// Get button text
    func getButtonText(for button: ButtonType) -> String {
        switch button {
        case .saveFlightButton:
            return config.uiConfig.buttonText.saveFlightButton
        case .cancelButton:
            return config.uiConfig.buttonText.cancelButton
        case .resetButton:
            return config.uiConfig.buttonText.resetButton
        case .addDateButton:
            return config.uiConfig.buttonText.addDateButton
        case .addTimeButton:
            return config.uiConfig.buttonText.addTimeButton
        }
    }
}

// MARK: - Configuration Enums

enum ValidationField {
    case flightNumber
    case airportCode
    case seatNumber
    case gate
}

enum ValidationError {
    case flightNumberInvalid
    case airportCodeInvalid
    case airportCodeRequired
    case airportCodeSameAsOther
    case confirmationCodeInvalid
    case seatNumberInvalid
    case gateInvalid
    case terminalInvalid
    case arrivalBeforeDeparture
    case flightTooLong
    case departureTooOld
}

enum PlaceholderField {
    case flightNumber
    case confirmationCode
    case airline
    case departureAirport
    case arrivalAirport
    case departureCity
    case arrivalCity
    case seat
    case gate
    case terminal
    case passengerName
}

enum ButtonType {
    case saveFlightButton
    case cancelButton
    case resetButton
    case addDateButton
    case addTimeButton
}