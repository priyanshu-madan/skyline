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
    private var cancellables = Set<AnyCancellable>()
    private let cloudKitService = CloudKitService.shared
    
    init() {
        loadFlights()
        loadSearchHistory()
        setupAutoSave()
        setupCloudKitSync()
        self.isInitialized = true
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
    func updateFlightCoordinates(_ flightId: String) {
        guard let index = flights.firstIndex(where: { $0.id == flightId }) else { return }
        
        let flight = flights[index]
        let airportService = AirportService.shared
        
        // Get updated coordinates (check the dynamic database)
        let depCoordinate = airportService.getCoordinates(for: flight.departure.code)
        let arrCoordinate = airportService.getCoordinates(for: flight.arrival.code)
        
        // Update coordinates for flight
        
        // Create new Airport instances with updated coordinates
        let updatedDeparture = Airport(
            airport: flight.departure.airport,
            code: flight.departure.code,
            city: flight.departure.city,
            latitude: depCoordinate?.latitude ?? flight.departure.latitude,
            longitude: depCoordinate?.longitude ?? flight.departure.longitude,
            time: flight.departure.time,
            actualTime: flight.departure.actualTime,
            terminal: flight.departure.terminal,
            gate: flight.departure.gate,
            delay: flight.departure.delay
        )
        
        let updatedArrival = Airport(
            airport: flight.arrival.airport,
            code: flight.arrival.code,
            city: flight.arrival.city,
            latitude: arrCoordinate?.latitude ?? flight.arrival.latitude,
            longitude: arrCoordinate?.longitude ?? flight.arrival.longitude,
            time: flight.arrival.time,
            actualTime: flight.arrival.actualTime,
            terminal: flight.arrival.terminal,
            gate: flight.arrival.gate,
            delay: flight.arrival.delay
        )
        
        // Create new Flight instance with updated airports
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
        
        // Flight coordinates updated
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
    
    func removeFlightSync(_ flightId: String) {
        flights.removeAll { $0.id == flightId }
        
        // Clear selection if the removed flight was selected
        if selectedFlight?.id == flightId {
            selectedFlight = nil
        }
        
        saveFlights()
        
        // Sync deletion to CloudKit if available
        if cloudKitAvailable {
            Task {
                let _ = await cloudKitService.deleteFlight(with: flightId)
            }
        }
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Flight removed
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
            // Use CloudKit service's conflict resolution
            let resolvedFlights = cloudKitService.handleConflictResolution(
                localFlights: flights,
                cloudFlights: cloudFlights
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
                date: Date()
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