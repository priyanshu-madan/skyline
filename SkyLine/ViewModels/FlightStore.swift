//
//  FlightStore.swift
//  SkyLine
//
//  Flight data management using ObservableObject pattern
//

import Foundation
import SwiftUI
import Combine
import CloudKit

// MARK: - Flight Store
class FlightStore: ObservableObject {
    // Published properties for UI updates
    @Published var flights: [Flight] = []
    @Published var selectedFlight: Flight?
    @Published var searchHistory: [String] = []
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isInitialized: Bool = false
    @Published var isSyncing: Bool = false
    @Published var cloudKitAvailable: Bool = false
    @Published var lastSyncDate: Date?
    
    // Computed properties
    var flightCount: Int {
        flights.count
    }
    
    var flightsByStatus: [FlightStatus: [Flight]] {
        Dictionary(grouping: flights) { $0.status }
    }
    
    var sortedFlights: [Flight] {
        flights.sorted { first, second in
            // Sort by status priority first, then by departure time
            let statusPriority: [FlightStatus] = [.boarding, .departed, .inAir, .delayed, .landed, .cancelled]
            let firstPriority = statusPriority.firstIndex(of: first.status) ?? statusPriority.count
            let secondPriority = statusPriority.firstIndex(of: second.status) ?? statusPriority.count
            
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }
            
            // If same status, sort by flight number
            return first.flightNumber < second.flightNumber
        }
    }
    
    var upcomingFlights: [Flight] {
        flights.filter { flight in
            [.boarding, .departed, .inAir].contains(flight.status)
        }
    }
    
    var completedFlights: [Flight] {
        flights.filter { flight in
            [.landed].contains(flight.status)
        }
    }
    
    var problemFlights: [Flight] {
        flights.filter { flight in
            [.delayed, .cancelled].contains(flight.status)
        }
    }
    
    var activeFlights: [Flight] {
        flights.filter { $0.isActive }
    }
    
    private let userDefaults = UserDefaults.standard
    private let flightsKey = "saved_flights"
    private let searchHistoryKey = "search_history"
    private let lastSyncKey = "last_sync_date"
    private let deletedFlightsKey = "deleted_flights"
    private var cancellables = Set<AnyCancellable>()
    private let cloudKitService = CloudKitService.shared
    
    // Track deleted flights to prevent re-sync
    private var deletedFlightIds: Set<String> = []
    
    init() {
        loadFlights()
        loadSearchHistory()
        loadDeletedFlights()
        setupAutoSave()
        setupCloudKitSync()
        self.isInitialized = true
        
        // EMERGENCY FIX: Completely disable enhancement to stop infinite loop
        // Only run enhancement once on first app launch
        if !UserDefaults.standard.bool(forKey: "hasRunEnhancement") && false { // DISABLED
            Task {
                await updateAllFlightsWithEnhancedData()
                UserDefaults.standard.set(true, forKey: "hasRunEnhancement")
            }
        }
        
        // Fix flight dates for existing saved flights (run once)
        if !UserDefaults.standard.bool(forKey: "hasFixedFlightDates") {
            Task {
                await fixFlightDates()
                UserDefaults.standard.set(true, forKey: "hasFixedFlightDates")
            }
        }
    }
    
    // MARK: - Flight Management
    
    @MainActor
    func addFlight(_ flight: Flight) async -> Result<String, FlightError> {
        guard !isFlightSaved(flight.id) else {
            return .failure(.duplicateFlight)
        }
        
        setLoading(true)
        
        do {
            // Simulate API call delay
            try await Task.sleep(nanoseconds: 500_000_000)
            
            flights.append(flight)
            saveFlights()
            
            // Sync to CloudKit if available
            if cloudKitAvailable {
                Task {
                    await syncToCloud()
                }
            }
            
            setLoading(false, success: "Flight \(flight.flightNumber) saved successfully")
            
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            return .success(flight.id)
        } catch {
            setLoading(false, error: "Failed to save flight")
            return .failure(.saveFailed)
        }
    }
    
    @MainActor
    func updateAllFlightsWithEnhancedData() async {
        print("🔄 Updating all flights with enhanced airport data...")
        
        // Remove duplicate flights first
        removeDuplicateFlights()
        
        // Force refresh major airports that might have incomplete data
        await refreshMajorAirports()
        
        // Process flights in smaller batches to prevent overwhelming the system
        let batchSize = 2
        for batchStart in stride(from: 0, to: flights.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, flights.count)
            
            for i in batchStart..<batchEnd {
                let flight = flights[i]
                
                // Skip flights with empty airport codes
                guard !flight.departure.code.isEmpty && !flight.arrival.code.isEmpty else {
                    print("⚠️ Skipping flight \(flight.flightNumber) - empty airport codes")
                    continue
                }
                
                // Check if flight already has enhanced data to avoid redundant processing
                if !flight.departure.city.isEmpty && !flight.arrival.city.isEmpty && 
                   flight.departure.city != flight.departure.code && 
                   flight.arrival.city != flight.arrival.code {
                    print("✅ Flight \(flight.flightNumber) already has enhanced data, skipping")
                    continue
                }
                
                // Get enhanced airport information for both departure and arrival
                let airportService = AirportService.shared
                let depInfo = await airportService.getAirportInfo(for: flight.departure.code)
                let arrInfo = await airportService.getAirportInfo(for: flight.arrival.code)
            
            // Create new Airport instances with enhanced information
            let updatedDeparture = Airport(
                airport: depInfo.name ?? flight.departure.airport,
                code: flight.departure.code,
                city: depInfo.city ?? (flight.departure.city.isEmpty ? flight.departure.code : flight.departure.city),
                latitude: depInfo.coordinates?.latitude ?? flight.departure.latitude,
                longitude: depInfo.coordinates?.longitude ?? flight.departure.longitude,
                time: flight.departure.time,
                actualTime: flight.departure.actualTime,
                terminal: flight.departure.terminal,
                gate: flight.departure.gate,
                delay: flight.departure.delay
            )
            
            let updatedArrival = Airport(
                airport: arrInfo.name ?? flight.arrival.airport,
                code: flight.arrival.code,
                city: arrInfo.city ?? (flight.arrival.city.isEmpty ? flight.arrival.code : flight.arrival.city),
                latitude: arrInfo.coordinates?.latitude ?? flight.arrival.latitude,
                longitude: arrInfo.coordinates?.longitude ?? flight.arrival.longitude,
                time: flight.arrival.time,
                actualTime: flight.arrival.actualTime,
                terminal: flight.arrival.terminal,
                gate: flight.arrival.gate,
                delay: flight.arrival.delay
            )
            
            // Create new Flight instance with enhanced airport data
            let updatedFlight = Flight(
                id: flight.id,
                flightNumber: flight.flightNumber,
                airline: flight.airline,
                departure: updatedDeparture,
                arrival: updatedArrival,
                status: flight.status,
                aircraft: flight.aircraft,
                currentPosition: flight.currentPosition,
                progress: flight.progress,
                flightDate: flight.flightDate,
                dataSource: flight.dataSource,
                date: flight.date
            )
            
                flights[i] = updatedFlight
                print("✅ Enhanced flight \(flight.flightNumber): \(updatedDeparture.city) to \(updatedArrival.city)")
            }
            
            // Add delay between batches to prevent overwhelming CloudKit
            if batchEnd < flights.count {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        saveFlights()
        print("🎉 All flights updated with enhanced airport data")
    }
    
    private func removeDuplicateFlights() {
        let uniqueFlights = flights.reduce(into: [String: Flight]()) { result, flight in
            let key = "\(flight.flightNumber)-\(flight.departure.code)-\(flight.arrival.code)-\(DateFormatter.flightCardDate.string(from: flight.date))"
            if result[key] == nil {
                result[key] = flight
            } else {
                print("🗑️ Removing duplicate flight: \(flight.flightNumber)")
            }
        }
        
        flights = Array(uniqueFlights.values)
        print("✅ Removed duplicates, now have \(flights.count) unique flights")
    }
    
    private func refreshMajorAirports() async {
        // Get all unique airport codes from current flights
        var airportCodes = Set<String>()
        for flight in flights {
            if !flight.departure.code.isEmpty {
                airportCodes.insert(flight.departure.code)
            }
            if !flight.arrival.code.isEmpty {
                airportCodes.insert(flight.arrival.code)
            }
        }
        
        let validCodes = Array(airportCodes.filter { !$0.isEmpty })
        print("🔄 Force refreshing airport data for: \(validCodes.sorted())")
        
        // Limit concurrent requests to prevent rate limiting
        let batchSize = 3
        for batch in validCodes.chunked(into: batchSize) {
            await withTaskGroup(of: Void.self) { group in
                for code in batch {
                    group.addTask {
                        print("🔍 Force fetching airport info for \(code)")
                        let _ = await SharedAirportService.shared.getAirportInfo(for: code)
                    }
                }
            }
            
            // Add delay between batches to respect rate limits
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
    
    func debugFlightData() {
        print("🔍 Debug: Current flight data")
        for flight in flights {
            print("Flight \(flight.flightNumber):")
            print("  Departure: \(flight.departure.city) (\(flight.departure.code))")
            print("  Arrival: \(flight.arrival.city) (\(flight.arrival.code))")
            print("  City empty check - Dep: '\(flight.departure.city.isEmpty)', Arr: '\(flight.arrival.city.isEmpty)'")
            print("  Flight date: \(DateFormatter.flightCardDate.string(from: flight.date))")
        }
    }
    
    /// Fix flight dates for existing saved flights that may have incorrect dates
    @MainActor
    func fixFlightDates() {
        print("🔧 Fixing flight dates...")
        var updatedFlights: [Flight] = []
        
        for flight in flights {
            let today = Calendar.current.startOfDay(for: Date())
            let flightDate = Calendar.current.startOfDay(for: flight.date)
            
            // If the flight date is today, try to extract a better date from departure time
            if flightDate == today {
                let properDate = Flight.extractFlightDate(from: flight.departure.time)
                
                // Only update if we get a different date
                if Calendar.current.startOfDay(for: properDate) != today {
                    let updatedFlight = Flight(
                        id: flight.id,
                        flightNumber: flight.flightNumber,
                        airline: flight.airline,
                        departure: flight.departure,
                        arrival: flight.arrival,
                        status: flight.status,
                        aircraft: flight.aircraft,
                        currentPosition: flight.currentPosition,
                        progress: flight.progress,
                        flightDate: flight.flightDate,
                        dataSource: flight.dataSource,
                        date: properDate
                    )
                    updatedFlights.append(updatedFlight)
                    print("✅ Fixed date for flight \(flight.flightNumber): \(DateFormatter.flightCardDate.string(from: properDate))")
                } else {
                    updatedFlights.append(flight)
                }
            } else {
                updatedFlights.append(flight)
            }
        }
        
        flights = updatedFlights
        saveFlights()
        print("🎉 Flight date fixing completed")
    }

    @MainActor
    func updateFlightCoordinates(_ flightId: String) {
        // EMERGENCY FIX: Completely disable this method to stop infinite loop
        print("⚠️ updateFlightCoordinates disabled to prevent infinite loop")
        return
        
        guard let index = flights.firstIndex(where: { $0.id == flightId }) else { return }
        
        let flight = flights[index]
        
        // Check if flight already has enhanced data
        let hasEnhancedData = !flight.departure.city.isEmpty && 
                             !flight.arrival.city.isEmpty && 
                             flight.departure.city != flight.departure.code && 
                             flight.arrival.city != flight.arrival.code
        
        if hasEnhancedData {
            print("✅ Flight \(flight.flightNumber) already has enhanced data, skipping")
            return
        }
        
        Task {
            // Get enhanced airport information including city/country data
            let airportService = AirportService.shared
            let depInfo = await airportService.getAirportInfo(for: flight.departure.code)
            let arrInfo = await airportService.getAirportInfo(for: flight.arrival.code)
            
            await MainActor.run {
                // Create new Airport instances with enhanced information
                let updatedDeparture = Airport(
                    airport: depInfo.name ?? flight.departure.airport,
                    code: flight.departure.code,
                    city: depInfo.city ?? flight.departure.city,
                    latitude: depInfo.coordinates?.latitude ?? flight.departure.latitude,
                    longitude: depInfo.coordinates?.longitude ?? flight.departure.longitude,
                    time: flight.departure.time,
                    actualTime: flight.departure.actualTime,
                    terminal: flight.departure.terminal,
                    gate: flight.departure.gate,
                    delay: flight.departure.delay
                )
                
                let updatedArrival = Airport(
                    airport: arrInfo.name ?? flight.arrival.airport,
                    code: flight.arrival.code,
                    city: arrInfo.city ?? flight.arrival.city,
                    latitude: arrInfo.coordinates?.latitude ?? flight.arrival.latitude,
                    longitude: arrInfo.coordinates?.longitude ?? flight.arrival.longitude,
                    time: flight.arrival.time,
                    actualTime: flight.arrival.actualTime,
                    terminal: flight.arrival.terminal,
                    gate: flight.arrival.gate,
                    delay: flight.arrival.delay
                )
                
                // Create new Flight instance with enhanced airport data
                let updatedFlight = Flight(
                    id: flight.id,
                    flightNumber: flight.flightNumber,
                    airline: flight.airline,
                    departure: updatedDeparture,
                    arrival: updatedArrival,
                    status: flight.status,
                    aircraft: flight.aircraft,
                    currentPosition: flight.currentPosition,
                    progress: flight.progress,
                    flightDate: flight.flightDate,
                    dataSource: flight.dataSource,
                    date: flight.date
                )
                
                flights[index] = updatedFlight
                saveFlights()
                
                print("✅ Updated flight \(flight.flightNumber) with enhanced airport data")
            }
        }
    }
    
    @MainActor
    func removeFlight(_ flightId: String) async -> Result<Void, FlightError> {
        guard isFlightSaved(flightId) else {
            return .failure(.flightNotFound)
        }
        
        flights.removeAll { $0.id == flightId }
        
        // Clear selection if the removed flight was selected
        if selectedFlight?.id == flightId {
            selectedFlight = nil
        }
        
        saveFlights()
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        return .success(())
    }
    
    @MainActor
    func removeFlightSync(_ flightId: String) async {
        flights.removeAll { $0.id == flightId }
        
        // Clear selection if the removed flight was selected
        if selectedFlight?.id == flightId {
            selectedFlight = nil
        }
        
        // Track this deletion to prevent re-sync
        deletedFlightIds.insert(flightId)
        saveDeletedFlights()
        saveFlights()
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Sync deletion to CloudKit if available - wait for completion
        if cloudKitAvailable {
            let result = await cloudKitService.deleteFlight(with: flightId)
            switch result {
            case .success():
                print("✅ Flight \(flightId) deleted from CloudKit")
            case .failure(let error):
                print("❌ Failed to delete \(flightId) from CloudKit: \(error)")
                // TODO: Could implement retry logic here
            }
        }
        
        print("🗑️ Flight \(flightId) removal completed")
    }
    
    func updateFlight(_ flightId: String, with updates: Flight) {
        guard let index = flights.firstIndex(where: { $0.id == flightId }) else { return }
        
        flights[index] = updates
        saveFlights()
        
        // Update selected flight if it matches
        if selectedFlight?.id == flightId {
            selectedFlight = updates
        }
    }
    
    func getFlight(by id: String) -> Flight? {
        flights.first { $0.id == id }
    }
    
    func isFlightSaved(_ flightId: String) -> Bool {
        flights.contains { $0.id == flightId }
    }
    
    func setSelectedFlight(_ flight: Flight?) {
        selectedFlight = flight
    }
    
    func clearAllFlights() {
        flights.removeAll()
        selectedFlight = nil
        
        // Clear the deleted flights tracking since we're starting fresh
        deletedFlightIds.removeAll()
        saveDeletedFlights()
        saveFlights()
        
        // Clear from CloudKit if available
        if cloudKitAvailable {
            Task {
                await syncToCloud() // This will sync the empty flights array
            }
        }
        
        setLoading(false, success: "All flights cleared")
    }
    
    // MARK: - Search History
    
    func addToSearchHistory(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !searchHistory.contains(trimmedQuery) else { return }
        
        searchHistory.insert(trimmedQuery, at: 0)
        
        // Keep only last 10 searches
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }
        
        saveSearchHistory()
    }
    
    func removeFromSearchHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        saveSearchHistory()
    }
    
    func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }
    
    // MARK: - Flight Status Refresh
    
    @MainActor
    func refreshFlightStatuses() async {
        setLoading(true)
        
        do {
            for (index, flight) in flights.enumerated() {
                // Try to get updated flight data from API
                do {
                    let updatedFlights = try await FlightAPIService.shared.searchFlightsByNumber(flight.flightNumber)
                    if let updatedFlight = updatedFlights.first {
                        flights[index] = updatedFlight
                        // Updated flight status
                    }
                } catch {
                    // Failed to refresh flight status
                    // Continue with other flights even if one fails
                }
                
                // Small delay to avoid overwhelming the API
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            saveFlights()
            setLoading(false, success: "Flight statuses updated")
            
        } catch {
            setLoading(false, error: "Failed to refresh flight statuses")
        }
    }
    
    // MARK: - Loading States
    
    private func setLoading(_ loading: Bool, success message: String? = nil, error: String? = nil) {
        isLoading = loading
        
        if let message = message {
            hasError = false
            errorMessage = ""
            // Could show success toast here
        }
        
        if let error = error {
            hasError = true
            errorMessage = error
        }
        
        if !loading && message == nil && error == nil {
            hasError = false
            errorMessage = ""
        }
    }
    
    // MARK: - Persistence
    
    private func saveFlights() {
        do {
            let data = try JSONEncoder().encode(flights)
            userDefaults.set(data, forKey: flightsKey)
        } catch {
            // Failed to save flights
        }
    }
    
    private func loadFlights() {
        guard let data = userDefaults.data(forKey: flightsKey) else {
            // Load sample data for development
            flights = [
                Flight.sample, 
                Flight.sampleInAir, 
                Flight.sampleFigmaDesign, 
                Flight.sampleJakartaDenpasar
            ]
            return
        }
        
        do {
            flights = try JSONDecoder().decode([Flight].self, from: data)
        } catch {
            // Failed to load flights
            flights = []
        }
        
        // Load last sync date
        if let lastSyncData = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = lastSyncData
        }
    }
    
    private func saveSearchHistory() {
        userDefaults.set(searchHistory, forKey: searchHistoryKey)
    }
    
    private func loadSearchHistory() {
        searchHistory = userDefaults.stringArray(forKey: searchHistoryKey) ?? []
    }
    
    private func saveDeletedFlights() {
        let deletedArray = Array(deletedFlightIds)
        userDefaults.set(deletedArray, forKey: deletedFlightsKey)
    }
    
    private func loadDeletedFlights() {
        let deletedArray = userDefaults.stringArray(forKey: deletedFlightsKey) ?? []
        deletedFlightIds = Set(deletedArray)
    }
    
    private func setupAutoSave() {
        // Auto-save when flights change
        $flights
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveFlights()
            }
            .store(in: &cancellables)
        
        // Auto-save when search history changes
        $searchHistory
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSearchHistory()
            }
            .store(in: &cancellables)
    }
    
    private func setupCloudKitSync() {
        // Check CloudKit availability on app launch
        Task {
            let available = await cloudKitService.checkAccountStatus()
            await MainActor.run {
                cloudKitAvailable = available
                if available {
                    // CloudKit available - auto-sync enabled
                } else {
                    // CloudKit not available - using local storage only
                }
            }
            
            // Perform initial sync if CloudKit is available
            if available {
                await performInitialSync()
            }
        }
    }
    
    // MARK: - CloudKit Sync Methods
    
    @MainActor
    func performInitialSync() async {
        guard cloudKitAvailable else { return }
        
        isSyncing = true
        
        // Fetch flights from CloudKit
        let result = await cloudKitService.performFullSync()
        
        switch result {
        case .success(let cloudFlights):
            // Filter out any flights that were explicitly deleted by the user
            let filteredCloudFlights = cloudFlights.filter { !deletedFlightIds.contains($0.id) }
            
            // Use CloudKit service's conflict resolution with filtered flights
            let resolvedFlights = cloudKitService.handleConflictResolution(
                localFlights: flights,
                cloudFlights: filteredCloudFlights
            )
            
            flights = resolvedFlights
            saveFlights() // Save merged data locally
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            
            // Initial sync completed
            
        case .failure(let error):
            // Initial sync failed - continue with local data
            break
        }
        
        // Sync search history
        let searchResult = await cloudKitService.syncSearchHistory(local: searchHistory)
        if case .success(let cloudSearches) = searchResult {
            searchHistory = cloudSearches
            saveSearchHistory()
        }
        
        isSyncing = false
    }
    
    @MainActor
    func syncToCloud() async {
        guard cloudKitAvailable else { return }
        
        isSyncing = true
        
        // Save current flights to CloudKit
        let result = await cloudKitService.saveFlights(flights)
        
        switch result {
        case .success():
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            // Synced flights to CloudKit
            
        case .failure(let error):
            hasError = true
            errorMessage = "Sync failed: \(error.localizedDescription)"
            // CloudKit sync failed
        }
        
        // Sync search history
        let _ = await cloudKitService.saveSearchHistory(searchHistory)
        
        isSyncing = false
    }
    
    @MainActor
    func pullFromCloud() async {
        guard cloudKitAvailable else { return }
        
        isSyncing = true
        
        let result = await cloudKitService.fetchFlights()
        
        switch result {
        case .success(let cloudFlights):
            flights = cloudFlights
            saveFlights()
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            // Pulled flights from CloudKit
            
        case .failure(let error):
            hasError = true
            errorMessage = "Sync failed: \(error.localizedDescription)"
            // CloudKit pull failed
        }
        
        isSyncing = false
    }
    
    // MARK: - API Integration Methods
    
    func searchFlights(query: String) async -> Result<[Flight], FlightError> {
        await MainActor.run {
            setLoading(true)
            addToSearchHistory(query)
        }
        
        do {
            let flights: [Flight]
            
            // Determine if it's a flight number or route search
            if query.contains("to") || query.contains("-") {
                // Route search (e.g., "LAX to JFK" or "LAX-JFK")
                let components = query.uppercased()
                    .replacingOccurrences(of: " TO ", with: "-")
                    .split(separator: "-")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                
                if components.count == 2 {
                    flights = try await FlightAPIService.shared.searchFlightsByRoute(components[0], components[1])
                } else {
                    flights = try await FlightAPIService.shared.searchFlightsByNumber(query)
                }
            } else {
                // Flight number search
                flights = try await FlightAPIService.shared.searchFlightsByNumber(query)
            }
            
            await MainActor.run {
                setLoading(false)
            }
            return .success(flights)
        } catch {
            await MainActor.run {
                setLoading(false, error: "Search failed: \(error.localizedDescription)")
            }
            return .failure(.searchFailed)
        }
    }
    
    @MainActor
    func refreshFlightData() async {
        setLoading(true)
        
        do {
            // Refresh each saved flight by re-searching for it
            var refreshedFlights: [Flight] = []
            
            for flight in flights {
                do {
                    let searchResults = try await FlightAPIService.shared.searchFlightsByNumber(flight.flightNumber)
                    
                    // Find the matching flight and update it
                    if let updatedFlight = searchResults.first(where: { $0.flightNumber == flight.flightNumber }) {
                        // Preserve the original ID to maintain consistency
                        let preservedFlight = Flight(
                            id: flight.id,
                            flightNumber: updatedFlight.flightNumber,
                            airline: updatedFlight.airline,
                            departure: updatedFlight.departure,
                            arrival: updatedFlight.arrival,
                            status: updatedFlight.status,
                            aircraft: updatedFlight.aircraft,
                            currentPosition: updatedFlight.currentPosition,
                            progress: updatedFlight.progress,
                            flightDate: updatedFlight.flightDate,
                            dataSource: updatedFlight.dataSource,
                            date: flight.date
                        )
                        refreshedFlights.append(preservedFlight)
                    } else {
                        // Keep original flight if no update found
                        refreshedFlights.append(flight)
                    }
                } catch {
                    // Keep original flight if refresh fails
                    refreshedFlights.append(flight)
                }
            }
            
            flights = refreshedFlights
            setLoading(false, success: "Flight data refreshed")
        } catch {
            setLoading(false, error: "Refresh failed")
        }
    }
    
    private func generateMockSearchResults(for query: String) -> [Flight] {
        // This would be replaced with actual API calls
        let mockFlights = [
            Flight(
                id: "search-\(query)-1",
                flightNumber: query.uppercased().contains("AA") ? "AA\(Int.random(in: 100...999))" : "\(query.prefix(2).uppercased())\(Int.random(in: 100...999))",
                airline: "Mock Airline",
                departure: Airport(
                    airport: "Mock Departure Airport",
                    code: "LAX",
                    city: "Los Angeles",
                    latitude: 33.9425,
                    longitude: -118.4081,
                    time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                    actualTime: nil,
                    terminal: "2",
                    gate: "A\(Int.random(in: 1...50))",
                    delay: nil
                ),
                arrival: Airport(
                    airport: "Mock Arrival Airport",
                    code: "JFK",
                    city: "New York",
                    latitude: 40.6413,
                    longitude: -73.7781,
                    time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(14400)),
                    actualTime: nil,
                    terminal: "4",
                    gate: "B\(Int.random(in: 1...30))",
                    delay: nil
                ),
                status: FlightStatus.allCases.randomElement() ?? .boarding,
                aircraft: Aircraft(
                    type: "Boeing 737",
                    registration: "N\(Int.random(in: 100...999))XX",
                    icao24: nil
                ),
                currentPosition: nil,
                progress: Double.random(in: 0...1),
                flightDate: ISO8601DateFormatter().string(from: Date()),
                dataSource: .aviationstack,
                date: Flight.extractFlightDate(from: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
            )
        ]
        
        return mockFlights
    }
}

// MARK: - Flight Error Types
enum FlightError: LocalizedError {
    case duplicateFlight
    case flightNotFound
    case saveFailed
    case removeFailed
    case searchFailed
    case networkError
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .duplicateFlight:
            return "Flight is already saved"
        case .flightNotFound:
            return "Flight not found"
        case .saveFailed:
            return "Failed to save flight"
        case .removeFailed:
            return "Failed to remove flight"
        case .searchFailed:
            return "Failed to search flights"
        case .networkError:
            return "Network connection error"
        case .invalidData:
            return "Invalid flight data"
        }
    }
}

// MARK: - Array Extension for Batching
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}