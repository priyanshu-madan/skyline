//
//  BottomSheetContentView.swift
//  SkyLine
//
//  Content for the bottom sheet using BottomSheetSwiftUI library
//

import SwiftUI
import BottomSheet
import PhotosUI

struct BottomSheetContentView: View {
    @Binding var sheetPosition: BottomSheetPosition
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingBoardingPassConfirmation = false
    @State private var scannedBoardingPassData: BoardingPassData?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [Flight] = []
    @State private var searchError: String?
    
    var body: some View {
        Group {
            if sheetPosition == .absolute(120) {
                // Collapsed state - show minimal content with profile on right
                collapsedStateView
            } else {
                // Expanded state - show full content
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with Profile (Expanded State Content)
                        expandedHeaderView
                
                // Add Flight Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Add Flight")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Spacer()
                    }
                    
                    // OCR Boarding Pass Scanner
                    Button(action: { 
                        showingPhotoPicker = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Boarding Pass")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                Text("From Apple Wallet screenshot")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [themeManager.currentTheme.colors.primary, themeManager.currentTheme.colors.primary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    
                    // OR Divider
                    HStack {
                        Rectangle()
                            .fill(themeManager.currentTheme.colors.textSecondary.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .padding(.horizontal, 12)
                        
                        Rectangle()
                            .fill(themeManager.currentTheme.colors.textSecondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    
                    // Manual Search
                    VStack(spacing: 12) {
                        TextField("Enter flight number (e.g., AA123)", text: $searchText)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeManager.currentTheme.colors.primary.opacity(0.3), lineWidth: 1)
                            )
                            .onSubmit {
                                if !searchText.isEmpty {
                                    performFlightSearch()
                                }
                            }
                        
                        Button("Search Flights") {
                            performFlightSearch()
                        }
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(searchText.isEmpty ? themeManager.currentTheme.colors.textSecondary : themeManager.currentTheme.colors.success)
                        .cornerRadius(8)
                        .disabled(searchText.isEmpty || isSearching)
                        
                        // Search Status
                        if isSearching {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                
                                Text("Searching for flights...")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .cornerRadius(8)
                        }
                        
                        // Search Error
                        if let error = searchError {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.error)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Search Failed")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.error)
                                    Text(error)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .cornerRadius(8)
                        }
                        
                        // Search Results
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Search Results")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                ForEach(searchResults) { flight in
                                    SearchResultCard(flight: flight) {
                                        Task {
                                            // Ensure coordinates are available before saving
                                            let flightWithCoords = await ensureFlightCoordinates(flight)
                                            
                                            let _ = await flightStore.addFlight(flightWithCoords)
                                            searchResults.removeAll()
                                            searchText = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // My Flights Section
                VStack(spacing: 16) {
                    HStack {
                        Text("My Flights")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Spacer()
                    }
                    
                    if flightStore.flights.isEmpty {
                        VStack(spacing: 16) {
                            Text("🛫")
                                .font(.system(size: 48))
                            
                            Text("No saved flights")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            
                            Text("Search for flights and save them here to track their status")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(flightStore.sortedFlights) { flight in
                                CompactFlightRowView(flight: flight) {
                                    // Focus on flight in globe
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Settings Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Spacer()
                    }
                    
                    // Theme Toggle
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: themeManager.currentTheme == .light ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance")
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                Text("Current: \(themeManager.currentTheme.displayName)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            themeManager.toggleTheme()
                        }) {
                            Text("Toggle")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(themeManager.currentTheme.colors.primary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                        // Spacer for bottom safe area
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .background(.clear)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { newItem in
            if let newItem = newItem {
                handleSelectedPhoto(newItem)
                selectedPhotoItem = nil
            }
        }
        .sheet(isPresented: $showingBoardingPassConfirmation) {
            if let boardingPassData = scannedBoardingPassData {
                BoardingPassConfirmationView(
                    boardingPassData: boardingPassData,
                    onConfirm: { confirmedData in
                        Task {
                            await createFlightFromBoardingPass(confirmedData)
                            await MainActor.run {
                                showingBoardingPassConfirmation = false
                                scannedBoardingPassData = nil
                            }
                        }
                    },
                    onCancel: {
                        showingBoardingPassConfirmation = false
                        scannedBoardingPassData = nil
                    }
                )
                .environmentObject(themeManager)
            }
        }
    }
    
    // MARK: - Collapsed State View
    
    private var collapsedStateView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Flight count and "Add Flight" text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(flightStore.flightCount) flights")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text("Tap to add more flights")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                Spacer()
                
                // Profile Picture on the right
                Circle()
                    .fill(themeManager.currentTheme.colors.primary.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Group {
                            if let user = authService.authenticationState.user {
                                Text(user.initials)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                            }
                        }
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Ensure minimum height for collapsed state
            Spacer(minLength: 20)
        }
        .frame(minHeight: 80) // Ensure minimum height
    }
    
    // MARK: - Expanded Header View
    
    private var expandedHeaderView: some View {
        HStack(spacing: 16) {
            // Profile Picture
            Circle()
                .fill(themeManager.currentTheme.colors.primary.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Group {
                        if let user = authService.authenticationState.user {
                            Text(user.initials)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 24, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                    }
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(authService.authenticationState.user?.displayName ?? "SkyLine Pilot")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("\(flightStore.flightCount) saved flights")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Helper Functions (same as original)
    
    private func ensureFlightCoordinates(_ flight: Flight) async -> Flight {
        let airportService = AirportService.shared
        
        // Check if coordinates are missing and fetch them
        let depCode = flight.departure.code
        let arrCode = flight.arrival.code
        
        print("🔍 Ensuring coordinates for \(depCode) → \(arrCode)")
        
        // Use async coordinate fetching to ensure we have coordinates
        let depCoordinate = await airportService.getCoordinatesAsync(for: depCode)
        let arrCoordinate = await airportService.getCoordinatesAsync(for: arrCode)
        
        print("✅ Coordinate fetching completed for \(flight.flightNumber)")
        
        // Create updated flight with coordinates
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
        
        return Flight(
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
    }
    
    private func performFlightSearch() {
        guard !searchText.isEmpty else { return }
        
        Task {
            await MainActor.run {
                isSearching = true
                searchError = nil
                searchResults.removeAll()
            }
            
            do {
                let results = try await FlightAPIService.shared.searchFlightsByNumber(searchText.uppercased())
                
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                    
                    if results.isEmpty {
                        searchError = "No flights found for '\(searchText)'"
                    }
                }
                
                print("✅ Search completed:", results.count, "flights found")
                
            } catch {
                await MainActor.run {
                    searchError = error.localizedDescription
                    isSearching = false
                }
                print("❌ Search failed:", error)
            }
        }
    }
    
    private func handleSelectedPhoto(_ photoItem: PhotosPickerItem) {
        Task {
            await MainActor.run {
                isSearching = true
                searchError = nil
                print("📸 Starting photo processing...")
            }
            
            do {
                guard let data = try await photoItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    await MainActor.run {
                        searchError = "Failed to load selected image"
                        isSearching = false
                    }
                    return
                }
                
                print("📸 Image loaded successfully, size: \(uiImage.size)")
                
                // Perform OCR on the image
                guard let boardingPassData = await BoardingPassScanner.shared.scanBoardingPass(from: uiImage) else {
                    await MainActor.run {
                        searchError = "Could not extract flight details from boarding pass. Please try a clearer image or enter flight details manually."
                        isSearching = false
                    }
                    return
                }
                
                // Show confirmation sheet with parsed data
                await MainActor.run {
                    print("📋 Setting up confirmation sheet with data:", boardingPassData.summary)
                    scannedBoardingPassData = boardingPassData
                    showingBoardingPassConfirmation = true
                    isSearching = false
                    print("📋 Confirmation sheet should now show:", showingBoardingPassConfirmation)
                }
                
            } catch {
                await MainActor.run {
                    searchError = "Failed to scan boarding pass: \(error.localizedDescription)"
                    isSearching = false
                }
                print("❌ OCR scanning failed:", error)
            }
        }
    }
    
    @MainActor
    private func createFlightFromBoardingPass(_ boardingPassData: BoardingPassData) async {
        guard let flightNumber = boardingPassData.flightNumber,
              let depCode = boardingPassData.departureCode,
              let arrCode = boardingPassData.arrivalCode else {
            print("❌ Invalid boarding pass data - missing required fields")
            return
        }
        
        // Create flight from boarding pass data
        let flight = Flight(
            id: UUID().uuidString,
            flightNumber: flightNumber,
            airline: String(flightNumber.prefix(2)), // Extract airline from flight number
            departure: Airport(
                airport: depCode, // Will be enhanced with real airport names later
                code: depCode,
                city: depCode, // Use airport code as city for now
                latitude: nil, // Will be populated by AirportService
                longitude: nil,
                time: boardingPassData.departureTime ?? "",
                actualTime: "", // Default empty
                terminal: boardingPassData.terminal ?? "",
                gate: boardingPassData.gate ?? "",
                delay: 0 // Default no delay
            ),
            arrival: Airport(
                airport: arrCode, // Will be enhanced with real airport names later
                code: arrCode,
                city: arrCode, // Use airport code as city for now
                latitude: nil, // Will be populated by AirportService
                longitude: nil,
                time: boardingPassData.arrivalTime ?? "",
                actualTime: "", // Default empty
                terminal: "",
                gate: "",
                delay: 0 // Default no delay
            ),
            status: .boarding,
            aircraft: Aircraft(type: "", registration: "", icao24: ""),
            currentPosition: nil, // No current position for boarding pass
            progress: 0.0, // Default progress
            flightDate: nil, // No specific date
            dataSource: .manual, // User-entered data
            date: Calendar.current.startOfDay(for: Date())
        )
        
        // Add coordinates using AirportService
        let airportService = AirportService.shared
        
        // Get coordinates for airports
        print("🔍 Fetching coordinates for \(depCode) → \(arrCode)")
        let depCoordinate = await airportService.getCoordinatesAsync(for: depCode)
        let arrCoordinate = await airportService.getCoordinatesAsync(for: arrCode)
        
        // Create new Airport instances with coordinates
        let updatedDeparture = Airport(
            airport: depCode,
            code: depCode,
            city: depCode, // Use airport code as city for now
            latitude: depCoordinate?.latitude,
            longitude: depCoordinate?.longitude,
            time: boardingPassData.departureTime ?? "",
            actualTime: "",
            terminal: boardingPassData.terminal ?? "",
            gate: boardingPassData.gate ?? "",
            delay: 0
        )
        
        let updatedArrival = Airport(
            airport: arrCode,
            code: arrCode,
            city: arrCode, // Use airport code as city for now
            latitude: arrCoordinate?.latitude,
            longitude: arrCoordinate?.longitude,
            time: boardingPassData.arrivalTime ?? "",
            actualTime: "",
            terminal: "",
            gate: "",
            delay: 0
        )
        
        // Create new Flight with updated airports
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
            date: Flight.extractFlightDate(from: boardingPassData.departureTime ?? "")
        )
        
        // Save to FlightStore
        let _ = await flightStore.addFlight(updatedFlight)
        
        print("✅ Flight created from boarding pass:", updatedFlight.flightNumber)
    }
}