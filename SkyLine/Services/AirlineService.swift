//
//  AirlineService.swift
//  SkyLine
//
//  Service for managing airline data with dynamic fetching and caching
//

import Foundation
import CloudKit

class AirlineService: ObservableObject {
    static let shared = AirlineService()
    
    @Published var airlines: [String: Airline] = [:]  // Code -> Airline mapping
    @Published var isLoading = false
    @Published var lastError: String?
    
    private let cloudKitService = CloudKitService.shared
    private let cacheKey = "cached_airlines"
    
    private init() {
        loadCachedAirlines()
    }
    
    // MARK: - Public Interface
    
    /// Get airline name from airline code, with dynamic fetching if not found
    func getAirline(for code: String) async -> Airline? {
        let cleanCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Check local cache first
        if let cachedAirline = airlines[cleanCode] {
            print("✈️ Found cached airline: \(cleanCode) -> \(cachedAirline.name)")
            return cachedAirline
        }
        
        // Try to fetch from CloudKit
        if let cloudAirline = await fetchAirlineFromCloudKit(code: cleanCode) {
            await MainActor.run {
                airlines[cleanCode] = cloudAirline
                saveCachedAirlines()
            }
            print("☁️ Fetched from CloudKit: \(cleanCode) -> \(cloudAirline.name)")
            return cloudAirline
        }
        
        // Try to fetch from external API
        if let apiAirline = await fetchAirlineFromAPI(code: cleanCode) {
            // Save to CloudKit for future use
            await saveAirlineToCloudKit(apiAirline)
            
            await MainActor.run {
                airlines[cleanCode] = apiAirline
                saveCachedAirlines()
            }
            print("🌐 Fetched from API: \(cleanCode) -> \(apiAirline.name)")
            return apiAirline
        }
        
        print("⚠️ Could not find airline for code: \(cleanCode)")
        return nil
    }
    
    /// Get airline name from flight number (extracts code first)
    func getAirlineFromFlightNumber(_ flightNumber: String) async -> String? {
        let cleanFlightNumber = flightNumber.uppercased().trimmingCharacters(in: .whitespaces)
        print("🔍 DEBUG: Looking up airline for flight number: '\(flightNumber)' (cleaned: '\(cleanFlightNumber)')")
        
        // Extract airline code patterns
        let possibleCodes = extractAirlineCodes(from: cleanFlightNumber)
        print("🔍 DEBUG: Extracted possible airline codes: \(possibleCodes)")
        
        for code in possibleCodes {
            print("🔍 DEBUG: Trying airline code: '\(code)'")
            if let airline = await getAirline(for: code) {
                print("✅ DEBUG: Found airline: \(code) -> \(airline.name)")
                return airline.name
            } else {
                print("❌ DEBUG: No airline found for code: '\(code)'")
            }
        }
        
        print("⚠️ DEBUG: No airline found for any codes from flight number: \(flightNumber)")
        return nil
    }
    
    // MARK: - CloudKit Operations
    
    private func fetchAirlineFromCloudKit(code: String) async -> Airline? {
        let predicate = NSPredicate(format: "code == %@", code)
        let query = CKQuery(recordType: "Airline", predicate: predicate)
        
        do {
            let records = try await cloudKitService.database.records(matching: query)
            if let record = try records.matchResults.first?.1.get() {
                return Airline(from: record)
            }
        } catch {
            print("❌ CloudKit fetch error for airline \(code): \(error)")
        }
        
        return nil
    }
    
    private func saveAirlineToCloudKit(_ airline: Airline) async {
        do {
            let record = airline.toCKRecord()
            _ = try await cloudKitService.database.save(record)
            print("✅ Saved airline to CloudKit: \(airline.code) -> \(airline.name)")
        } catch {
            print("❌ Failed to save airline to CloudKit: \(error)")
        }
    }
    
    // MARK: - External API Fetching
    
    private func fetchAirlineFromAPI(code: String) async -> Airline? {
        // Using aviation-reference-data API for airline lookups
        guard let url = URL(string: "https://aviation-reference-data.p.rapidapi.com/airlines/\(code)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Note: You would need to add your RapidAPI key to Info.plist or environment
        if let apiKey = Bundle.main.infoDictionary?["AVIATION_API_KEY"] as? String {
            request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
            request.setValue("aviation-reference-data.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        } else {
            print("⚠️ Aviation API key not configured, using fallback mapping")
            return getFallbackAirline(for: code)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ Aviation API request failed, using fallback")
                return getFallbackAirline(for: code)
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {
                
                let icaoCode = json["icao"] as? String
                let country = json["country"] as? String
                
                return Airline(
                    code: code,
                    name: name,
                    icaoCode: icaoCode,
                    country: country,
                    isActive: true
                )
            }
            
        } catch {
            print("❌ Aviation API error: \(error)")
        }
        
        // Fallback to known mappings
        return getFallbackAirline(for: code)
    }
    
    // MARK: - Fallback Mapping
    
    private func getFallbackAirline(for code: String) -> Airline? {
        // Common airline mappings as fallback
        let fallbackMappings: [String: (name: String, country: String?)] = [
            "6E": ("IndiGo", "India"),
            "AI": ("Air India", "India"),
            "UA": ("United Airlines", "United States"),
            "AA": ("American Airlines", "United States"),
            "DL": ("Delta Air Lines", "United States"),
            "SG": ("SpiceJet", "India"),
            "UK": ("Vistara", "India"),
            "EK": ("Emirates", "UAE"),
            "QR": ("Qatar Airways", "Qatar"),
            "WY": ("Oman Air", "Oman"),
            "SQ": ("Singapore Airlines", "Singapore"),
            "LH": ("Lufthansa", "Germany"),
            "BA": ("British Airways", "United Kingdom"),
            "AF": ("Air France", "France"),
            "KL": ("KLM", "Netherlands"),
            "TK": ("Turkish Airlines", "Turkey"),
            "CX": ("Cathay Pacific", "Hong Kong"),
            "JL": ("Japan Airlines", "Japan"),
            "NH": ("ANA", "Japan"),
            "AC": ("Air Canada", "Canada"),
            "QF": ("Qantas", "Australia")
        ]
        
        if let mapping = fallbackMappings[code] {
            return Airline(
                code: code,
                name: mapping.name,
                country: mapping.country,
                isActive: true
            )
        }
        
        return nil
    }
    
    // MARK: - Code Extraction
    
    private func extractAirlineCodes(from flightNumber: String) -> [String] {
        var codes: [String] = []
        
        // Try 2-letter codes first (most common)
        if flightNumber.count >= 2 {
            let twoLetterCode = String(flightNumber.prefix(2))
            codes.append(twoLetterCode)
        }
        
        // Try 3-letter codes
        if flightNumber.count >= 3 {
            let threeLetterCode = String(flightNumber.prefix(3))
            codes.append(threeLetterCode)
        }
        
        // Try digit+letter patterns (like 6E)
        if flightNumber.count >= 2 {
            let pattern = String(flightNumber.prefix(2))
            if pattern.first?.isNumber == true && pattern.last?.isLetter == true {
                codes.insert(pattern, at: 0) // Prioritize this pattern
            }
        }
        
        return codes
    }
    
    // MARK: - Caching
    
    private func loadCachedAirlines() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: Airline].self, from: data) {
            airlines = cached
            print("📱 Loaded \(cached.count) cached airlines:")
            for (code, airline) in cached {
                print("   \(code) -> \(airline.name)")
            }
        } else {
            print("📱 No cached airlines found")
        }
    }
    
    private func saveCachedAirlines() {
        if let data = try? JSONEncoder().encode(airlines) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            print("💾 Saved \(airlines.count) airlines to cache")
        }
    }
    
    // MARK: - Bulk Operations
    
    /// Seed initial airline data (call once during app setup)
    func seedInitialAirlines() async {
        await MainActor.run {
            isLoading = true
        }
        
        let initialAirlines = [
            Airline(code: "6E", name: "IndiGo", icaoCode: "IGO", country: "India"),
            Airline(code: "AI", name: "Air India", icaoCode: "AIC", country: "India"),
            Airline(code: "UA", name: "United Airlines", icaoCode: "UAL", country: "United States"),
            Airline(code: "AA", name: "American Airlines", icaoCode: "AAL", country: "United States"),
            Airline(code: "DL", name: "Delta Air Lines", icaoCode: "DAL", country: "United States"),
            Airline(code: "SG", name: "SpiceJet", icaoCode: "SEJ", country: "India"),
            Airline(code: "UK", name: "Vistara", icaoCode: "VTI", country: "India"),
            Airline(code: "EK", name: "Emirates", icaoCode: "UAE", country: "UAE"),
            Airline(code: "QR", name: "Qatar Airways", icaoCode: "QTR", country: "Qatar"),
            Airline(code: "SQ", name: "Singapore Airlines", icaoCode: "SIA", country: "Singapore"),
        ]
        
        for airline in initialAirlines {
            // Only seed if not already exists
            if airlines[airline.code] == nil {
                await saveAirlineToCloudKit(airline)
                await MainActor.run {
                    airlines[airline.code] = airline
                }
            }
        }
        
        await MainActor.run {
            saveCachedAirlines()
            isLoading = false
        }
        
        print("🌱 Seeded \(initialAirlines.count) initial airlines")
    }
}