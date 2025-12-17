//
//  BoardingPassConfig.swift
//  SkyLine
//
//  Configuration system for boarding pass validation and UI
//

import Foundation

// MARK: - Main Configuration Structure

struct BoardingPassConfig: Codable {
    let validationRules: ValidationRules
    let timeFormats: TimeFormats
    let businessRules: BusinessRules
    let uiConfig: UIConfig
    let parsingConfig: ParsingConfig
    
    static let `default` = BoardingPassConfig(
        validationRules: ValidationRules(),
        timeFormats: TimeFormats(),
        businessRules: BusinessRules(),
        uiConfig: UIConfig(),
        parsingConfig: ParsingConfig.default
    )
}

// MARK: - Validation Rules

struct ValidationRules: Codable {
    let flightNumberPattern: String
    let airportCodePattern: String
    let seatNumberPattern: String
    let gatePattern: String
    let confirmationCodeLengthRange: ConfirmationCodeRange
    let terminalMaxLength: Int
    
    init(
        flightNumberPattern: String = "^[A-Z]{2,3}[0-9]{1,4}$",
        airportCodePattern: String = "^[A-Z]{3}$",
        seatNumberPattern: String = "^[0-9]{1,3}[A-Z]$",
        gatePattern: String = "^[A-Z]?[0-9]{1,3}[A-Z]?$",
        confirmationCodeLengthRange: ConfirmationCodeRange = ConfirmationCodeRange(),
        terminalMaxLength: Int = 20
    ) {
        self.flightNumberPattern = flightNumberPattern
        self.airportCodePattern = airportCodePattern
        self.seatNumberPattern = seatNumberPattern
        self.gatePattern = gatePattern
        self.confirmationCodeLengthRange = confirmationCodeLengthRange
        self.terminalMaxLength = terminalMaxLength
    }
}

struct ConfirmationCodeRange: Codable {
    let min: Int
    let max: Int
    
    init(min: Int = 4, max: Int = 8) {
        self.min = min
        self.max = max
    }
}

// MARK: - Time Formats

struct TimeFormats: Codable {
    let supportedInputFormats: [String]
    let outputFormat: String
    let locale: String
    
    init(
        supportedInputFormats: [String] = ["HH:mm", "H:mm", "h:mm a", "hh:mm a"],
        outputFormat: String = "HH:mm",
        locale: String = "en_US_POSIX"
    ) {
        self.supportedInputFormats = supportedInputFormats
        self.outputFormat = outputFormat
        self.locale = locale
    }
}

// MARK: - Business Rules

struct BusinessRules: Codable {
    let maxFlightDurationHours: Int
    let allowPastDatesHours: Int
    let minFlightDurationMinutes: Int
    let autoSuggestionEnabled: Bool
    let realTimeValidationEnabled: Bool
    
    init(
        maxFlightDurationHours: Int = 24,
        allowPastDatesHours: Int = 24,
        minFlightDurationMinutes: Int = 30,
        autoSuggestionEnabled: Bool = true,
        realTimeValidationEnabled: Bool = true
    ) {
        self.maxFlightDurationHours = maxFlightDurationHours
        self.allowPastDatesHours = allowPastDatesHours
        self.minFlightDurationMinutes = minFlightDurationMinutes
        self.autoSuggestionEnabled = autoSuggestionEnabled
        self.realTimeValidationEnabled = realTimeValidationEnabled
    }
}

// MARK: - UI Configuration

struct UIConfig: Codable {
    let placeholders: Placeholders
    let buttonText: ButtonText
    let errorMessages: ErrorMessages
    let hapticFeedbackEnabled: Bool
    
    init(
        placeholders: Placeholders = Placeholders(),
        buttonText: ButtonText = ButtonText(),
        errorMessages: ErrorMessages = ErrorMessages(),
        hapticFeedbackEnabled: Bool = true
    ) {
        self.placeholders = placeholders
        self.buttonText = buttonText
        self.errorMessages = errorMessages
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
    }
}

struct Placeholders: Codable {
    let flightNumber: String
    let confirmationCode: String
    let airline: String
    let departureAirport: String
    let arrivalAirport: String
    let departureCity: String
    let arrivalCity: String
    let seat: String
    let gate: String
    let terminal: String
    let passengerName: String
    
    init(
        flightNumber: String = "WY0153",
        confirmationCode: String = "ABC123",
        airline: String = "OMAN AIR",
        departureAirport: String = "MCT",
        arrivalAirport: String = "ZRH",
        departureCity: String = "Muscat",
        arrivalCity: String = "Zurich",
        seat: String = "12A",
        gate: String = "A12",
        terminal: String = "3",
        passengerName: String = "JOHN DOE"
    ) {
        self.flightNumber = flightNumber
        self.confirmationCode = confirmationCode
        self.airline = airline
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departureCity = departureCity
        self.arrivalCity = arrivalCity
        self.seat = seat
        self.gate = gate
        self.terminal = terminal
        self.passengerName = passengerName
    }
}

struct ButtonText: Codable {
    let saveFlightButton: String
    let cancelButton: String
    let resetButton: String
    let addDateButton: String
    let addTimeButton: String
    
    init(
        saveFlightButton: String = "SAVE FLIGHT",
        cancelButton: String = "CANCEL",
        resetButton: String = "Reset to Original",
        addDateButton: String = "N/A",
        addTimeButton: String = "N/A"
    ) {
        self.saveFlightButton = saveFlightButton
        self.cancelButton = cancelButton
        self.resetButton = resetButton
        self.addDateButton = addDateButton
        self.addTimeButton = addTimeButton
    }
}

struct ErrorMessages: Codable {
    let flightNumberInvalid: String
    let airportCodeInvalid: String
    let airportCodeRequired: String
    let airportCodeSameAsOther: String
    let confirmationCodeInvalid: String
    let seatNumberInvalid: String
    let gateInvalid: String
    let terminalInvalid: String
    let arrivalBeforeDeparture: String
    let flightTooLong: String
    let departureTooOld: String
    
    init(
        flightNumberInvalid: String = "Invalid format (e.g., AA123, WY0153)",
        airportCodeInvalid: String = "Must be 3 letters (e.g., LAX, JFK)",
        airportCodeRequired: String = "Airport code is required",
        airportCodeSameAsOther: String = "Cannot be same as departure",
        confirmationCodeInvalid: String = "Usually 6 alphanumeric characters",
        seatNumberInvalid: String = "Invalid format (e.g., 12A, 3F)",
        gateInvalid: String = "Invalid format (e.g., A12, C3)",
        terminalInvalid: String = "Invalid format (e.g., 1, T2, North)",
        arrivalBeforeDeparture: String = "Arrival must be after departure",
        flightTooLong: String = "Flight duration seems unusually long",
        departureTooOld: String = "Departure date seems too far in the past"
    ) {
        self.flightNumberInvalid = flightNumberInvalid
        self.airportCodeInvalid = airportCodeInvalid
        self.airportCodeRequired = airportCodeRequired
        self.airportCodeSameAsOther = airportCodeSameAsOther
        self.confirmationCodeInvalid = confirmationCodeInvalid
        self.seatNumberInvalid = seatNumberInvalid
        self.gateInvalid = gateInvalid
        self.terminalInvalid = terminalInvalid
        self.arrivalBeforeDeparture = arrivalBeforeDeparture
        self.flightTooLong = flightTooLong
        self.departureTooOld = departureTooOld
    }
}

// MARK: - Parsing Configuration

enum ParsingMethod: String, CaseIterable, Codable {
    case openRouter = "openrouter"
    case appleIntelligence = "apple_intelligence" 
    case visionFramework = "vision_framework"
    
    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter AI"
        case .appleIntelligence: return "Apple Intelligence"
        case .visionFramework: return "Vision Framework"
        }
    }
    
    var description: String {
        switch self {
        case .openRouter: return "Advanced AI models via OpenRouter API"
        case .appleIntelligence: return "On-device Apple Intelligence"
        case .visionFramework: return "Basic OCR text recognition"
        }
    }
}

struct ParsingConfig: Codable {
    let parsingMethod: ParsingMethod
    let openRouterConfig: OpenRouterParsingConfig
    let enableFallbacks: Bool
    let fallbackOrder: [ParsingMethod]
    
    static let `default` = ParsingConfig(
        parsingMethod: .openRouter,
        openRouterConfig: OpenRouterParsingConfig.default,
        enableFallbacks: true,
        fallbackOrder: [.openRouter, .appleIntelligence, .visionFramework]
    )
}

struct OpenRouterParsingConfig: Codable {
    let preferredModel: String
    let maxTokens: Int
    let temperature: Double
    let maxCostPerRequest: Double
    
    static let `default` = OpenRouterParsingConfig(
        preferredModel: "openai/gpt-4o",
        maxTokens: 2000,
        temperature: 0.1,
        maxCostPerRequest: 0.05
    )
}