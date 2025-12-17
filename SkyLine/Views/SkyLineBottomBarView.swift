//
//  SkyLineBottomBarView.swift
//  SkyLine
//
//  Bottom bar view replicating FindMyBottomBar structure
//

import SwiftUI
import PhotosUI

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let flightCardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()
    
    static let flightTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    static let flightTimeArrival: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

/// Tab Enum for SkyLine
enum SkyLineTab: String, CaseIterable {
    case trips = "Trips"
    case flights = "Flights"
    case profile = "Profile"
    
    var symbolImage: String {
        switch self {
        case .trips:
            return "suitcase"
        case .flights:
            return "airplane"
        case .profile:
            return "location.slash"
        }
    }
}

struct SkyLineBottomBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var tripStore = TripStore.shared
    @State private var activeTab: SkyLineTab = .trips
    @State private var addTripView: Bool = false
    @State private var refreshID = UUID()
    @State private var selectedFlightId: String? = nil
    @State private var selectedFlightForDetails: Flight? = nil
    @State private var flightDetailsViewKey: UUID = UUID()
    
    // Callbacks to communicate with parent ContentView
    let onFlightSelected: ((Flight) -> Void)?
    let onTabSelected: (() -> Void)?
    let onGlobeReset: (() -> Void)?
    let onTabChanged: ((SkyLineTab) -> Void)?
    @Binding var selectedDetent: PresentationDetent
    
    init(onFlightSelected: ((Flight) -> Void)? = nil, onTabSelected: (() -> Void)? = nil, onGlobeReset: (() -> Void)? = nil, selectedDetent: Binding<PresentationDetent>, onTabChanged: ((SkyLineTab) -> Void)? = nil) {
        self.onFlightSelected = onFlightSelected
        self.onTabSelected = onTabSelected
        self.onGlobeReset = onGlobeReset
        self.onTabChanged = onTabChanged
        self._selectedDetent = selectedDetent
    }
    
    var body: some View {
        GeometryReader {
            let safeArea = $0.safeAreaInsets
            let bottomPadding = safeArea.bottom / 5
            
            VStack(spacing: 0) {
                TabView(selection: $activeTab) {
                    IndividualTabView(.trips)
                        .tag(SkyLineTab.trips)
                    
                    IndividualTabView(.flights)
                        .tag(SkyLineTab.flights)
                    
                    IndividualTabView(.profile)
                        .tag(SkyLineTab.profile)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .background {
                    TabViewHelper()
                }
                .compositingGroup()
                .onChange(of: activeTab) { newTab in
                    print("🔄 Tab changed in onChange: \(newTab.rawValue)")
                    onTabChanged?(newTab)
                }
                .onAppear {
                    onTabChanged?(activeTab)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BoardingPassScanned"))) { notification in
                    if let boardingPassData = notification.object as? BoardingPassData {
                        Task {
                            await handleBoardingPassScanned(boardingPassData)
                        }
                    }
                }
                
                CustomTabBar()
                    .padding(.bottom, bottomPadding)
            }
            .background(themeManager.currentTheme.colors.background)
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $addTripView) {
            AddTripView()
                .environmentObject(themeManager)
                .environmentObject(tripStore)
        }
        .sheet(item: $scannedBoardingPassData) { boardingPassData in
            BoardingPassConfirmationView(
                boardingPassData: boardingPassData,
                onConfirm: { confirmedData in
                    Task {
                        let flight = await createFlightFromBoardingPass(confirmedData)
                        let result = await flightStore.addFlight(flight)
                        
                        await MainActor.run {
                            switch result {
                            case .success:
                                print("✅ Flight added to store: \(flight.flightNumber)")
                                scannedBoardingPassData = nil
                                
                                // Auto-focus on the new flight
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    handleFlightTap(flight)
                                }
                                
                            case .failure(let error):
                                print("❌ Failed to add flight: \(error)")
                                scannedBoardingPassData = nil
                            }
                        }
                    }
                },
                onCancel: {
                    scannedBoardingPassData = nil
                }
            )
            .environmentObject(themeManager)
            .onAppear {
                print("📋 Presenting confirmation sheet with data: \(boardingPassData.summary)")
            }
        }
    }
    
    /// Individual Tab View
    @ViewBuilder
    func IndividualTabView(_ tab: SkyLineTab) -> some View {
        ScrollView(.vertical) {
            VStack {
                // Remove the header section when viewing flight details
                if !(tab == .flights && selectedFlightForDetails != nil && (selectedDetent == .fraction(0.3) || selectedDetent == .fraction(0.6) || selectedDetent == .large)) {
                    HStack {
                        if tab == .trips {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trips")
                                    .font(.system(.largeTitle, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                Text("\(tripStore.trips.count) trips documented")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        } else {
                            Text(tab.rawValue)
                                .font(.system(.largeTitle, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                        }
                        
                        Spacer(minLength: 0)
                        
                        if tab == .flights {
                            CustomMenuView(style: .glass) {
                                Image(systemName: "plus")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .frame(width: 30, height: 30)
                            } content: {
                                BoardingPassMenuContent()
                                    .environmentObject(themeManager)
                            }
                        } else {
                            Button {
                                if tab == .trips {
                                    addTripView.toggle()
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                        }
                    }
                    .padding(.top, 15)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
                }
            }
            
            // Tab-specific content
            switch tab {
            case .trips:
                TripsTabContent()
            case .flights:
                if let selectedFlight = selectedFlightForDetails, selectedDetent == .fraction(0.3) || selectedDetent == .fraction(0.6) || selectedDetent == .large {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Flight Header
                            VStack(spacing: 12) {
                                Text(selectedFlight.flightNumber)
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                if let airline = selectedFlight.airline {
                                    Text(airline)
                                        .font(.system(size: 16, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                            }
                            .padding(.top, 20)
                            
                            // Route Information
                            HStack(spacing: 20) {
                                // Departure
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DEPARTURE")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    
                                    Text(selectedFlight.departure.code)
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    
                                    Text(selectedFlight.departure.airport)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                        .lineLimit(2)
                                    
                                    if !selectedFlight.departure.time.isEmpty {
                                        Text(selectedFlight.departure.time)
                                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.primary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "airplane")
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                                    .rotationEffect(.degrees(45))
                                
                                Spacer()
                                
                                // Arrival
                                VStack(alignment: .trailing, spacing: 8) {
                                    Text("ARRIVAL")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    
                                    Text(selectedFlight.arrival.code)
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    
                                    Text(selectedFlight.arrival.airport)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.trailing)
                                    
                                    if !selectedFlight.arrival.time.isEmpty {
                                        Text(selectedFlight.arrival.time)
                                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.primary)
                                    }
                                }
                            }
                            .padding(20)
                            .background(themeManager.currentTheme.colors.surface)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }
                    }
                    .onTapGesture {
                        print("🔍 DEBUG: Flight detail view close tapped")
                        onGlobeReset?()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedFlightForDetails = nil
                            selectedDetent = .fraction(0.2)
                            flightDetailsViewKey = UUID()
                            print("🔍 DEBUG: Reset to selectedDetent 0.2")
                        }
                    }
                    .id(flightDetailsViewKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .transaction { transaction in
                        // Force immediate update without animation to reset scroll state
                        transaction.disablesAnimations = true
                    }
                    .onAppear {
                        print("🔍 DEBUG: FlightDetailView appeared in SkyLineBottomBarView")
                        print("🔍 DEBUG: Current selectedDetent: \(selectedDetent)")
                        print("🔍 DEBUG: Flight: \(selectedFlight.flightNumber)")
                        print("🔍 DEBUG: ViewKey: \(flightDetailsViewKey)")
                    }
                } else {
                    FlightsTabContent()
                }
            case .profile:
                ProfileTabContent()
            }
        }
        .background(.clear)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarBackgroundVisibility(.hidden, for: .tabBar)
    }
    
    /// Custom Tab Bar with Liquid Glass Effect
    @ViewBuilder
    func CustomTabBar() -> some View {
        HStack(spacing: 0) {
            ForEach(SkyLineTab.allCases, id: \.rawValue) { tab in
                VStack(spacing: 6) {
                    Image(systemName: tab.symbolImage)
                        .font(.system(.title3, design: .monospaced))
                        .symbolVariant(.fill)
                    
                    Text(tab.rawValue)
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(activeTab == tab ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture {
                    print("🎯 Tab tapped: \(tab.rawValue)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeTab = tab
                    }
                    
                    // Immediately notify the globe of tab change
                    print("🔄 Immediately calling onTabChanged with: \(tab.rawValue)")
                    onTabChanged?(tab)
                    
                    // Trigger sheet expansion when tab is tapped
                    onTabSelected?()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.currentTheme == .light ? .white : themeManager.currentTheme.colors.surface)
                .shadow(
                    color: themeManager.currentTheme == .light ? .black.opacity(0.1) : .white.opacity(0.05),
                    radius: 10,
                    x: 0,
                    y: -2
                )
        )
        .id(refreshID)
        .onReceive(themeManager.$currentTheme) { _ in
            refreshID = UUID()
        }
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    func TripsTabContent() -> some View {
        TripsListView()
            .environmentObject(tripStore)
    }
    
    @ViewBuilder
    func FlightsTabContent() -> some View {
        if flightStore.flights.isEmpty {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "airplane")
                        .font(.system(size: 48, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                    
                    Text("No Flights")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.semibold)
                    
                    Text("Add flights to track their status")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(flightStore.sortedFlights) { flight in
                        FlightRowView(
                            flight: flight,
                            isSelected: selectedFlightId == flight.id,
                            onTap: {
                                handleFlightTap(flight)
                            },
                            onDelete: {
                                handleFlightDelete(flight)
                            }
                        )
                        .id("\(flight.id)-\(refreshID)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }
    
    
    @ViewBuilder
    func ProfileTabContent() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 48, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                
                Text(authService.authenticationState.user?.displayName ?? "Profile")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                
                Text("Settings and account")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Boarding Pass Handler
    
    @State private var scannedBoardingPassData: BoardingPassData?
    
    private func handleBoardingPassScanned(_ boardingPassData: BoardingPassData) async {
        print("🎫 Boarding pass scanned successfully")
        print("📄 Data: \(boardingPassData.summary)")
        print("🔍 Detailed BoardingPassData received in UI:")
        print("   ✈️  Flight: \(boardingPassData.flightNumber ?? "N/A")")
        print("   🏢 Airline: \(boardingPassData.airline ?? "N/A")")
        print("   👤 Passenger: \(boardingPassData.passengerName ?? "N/A")")
        print("   🛫 Departure: \(boardingPassData.departureCode ?? "N/A") (\(boardingPassData.departureCity ?? "N/A"))")
        print("   🛬 Arrival: \(boardingPassData.arrivalCode ?? "N/A") (\(boardingPassData.arrivalCity ?? "N/A"))")
        print("   🕐 Dep Time: \(boardingPassData.departureTime ?? "N/A")")
        print("   🕐 Arr Time: \(boardingPassData.arrivalTime ?? "N/A")")
        print("   📅 Dep Date: \(boardingPassData.departureDate?.description ?? "N/A")")
        print("   📅 Arr Date: \(boardingPassData.arrivalDate?.description ?? "N/A")")
        print("   💺 Seat: \(boardingPassData.seat ?? "N/A")")
        print("   🚪 Gate: \(boardingPassData.gate ?? "N/A")")
        print("   🏢 Terminal: \(boardingPassData.terminal ?? "N/A")")
        print("   🎫 Confirmation: \(boardingPassData.confirmationCode ?? "N/A")")
        print("   ✅ Is Valid: \(boardingPassData.isValid)")
        
        // Show confirmation sheet with compact time pickers by setting the data
        await MainActor.run {
            scannedBoardingPassData = boardingPassData
            print("📋 Set scannedBoardingPassData to trigger sheet: \(scannedBoardingPassData?.summary ?? "nil")")
        }
    }
    
    private func createFlightFromBoardingPass(_ data: BoardingPassData) async -> Flight {
        // Use boarding pass date if available, otherwise use a future date (not current date)
        let flightDate: Date
        if let boardingPassDate = data.departureDate {
            flightDate = boardingPassDate
        } else {
            // If no date from boarding pass, use tomorrow instead of today
            flightDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        }
        
        // Look up coordinates for departure airport (async with dynamic fetching)
        let (depName, depCity, _, depCoordinates) = await AirportService.shared.getAirportInfo(for: data.departureCode ?? "")
        let (arrName, arrCity, _, arrCoordinates) = await AirportService.shared.getAirportInfo(for: data.arrivalCode ?? "")
        
        // Format departure time - combine date with time from boarding pass
        let departureTimeString: String
        let departureDateTime: Date
        if let boardingPassTime = data.departureTime {
            // Combine flight date with boarding pass time
            departureDateTime = combineDateAndTime(date: flightDate, timeString: boardingPassTime) ?? flightDate
            departureTimeString = boardingPassTime // Keep the original time string for display
            print("✈️ Using boarding pass departure time: \(boardingPassTime)")
        } else {
            // Fallback to ISO format if no time available
            departureDateTime = flightDate
            departureTimeString = ISO8601DateFormatter().string(from: flightDate)
        }
        
        // Format arrival time - only use if extracted from boarding pass, otherwise N/A
        let arrivalTimeString: String
        let arrivalDateTime: Date
        if let boardingPassArrivalTime = data.arrivalTime {
            // Use the actual arrival time from boarding pass
            arrivalDateTime = combineDateAndTime(date: flightDate, timeString: boardingPassArrivalTime) ?? flightDate.addingTimeInterval(7200)
            arrivalTimeString = boardingPassArrivalTime
            print("✈️ Using boarding pass arrival time: \(boardingPassArrivalTime)")
        } else {
            // No arrival time on boarding pass - show N/A
            arrivalDateTime = departureDateTime.addingTimeInterval(7200) // Still need a date for internal use
            arrivalTimeString = "N/A"
            print("⚠️ No arrival time on boarding pass, showing N/A")
        }
        
        // Create departure airport with proper coordinates
        let departure = Airport(
            airport: depName ?? "\(data.departureCity ?? data.departureCode ?? "Unknown") Airport",
            code: data.departureCode ?? "???",
            city: depCity ?? data.departureCity ?? data.departureCode ?? "Unknown",
            latitude: depCoordinates?.latitude ?? 0.0,
            longitude: depCoordinates?.longitude ?? 0.0,
            time: departureTimeString,
            actualTime: nil,
            terminal: data.terminal,
            gate: data.gate,
            delay: nil
        )
        
        // Create arrival airport with proper coordinates
        let arrival = Airport(
            airport: arrName ?? "\(data.arrivalCity ?? data.arrivalCode ?? "Unknown") Airport", 
            code: data.arrivalCode ?? "???",
            city: arrCity ?? data.arrivalCity ?? data.arrivalCode ?? "Unknown",
            latitude: arrCoordinates?.latitude ?? 0.0,
            longitude: arrCoordinates?.longitude ?? 0.0,
            time: arrivalTimeString,
            actualTime: nil,
            terminal: nil,
            gate: nil,
            delay: nil
        )
        
        // Create flight object
        let flight = Flight(
            id: "boarding-pass-\(UUID().uuidString)",
            flightNumber: data.flightNumber ?? "Unknown",
            airline: data.airline, // Use the airline extracted from boarding pass
            departure: departure,
            arrival: arrival,
            status: .boarding,
            aircraft: Aircraft(
                type: nil,
                registration: nil,
                icao24: nil
            ),
            currentPosition: nil,
            progress: 0.0,
            flightDate: ISO8601DateFormatter().string(from: flightDate),
            dataSource: .pkpass,
            date: flightDate
        )
        
        print("✈️ Created Flight object from BoardingPass:")
        print("   Flight: \(flight.flightNumber) (\(flight.airline ?? "No Airline"))")
        print("   Route: \(flight.departure.code) (\(flight.departure.city)) → \(flight.arrival.code) (\(flight.arrival.city))")
        print("   Times: \(flight.departure.time) → \(flight.arrival.time)")
        print("   Date: \(DateFormatter.flightCardDate.string(from: flight.date))")
        print("   Coordinates: (\(flight.departure.latitude ?? 0), \(flight.departure.longitude ?? 0)) → (\(flight.arrival.latitude ?? 0), \(flight.arrival.longitude ?? 0))")
        
        return flight
    }
    
    // MARK: - Helper Functions
    
    private func combineDateAndTime(date: Date, timeString: String) -> Date? {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
        // Parse the time string (supports formats like "19:45", "7:35 PM")
        let timeFormats = ["HH:mm", "H:mm", "h:mm a", "h:mm"]
        
        for format in timeFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let timeDate = formatter.date(from: timeString) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
                
                var combinedComponents = DateComponents()
                combinedComponents.year = dateComponents.year
                combinedComponents.month = dateComponents.month
                combinedComponents.day = dateComponents.day
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                
                return calendar.date(from: combinedComponents)
            }
        }
        
        print("⚠️ Could not parse time string: '\(timeString)'")
        return nil
    }
    
    // Duration calculation removed - will be added in future update
    
    // MARK: - Flight Action Handlers
    
    private func handleFlightTap(_ flight: Flight) {
        print("🔍 DEBUG: Flight tapped - \(flight.flightNumber)")
        print("🔍 DEBUG: Current selectedDetent before tap: \(selectedDetent)")
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedFlightId = flight.id
            selectedFlightForDetails = flight
            flightDetailsViewKey = UUID() // Force view recreation with new key
            print("🔍 DEBUG: Set selectedFlightForDetails to \(flight.flightNumber)")
            print("🔍 DEBUG: Generated new flightDetailsViewKey: \(flightDetailsViewKey)")
            
            // For collapsed sheet, start with a specific detent
            if selectedDetent == .fraction(0.2) {
                selectedDetent = .fraction(0.3) // Start collapsed
                print("🔍 DEBUG: Changed selectedDetent from 0.2 to 0.3 (collapsed)")
            } else {
                print("🔍 DEBUG: selectedDetent was not 0.2, keeping as \(selectedDetent)")
            }
        }
        
        // Call the callback to communicate with ContentView
        onFlightSelected?(flight)
        print("🔍 DEBUG: Called onFlightSelected callback")
    }
    
    private func handleFlightDelete(_ flight: Flight) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Use removeFlightSync to also delete from CloudKit
        Task {
            await flightStore.removeFlightSync(flight.id)
        }
    }
    
    @ViewBuilder
    func FlightRowView(flight: Flight, isSelected: Bool = false, onTap: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            // Flight date
            HStack {
                Text(DateFormatter.flightCardDate.string(from: flight.date))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                Spacer()
            }
            .padding(.bottom, 12)
            
            // Main flight info section
            HStack(spacing: 16) {
                // Departure
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateFormatter.flightTime.string(from: flight.date))
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.departure.code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.departure.city)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Center airplane icon
                ZStack {
                    Circle()
                        .fill(themeManager.currentTheme.colors.text)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "airplane")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.background)
                        .rotationEffect(.degrees(90))
                }
                
                Spacer()
                
                // Arrival
                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.arrival.displayTime)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.arrival.code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.arrival.city)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 16)
            
            // Bottom section with flight details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Airlines")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.airline ?? "Unknown")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Flight no")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.flightNumber)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
            }
            .padding(12)
            .background(themeManager.currentTheme == .light ? Color(.systemGray6) : Color(.systemGray6).opacity(0.3))
            .cornerRadius(8)
        }
        .padding(12)
        .background(isSelected ? 
            themeManager.currentTheme.colors.primary.opacity(0.1) : 
            (themeManager.currentTheme == .light ? .white : themeManager.currentTheme.colors.surface))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? 
                        themeManager.currentTheme.colors.primary : 
                        (themeManager.currentTheme == .light ? Color(.systemGray4) : themeManager.currentTheme.colors.border),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: isSelected ? themeManager.currentTheme.colors.primary.opacity(0.3) : .black.opacity(0.05),
            radius: isSelected ? 8 : 2,
            x: 0,
            y: isSelected ? 4 : 1
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Focus on Globe", systemImage: "globe")
            }
            
            Button {
                // Copy flight info to clipboard
                let flightInfo = "\(flight.flightNumber): \(flight.departure.code) → \(flight.arrival.code)"
                UIPasteboard.general.string = flightInfo
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Flight", systemImage: "trash")
            }
        } preview: {
            // Preview content for the context menu
            VStack(alignment: .leading, spacing: 8) {
                Text(flight.flightNumber)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text(flight.departure.code)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(flight.departure.city)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "airplane")
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(flight.arrival.code)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(flight.arrival.city)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Status: \(flight.status.displayName)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(getStatusColor(for: flight.status))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(12)
        }
    }
    
    private func getStatusColor(for status: FlightStatus) -> Color {
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

fileprivate struct TabViewHelper: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        DispatchQueue.main.async {
            guard let compostingGroup = view.superview?.superview else { return }
            guard let swiftUIWrapperUITabView = compostingGroup.subviews.last else { return }
            
            if let tabBarController = swiftUIWrapperUITabView.subviews.first?.next as? UITabBarController {
                /// Clearing Backgrounds for liquid glass effect
                tabBarController.view.backgroundColor = .clear
                tabBarController.viewControllers?.forEach {
                    $0.view.backgroundColor = .clear
                }
                
                tabBarController.delegate = context.coordinator
                
                /// Remove default tab bar to use custom liquid glass one
                tabBarController.tabBar.removeFromSuperview()
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) { }
    
    class Coordinator: NSObject, UITabBarControllerDelegate, UIViewControllerAnimatedTransitioning {
        func tabBarController(_ tabBarController: UITabBarController, animationControllerForTransitionFrom fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            return self
        }
        
        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return .zero
        }
        
        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let destinationView = transitionContext.view(forKey: .to) else { return }
            let containerView = transitionContext.containerView
            
            containerView.addSubview(destinationView)
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - Custom Menu View

struct CustomMenuView<Label: View, Content: View>: View {
    var style: CustomMenuStyle = .glass
    var isHapticsEnabled: Bool = true
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content
    /// View Properties
    @State private var haptics: Bool = false
    @State private var isExpanded: Bool = false
    /// For Zoom transition
    @Namespace private var namespace
    
    var body: some View {
        Button {
            if isHapticsEnabled {
                haptics.toggle()
            }
            
            isExpanded.toggle()
        } label: {
            label
                .matchedTransitionSource(id: "MENUCONTENT", in: namespace)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .popover(isPresented: $isExpanded) {
            PopOverHelper {
                content
            }
            .navigationTransition(.zoom(sourceID: "MENUCONTENT", in: namespace))
        }
        .sensoryFeedback(.selection, trigger: haptics)
    }
}

fileprivate struct PopOverHelper<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isVisible: Bool = false
    
    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                    isVisible = true
                }
            }
            .presentationCompactAdaptation(.popover)
    }
}

/// Menu Style
enum CustomMenuStyle: String, CaseIterable {
    case glass = "Glass"
    case glassProminent = "Glass Prominent"
}

// MARK: - Boarding Pass Menu Content

struct BoardingPassMenuContent: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var unifiedService = UnifiedBoardingPassService.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Scan Boarding Pass")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 5)
            
            VStack(spacing: 15) {
                // Camera Button
                Button(action: { 
                    isShowingPicker = true 
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan Boarding Pass")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            Text("From camera or photos")
                                .font(.system(size: 11, design: .monospaced))
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [themeManager.currentTheme.colors.primary, themeManager.currentTheme.colors.primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .disabled(unifiedService.isProcessing)
                
                // Processing State
                if unifiedService.isProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("Scanning...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(8)
                }
                
                // Error State
                if let error = unifiedService.lastResult?.error {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.error)
                        
                        Text("Scan Failed")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.error)
                        
                        Spacer()
                        
                        Button("Retry") {
                            isShowingPicker = true
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.colors.error.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            // Cancel Button
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(.top, 5)
        }
        .padding(20)
        .frame(width: 280, height: 180)
        .photosPicker(isPresented: $isShowingPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { newPhoto in
            if let newPhoto = newPhoto {
                processSelectedPhoto(newPhoto)
            }
        }
    }
    
    private func processSelectedPhoto(_ photo: PhotosPickerItem) {
        Task {
            do {
                guard let imageData = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: imageData) else {
                    print("❌ Failed to load selected image")
                    return
                }
                
                print("📸 Processing boarding pass image...")
                
                if let boardingPassData = await unifiedService.parseImage(uiImage) {
                    print("✅ OCR completed successfully:", boardingPassData.summary)
                    
                    // Post notification to main view to show confirmation and close menu
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("BoardingPassScanned"),
                            object: boardingPassData
                        )
                        print("📋 Posted notification for boarding pass: \(boardingPassData.summary)")
                        dismiss() // Close the menu
                    }
                } else {
                    print("❌ OCR failed to extract boarding pass data")
                }
                
            } catch {
                print("❌ Error loading image: \(error.localizedDescription)")
                print("❌ Error processing photo:", error)
            }
        }
    }
    
    private func handleBoardingPassScanned(_ boardingPassData: BoardingPassData) async {
        print("🎫 Boarding pass confirmed in menu:", boardingPassData.summary)
        
        // Post a notification to handle this in the parent view
        NotificationCenter.default.post(
            name: NSNotification.Name("BoardingPassScanned"), 
            object: boardingPassData
        )
    }
}


#Preview {
    SkyLineBottomBarView(
        onFlightSelected: nil, 
        onTabSelected: nil,
        onGlobeReset: nil,
        selectedDetent: .constant(.fraction(0.2))
    )
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}