//
//  BottomSheetView.swift
//  SkyLine
//
//  Apple Maps-style bottom sheet interface for navigation
//

import SwiftUI
import PhotosUI

// Preference key to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BottomSheetView: View {
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
    
    // Sheet states
    enum SheetState {
        case collapsed
        case expanded
        
        var height: CGFloat {
            switch self {
            case .collapsed:
                return 96 // Height including drag handle (16pt) + collapsed content (80pt)
            case .expanded:
                return UIScreen.main.bounds.height * 0.6 // Smaller expanded height
            }
        }
    }
    
    @State private var currentState: SheetState = .collapsed
    @State private var scrollOffset: CGFloat = 0
    @State private var translation: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let collapsedHeight: CGFloat = 96
            let expandedHeight: CGFloat = geometry.size.height * 0.6
            let heightDifference = expandedHeight - collapsedHeight
            
            // Calculate sheet position from bottom
            let baseOffset: CGFloat = currentState == .collapsed ? 
                geometry.size.height - collapsedHeight : 
                geometry.size.height - expandedHeight
                
            let currentOffset = baseOffset + translation
            
            VStack(spacing: 0) {
                // Drag Handle Area (always visible at top of sheet)
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(themeManager.currentTheme.colors.textSecondary.opacity(0.6))
                        .frame(width: 40, height: 2)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                
                // Content based on state - single content view to avoid layering issues
                Group {
                    if currentState == .collapsed {
                        collapsedContent
                    } else {
                        expandedContent
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()
            }
            .frame(height: currentState == .collapsed ? collapsedHeight : expandedHeight)
            .background(
                Rectangle()
                    .fill(themeManager.currentTheme.colors.surface)
                    .cornerRadius(16, corners: [.topLeft, .topRight])
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(y: max(geometry.size.height - expandedHeight, min(geometry.size.height - collapsedHeight, currentOffset)))
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        let dragTranslation = value.translation.height
                        
                        // Only handle sheet gestures, let ScrollView handle its own scrolling
                        if currentState == .collapsed {
                            // Always allow expanding when collapsed
                            translation = max(-heightDifference, dragTranslation)
                        } else if currentState == .expanded && scrollOffset >= -10 && dragTranslation > 0 {
                            // Only handle downward collapse when at scroll top
                            translation = min(heightDifference, dragTranslation)
                        }
                    }
                    .onEnded { value in
                        let dragTranslation = value.translation.height
                        let velocity = value.velocity.height
                        
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            if currentState == .collapsed {
                                // Check if should expand
                                if dragTranslation < -50 || velocity < -300 {
                                    currentState = .expanded
                                }
                            } else {
                                // Check if should collapse
                                if scrollOffset >= -10 && (dragTranslation > 50 || velocity > 300) {
                                    currentState = .collapsed
                                }
                            }
                            
                            // Always reset translation
                            translation = 0
                        }
                    }
            )
        }
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
    
    // MARK: - Collapsed Content
    
    private var collapsedContent: some View {
        HStack(spacing: 16) {
            // Profile Picture
            Button(action: {
                withAnimation(.interactiveSpring()) {
                    currentState = .expanded
                }
            }) {
                Circle()
                    .fill(themeManager.currentTheme.colors.primary.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Group {
                            if let user = authService.authenticationState.user {
                                Text(user.initials)
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                            }
                        }
                    )
            }
            
            Spacer()
            
            // Flight count
            VStack(alignment: .center, spacing: 2) {
                Text("\(flightStore.flightCount)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("flights")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
            
            // Add Flight Button
            Button(action: {
                withAnimation(.interactiveSpring()) {
                    currentState = .expanded
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("Add Flight")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(25)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 24) {
                // Header with Profile
                HStack {
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
                    
                    // Close button
                    Button(action: {
                        withAnimation(.interactiveSpring()) {
                            currentState = .collapsed
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(themeManager.currentTheme.colors.textSecondary.opacity(0.1))
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
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
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Boarding Pass")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(themeManager.currentTheme.colors.background)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeManager.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
                            )
                            .onSubmit {
                                if !searchText.isEmpty {
                                    performFlightSearch()
                                }
                            }
                        
                        Button("Search Flights") {
                            performFlightSearch()
                        }
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
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
                            .background(themeManager.currentTheme.colors.background)
                            .cornerRadius(8)
                        }
                        
                        // Search Error
                        if let error = searchError {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.error)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Search Failed")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.error)
                                    Text(error)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(themeManager.currentTheme.colors.error.opacity(0.1))
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
                                            
                                            // Collapse the sheet
                                            withAnimation(.interactiveSpring()) {
                                                currentState = .collapsed
                                            }
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
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
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
                                    // Focus on flight in globe and collapse
                                    withAnimation(.interactiveSpring()) {
                                        currentState = .collapsed
                                    }
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
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
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
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(themeManager.currentTheme.colors.primary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                    .background(themeManager.currentTheme.colors.background)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                // Spacer for bottom safe area
                Color.clear
                    .frame(height: 40)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
            )
            .coordinateSpace(name: "scroll")
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    // MARK: - Helper Functions
    
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
            dataSource: flight.dataSource
        )
        
        // Save to FlightStore
        let _ = await flightStore.addFlight(updatedFlight)
        
        print("✅ Flight created from boarding pass:", updatedFlight.flightNumber)
        
        // Collapse the sheet
        withAnimation(.interactiveSpring()) {
            currentState = .collapsed
        }
    }
}

// MARK: - Compact Flight Row View

struct CompactFlightRowView: View {
    let flight: Flight
    let onTap: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Route
                HStack(spacing: 8) {
                    Text(flight.departure.code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.arrival.code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                
                Spacer()
                
                // Flight Number
                Text(flight.flightNumber)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                
                // Status
                Text(flight.status.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: flight.status))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(themeManager.currentTheme.colors.background)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func statusColor(for status: FlightStatus) -> Color {
        switch status {
        case .boarding: return themeManager.currentTheme.colors.statusBoarding
        case .departed: return themeManager.currentTheme.colors.statusDeparted
        case .inAir: return themeManager.currentTheme.colors.statusInAir
        case .landed: return themeManager.currentTheme.colors.statusLanded
        case .delayed: return themeManager.currentTheme.colors.statusDelayed
        case .cancelled: return themeManager.currentTheme.colors.statusCancelled
        }
    }
}

// MARK: - Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}