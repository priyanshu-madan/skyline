//
//  SkyLineBottomBarView.swift
//  SkyLine
//
//  Bottom bar view replicating FindMyBottomBar structure
//

import SwiftUI
import PhotosUI
import CoreLocation

enum FlightNavigationContext {
    case flights        // Navigated from flights tab
    case trip(Trip)     // Navigated from a specific trip
}

enum FlightFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case past = "Past"
}

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
    @State private var flightNavigationContext: FlightNavigationContext = .flights
    @State private var tripToReopen: Trip? = nil
    @State private var selectedFlightFilter: FlightFilter = .upcoming
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var profileImage: UIImage? = nil

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
                        } else if tab == .trips {
                            Button {
                                addTripView.toggle()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                        } else if tab == .profile {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
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
                    ModernFlightDetailContent(flight: selectedFlight, theme: themeManager)
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
    
    // MARK: - Flight Selection Handler
    
    private func handleFlightSelectedFromTrip(_ flight: Flight, _ trip: Trip) {
        // Set navigation context to remember we came from a trip
        flightNavigationContext = .trip(trip)
        
        // Switch to flights tab
        activeTab = .flights
        
        // Select the flight for details view
        selectedFlightForDetails = flight
        selectedFlightId = flight.id
        
        // Update the detent to show flight details
        selectedDetent = .fraction(0.6)
        
        // Refresh the view to ensure proper display
        flightDetailsViewKey = UUID()
        
        // Call the parent callback if needed
        onTabChanged?(.flights)
        onFlightSelected?(flight)
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    func TripsTabContent() -> some View {
        TripsListView(onFlightSelected: handleFlightSelectedFromTrip, externalTripSelection: tripToReopen)
            .environmentObject(tripStore)
    }
    
    @ViewBuilder
    func FlightsTabContent() -> some View {
        VStack(spacing: 0) {
            // Segmented Control
            if !flightStore.flights.isEmpty {
                FlightFilterSegmentedControl(selectedFilter: $selectedFlightFilter)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }

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
                        let filteredFlights = filteredFlightsList
                        if filteredFlights.isEmpty {
                            EmptyFlightFilterStateView(filterType: selectedFlightFilter.rawValue.lowercased())
                                .padding(.top, 40)
                        } else {
                            ForEach(filteredFlights) { flight in
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
        }
    }

    private var filteredFlightsList: [Flight] {
        let now = Date()
        switch selectedFlightFilter {
        case .upcoming:
            return flightStore.sortedFlights.filter { ($0.departureDate ?? $0.date) >= now }
        case .past:
            return flightStore.sortedFlights.filter { ($0.departureDate ?? $0.date) < now }
        }
    }
    
    
    @ViewBuilder
    func ProfileTabContent() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                Button {
                    showingEditProfile = true
                } label: {
                    VStack(spacing: 12) {
                        // Profile Picture with Edit Badge
                        ZStack(alignment: .topTrailing) {
                            // Profile Picture with Ring
                            Group {
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(themeManager.currentTheme.colors.primary)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Text(authService.authenticationState.user?.initials ?? "SU")
                                                .font(.system(size: 32, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                            .overlay(
                                Circle()
                                    .stroke(themeManager.currentTheme.colors.border.opacity(0.2), lineWidth: 2)
                            )

                            // Edit Pencil Icon
                            ZStack {
                                Circle()
                                    .fill(themeManager.currentTheme.colors.surface)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)

                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                            .offset(x: 2, y: -2)
                        }

                        // Name and Email
                        VStack(spacing: 4) {
                            Text(authService.authenticationState.user?.displayName ?? "SkyLine User")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            if let email = authService.authenticationState.user?.email {
                                Text(email)
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        }
                    }
                }

                // Statistics Card
                HStack(spacing: 0) {
                    StatCard(
                        icon: "suitcase.fill",
                        label: "Total Trips",
                        value: "\(tripStore.trips.count)"
                    )

                    Divider()
                        .frame(height: 60)

                    StatCard(
                        icon: "globe",
                        label: "Countries",
                        value: "\(calculateCountriesVisited())"
                    )

                    Divider()
                        .frame(height: 60)

                    StatCard(
                        icon: "airplane",
                        label: "Flights",
                        value: "\(flightStore.flights.count)"
                    )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.currentTheme.colors.surface)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                )

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .task {
            // Fetch profile image from CloudKit
            await loadProfileImage()
        }
        .onChange(of: showingEditProfile) { _, isShowing in
            if !isShowing {
                // Refresh profile image when edit sheet is dismissed
                Task {
                    await loadProfileImage()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(themeManager)
                .environmentObject(authService)
        }
    }

    // MARK: - Profile Tab Helper Functions

    @ViewBuilder
    private func StatCard(
        icon: String,
        label: String,
        value: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(themeManager.currentTheme.colors.primary)

            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.text)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Statistics Calculations

    private func calculateCountriesVisited() -> Int {
        let countries = Set(tripStore.trips.compactMap { $0.country })
        return countries.count
    }

    private func loadProfileImage() async {
        guard let user = authService.authenticationState.user else { return }

        do {
            if let image = try await CloudKitService.shared.fetchUserProfileImage(userId: user.id) {
                await MainActor.run {
                    profileImage = image
                }
            } else {
                await MainActor.run {
                    profileImage = nil
                }
            }
        } catch {
            print("❌ Failed to load profile image: \(error)")
            await MainActor.run {
                profileImage = nil
            }
        }
    }

    // MARK: - Modern Flight Detail Content Component
    
    func ModernFlightDetailContent(flight: Flight, theme: ThemeManager) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header - exactly like Builder.io
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flight Details")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        print("🔍 DEBUG: Close button tapped")
                        
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        
                        // Reset globe and close flight details
                        onGlobeReset?()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            // Check navigation context for back navigation
                            switch flightNavigationContext {
                            case .flights:
                                // Normal flights tab navigation - stay on flights tab
                                selectedFlightForDetails = nil
                                selectedDetent = .fraction(0.2)
                            case .trip(let trip):
                                // Came from a trip - navigate back to specific trip
                                selectedFlightForDetails = nil
                                activeTab = .trips
                                selectedDetent = .fraction(0.2)
                                
                                // Set the trip to reopen
                                tripToReopen = trip
                                
                                // Clear the trip selection after a delay to allow the view to update
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    tripToReopen = nil
                                }
                                
                                // Reset context
                                flightNavigationContext = .flights
                            }
                            flightDetailsViewKey = UUID()
                            print("🔍 DEBUG: Context-aware navigation completed")
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(theme.currentTheme.colors.border.opacity(0.5))
                                .frame(width: 40, height: 40)
                                .blur(radius: 8)
                            
                            Circle()
                                .fill(theme.currentTheme.colors.surface.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(theme.currentTheme.colors.border.opacity(0.5), lineWidth: 1)
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(theme.currentTheme.colors.text)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Main Boarding Pass Card
                VStack(spacing: 0) {
                    // Card with gradient background and blur effect
                    ZStack {
                        // Background gradient
                        RoundedRectangle(cornerRadius: 32)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: theme.currentTheme.colors.surface.opacity(0.9), location: 0),
                                        .init(color: theme.currentTheme.colors.surface.opacity(0.7), location: 1)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        // Large airplane watermark
                        HStack {
                            Spacer()
                            VStack {
                                Image(systemName: "airplane")
                                    .font(.system(size: 156, weight: .ultraLight))
                                    .foregroundColor(theme.currentTheme.colors.text.opacity(0.03))
                                    .rotationEffect(.degrees(320))
                                    .padding(.top, 24)
                                    .padding(.trailing, 32)
                                Spacer()
                            }
                        }
                        
                        // Main content
                        VStack(spacing: 16) {
                            // Top section: Airline & Flight info
                            VStack(spacing: 20) {
                                // Airline and flight number
                                HStack {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(theme.currentTheme.colors.primary.opacity(0.1))
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(theme.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
                                                )
                                                .shadow(color: theme.currentTheme.colors.primary.opacity(0.1), radius: 10)
                                            
                                            Image(systemName: "airplane")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundColor(theme.currentTheme.colors.primary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("AIRLINE")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .tracking(1.5)
                                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                                                .textCase(.uppercase)
                                            
                                            Text(flight.airline ?? "American Airlines")
                                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                                .foregroundColor(theme.currentTheme.colors.text)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("FLIGHT")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(1.5)
                                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                                            .textCase(.uppercase)
                                        
                                        Text(flight.flightNumber)
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(theme.currentTheme.colors.text)
                                    }
                                }
                                
                                // Route section with large airport codes
                                HStack {
                                    // Departure
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(flight.departure.code)
                                            .font(.system(size: 53, weight: .black, design: .monospaced))
                                            .tracking(-2)
                                            .foregroundColor(theme.currentTheme.colors.text)
                                        
                                        Text(flight.departure.city)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .tracking(1.5)
                                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                                            .textCase(.uppercase)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(flight.departure.displayTime)
                                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                                .foregroundColor(theme.currentTheme.colors.primary)
                                            
                                            Text(formatDate(flight.departureDate ?? flight.date))
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .tracking(0.5)
                                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                                                .textCase(.uppercase)
                                        }
                                        .padding(.top, 16)
                                    }
                                    
                                    Spacer()
                                    
                                    // Flight path
                                    VStack(spacing: 8) {
                                        HStack(spacing: 12) {
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(stops: [
                                                            .init(color: .clear, location: 0),
                                                            .init(color: theme.currentTheme.colors.primary.opacity(0.4), location: 0.5),
                                                            .init(color: theme.currentTheme.colors.primary.opacity(0.4), location: 1)
                                                        ]),
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(height: 1)
                                                .cornerRadius(0.5)
                                            
                                            ZStack {
                                                Circle()
                                                    .fill(theme.currentTheme.colors.primary.opacity(0.2))
                                                    .frame(width: 20, height: 20)
                                                    .blur(radius: 8)
                                                
                                                Image(systemName: "airplane")
                                                    .font(.system(size: 20, weight: .medium))
                                                    .foregroundColor(theme.currentTheme.colors.primary)
                                                    .rotationEffect(.degrees(0))
                                            }
                                            
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(stops: [
                                                            .init(color: theme.currentTheme.colors.primary.opacity(0.4), location: 0),
                                                            .init(color: theme.currentTheme.colors.primary.opacity(0.4), location: 0.5),
                                                            .init(color: .clear, location: 1)
                                                        ]),
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(height: 1)
                                                .cornerRadius(0.5)
                                        }
                                        
                                        HStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(theme.currentTheme.colors.primary.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(theme.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
                                                )
                                                .frame(width: 60, height: 20)
                                                .overlay(
                                                    Text(flight.flightDuration ?? calculateFlightDuration(flight: flight))
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                        .tracking(1.2)
                                                        .foregroundColor(theme.currentTheme.colors.primary)
                                                        .textCase(.uppercase)
                                                )
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    
                                    Spacer()
                                    
                                    // Arrival
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(flight.arrival.code)
                                            .font(.system(size: 53, weight: .black, design: .monospaced))
                                            .tracking(-2)
                                            .foregroundColor(theme.currentTheme.colors.text)
                                        
                                        Text(flight.arrival.city)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .tracking(1.5)
                                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                                            .textCase(.uppercase)
                                        
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(flight.arrival.displayTime)
                                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                                .foregroundColor(theme.currentTheme.colors.primary)
                                            
                                            Text(formatDate(flight.arrivalDate ?? flight.date))
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .tracking(0.5)
                                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                                                .textCase(.uppercase)
                                        }
                                        .padding(.top, 16)
                                    }
                                }
                                
                                // Passenger info section
                                HStack {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            Circle()
                                                .fill(theme.currentTheme.colors.primary.opacity(0.1))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Circle()
                                                        .stroke(theme.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
                                                )
                                            
                                            Image(systemName: "person")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(theme.currentTheme.colors.primary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("PASSENGER")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .tracking(1.5)
                                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                                                .textCase(.uppercase)
                                            
                                            Text("Priyanshu Madan")
                                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                                .foregroundColor(theme.currentTheme.colors.text)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("CLASS")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(1.5)
                                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                                            .textCase(.uppercase)
                                        
                                        Text("Business")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(theme.currentTheme.colors.text)
                                    }
                                }
                                .padding(16)
                                .background(.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.05), lineWidth: 1)
                                )
                                .cornerRadius(16)
                            }
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            
                            // Perforation line
                            ZStack {
                                // Dotted line in center
                                Rectangle()
                                    .fill(.clear)
                                    .frame(height: 2)
                                    .overlay(
                                        GeometryReader { geometry in
                                            Path { path in
                                                let dashLength: CGFloat = 8
                                                let gapLength: CGFloat = 4
                                                let totalLength = dashLength + gapLength
                                                let width = geometry.size.width
                                                let numberOfDashes = Int(width / totalLength)
                                                let startX = (width - CGFloat(numberOfDashes) * totalLength) / 2
                                                
                                                for i in 0..<numberOfDashes {
                                                    let x = startX + CGFloat(i) * totalLength
                                                    path.move(to: CGPoint(x: x, y: 1))
                                                    path.addLine(to: CGPoint(x: x + dashLength, y: 1))
                                                }
                                            }
                                            .stroke(.white.opacity(0.1), lineWidth: 2)
                                        }
                                    )
                                    .padding(.horizontal, 40)
                                
                                // Left circle cutout
                                HStack {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(.white.opacity(0.05), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.4), radius: 6, x: -4, y: 0)
                                        .offset(x: -18)
                                    
                                    Spacer()
                                    
                                    // Right circle cutout
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(.white.opacity(0.05), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.4), radius: 6, x: 4, y: 0)
                                        .offset(x: 18)
                                }
                            }
                            .frame(height: 36)
                            
                            // Bottom section: Barcode
                            VStack(spacing: 16) {
                                // Barcode
                                HStack(spacing: 2) {
                                    ForEach(0..<80, id: \.self) { i in
                                        let widths: [CGFloat] = [1, 2, 3, 1, 4, 2, 1, 3]
                                        Rectangle()
                                            .fill(theme.currentTheme.colors.text.opacity(0.6))
                                            .frame(width: widths[i % 8], height: 80)
                                            .opacity(Double.random(in: 0.1...1) > 0.1 ? 1 : 0.4)
                                            .cornerRadius(widths[i % 8] / 2)
                                    }
                                }
                                .frame(height: 80)
                                .padding(.horizontal, 24)
                                
                                // PNR and Ticket info
                                HStack {
                                    Text("PNR: G7X9K2")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.6)
                                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                                        .textCase(.uppercase)
                                    
                                    Spacer()
                                    
                                    Text("TKT: 0012345678901")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.6)
                                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                                        .textCase(.uppercase)
                                }
                                .padding(.horizontal, 40)
                            }
                            .padding(.bottom, 16)
                            .background(.white.opacity(0.02))
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    // Add to Trip button
                    Button(action: {
                        showingAddToTripSheet = true
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white)
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            
                            Text("Add to Trip")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 40)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        .cornerRadius(40)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
                        .overlay(
                            // Shine effect
                            RoundedRectangle(cornerRadius: 40)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .white.opacity(0.05), location: 0.5),
                                            .init(color: .clear, location: 1)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    
                    // Share button
                    Button(action: {
                        // TODO: Share flight
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                    .frame(width: 80, height: 80)
                    .background(theme.currentTheme.colors.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showingAddToTripSheet) {
            if let flight = selectedFlightForDetails {
                AddFlightToTripView(flight: flight)
                    .environmentObject(themeManager)
                    .environmentObject(TripStore.shared)
            } else {
                AddFlightToTripView(flight: flightStore.selectedFlight ?? Flight.sample)
                    .environmentObject(themeManager)
                    .environmentObject(TripStore.shared)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func calculateFlightDuration(flight: Flight) -> String {
        // Use separate departure and arrival dates if available
        let departureDate = flight.departureDate ?? flight.date
        let arrivalDate = flight.arrivalDate ?? flight.date
        
        // Parse departure and arrival times using their respective dates
        let departureTime = parseTimeString(flight.departure.time, date: departureDate)
        let arrivalTime = parseTimeString(flight.arrival.time, date: arrivalDate)
        
        guard let depTime = departureTime, let arrTime = arrivalTime else {
            return "N/A"
        }
        
        // Calculate duration directly (no need for overnight logic since we use actual dates)
        let duration = arrTime.timeIntervalSince(depTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        // Handle negative durations (shouldn't happen but just in case)
        if duration < 0 {
            return "N/A"
        }
        
        return String(format: "%dH %02dM", hours, minutes)
    }
    
    private func parseTimeString(_ timeString: String, date: Date) -> Date? {
        let timeFormats = ["HH:mm", "H:mm", "h:mm a", "h:mm"]
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
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
        
        return nil
    }
    
    // MARK: - Boarding Pass Handler
    
    @State private var scannedBoardingPassData: BoardingPassData?
    @State private var showingAddToTripSheet = false
}

// MARK: - Preview for the new Boarding Pass UI
#Preview("Modern Boarding Pass UI") {
    NavigationView {
        SkyLineBottomBarView(
            selectedDetent: .constant(.large)
        )
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
    }
}

#Preview("Boarding Pass Component Only") {
    struct PreviewWrapper: View {
        @StateObject private var themeManager = ThemeManager()
        @StateObject private var flightStore = FlightStore()
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                SkyLineBottomBarView(selectedDetent: .constant(.large))
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(AuthenticationService.shared)
            }
        }
    }
    
    return PreviewWrapper()
}

private extension SkyLineBottomBarView {
    func handleBoardingPassScanned(_ boardingPassData: BoardingPassData) async {
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
        // Extract departure and arrival dates separately
        let departureDate: Date
        if let boardingPassDepartureDate = data.departureDate {
            departureDate = boardingPassDepartureDate
        } else {
            // If no departure date from boarding pass, use tomorrow instead of today
            departureDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        }
        
        let arrivalDate: Date
        if let boardingPassArrivalDate = data.arrivalDate {
            arrivalDate = boardingPassArrivalDate
        } else {
            // If no specific arrival date, assume same day as departure
            arrivalDate = departureDate
        }
        
        // Legacy flight date for backward compatibility
        let flightDate = departureDate
        
        // Look up coordinates for departure airport (async with dynamic fetching)
        let (depName, depCity, _, depCoordinates) = await AirportService.shared.getAirportInfo(for: data.departureCode ?? "")
        let (arrName, arrCity, _, arrCoordinates) = await AirportService.shared.getAirportInfo(for: data.arrivalCode ?? "")
        
        // Format departure time - combine departure date with time from boarding pass
        let departureTimeString: String
        let departureDateTime: Date
        if let boardingPassTime = data.departureTime {
            // Combine departure date with boarding pass time
            departureDateTime = combineDateAndTime(date: departureDate, timeString: boardingPassTime) ?? departureDate
            departureTimeString = boardingPassTime // Keep the original time string for display
            print("✈️ Using boarding pass departure time: \(boardingPassTime) on date: \(departureDate)")
        } else {
            // Fallback to ISO format if no time available
            departureDateTime = departureDate
            departureTimeString = ISO8601DateFormatter().string(from: departureDate)
        }
        
        // Format arrival time - combine arrival date with time from boarding pass
        let arrivalTimeString: String
        let arrivalDateTime: Date
        if let boardingPassArrivalTime = data.arrivalTime {
            // Combine arrival date with boarding pass time (this is the key fix!)
            arrivalDateTime = combineDateAndTime(date: arrivalDate, timeString: boardingPassArrivalTime) ?? arrivalDate.addingTimeInterval(7200)
            arrivalTimeString = boardingPassArrivalTime
            print("✈️ Using boarding pass arrival time: \(boardingPassArrivalTime) on date: \(arrivalDate)")
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
            date: flightDate,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            flightDuration: data.flightDuration,
            isUserConfirmed: true, // Boarding pass data is user-confirmed
            userConfirmedFields: UserConfirmedFields(
                departureTime: data.departureTime != nil,
                arrivalTime: data.arrivalTime != nil,
                flightDate: data.departureDate != nil,
                departureDate: data.departureDate != nil,
                arrivalDate: data.arrivalDate != nil,
                gate: data.gate != nil,
                terminal: data.terminal != nil,
                seat: data.seat != nil
            )
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
            // Set navigation context to flights (normal flight tab navigation)
            flightNavigationContext = .flights
            
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
                    Text(flight.departure.displayTime)
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

// MARK: - Flight Filter Segmented Control
struct FlightFilterSegmentedControl: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedFilter: FlightFilter
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FlightFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundColor(selectedFilter == filter
                            ? themeManager.currentTheme.colors.primary
                            : themeManager.currentTheme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Group {
                                if selectedFilter == filter {
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(themeManager.currentTheme.colors.surface)
                                        .matchedGeometryEffect(id: "flightFilter", in: animation)
                                }
                            }
                        )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(themeManager.currentTheme.colors.surface.opacity(0.3))
        )
    }
}

// MARK: - Empty Flight Filter State
struct EmptyFlightFilterStateView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let filterType: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: filterType == "upcoming" ? "calendar" : "clock.arrow.circlepath")
                .font(.system(size: 48, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary.opacity(0.5))

            Text(filterType == "upcoming" ? "No Upcoming Flights" : "No Past Flights")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.text)

            Text(filterType == "upcoming"
                ? "Your upcoming flights will appear here"
                : "Your past flights will appear here")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
