//
//  SkyLineBottomBarView.swift
//  SkyLine
//
//  Bottom bar view replicating FindMyBottomBar structure
//

import SwiftUI

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let flightCardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
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
    case globe = "Globe"
    case flights = "Flights"
    case search = "Search"
    case profile = "Profile"
    
    var symbolImage: String {
        switch self {
        case .globe:
            return "globe.americas"
        case .flights:
            return "airplane"
        case .search:
            return "magnifyingglass"
        case .profile:
            return "location.slash"
        }
    }
}

struct SkyLineBottomBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var authService: AuthenticationService
    @State private var activeTab: SkyLineTab = .globe
    @State private var addFlightView: Bool = false
    @State private var refreshID = UUID()
    @State private var selectedFlightId: String? = nil
    @State private var selectedFlightForDetails: Flight? = nil
    
    // Callbacks to communicate with parent ContentView
    let onFlightSelected: ((Flight) -> Void)?
    let onTabSelected: (() -> Void)?
    let onGlobeReset: (() -> Void)?
    @Binding var selectedDetent: PresentationDetent
    
    init(onFlightSelected: ((Flight) -> Void)? = nil, onTabSelected: (() -> Void)? = nil, onGlobeReset: (() -> Void)? = nil, selectedDetent: Binding<PresentationDetent>) {
        self.onFlightSelected = onFlightSelected
        self.onTabSelected = onTabSelected
        self.onGlobeReset = onGlobeReset
        self._selectedDetent = selectedDetent
    }
    
    var body: some View {
        GeometryReader {
            let safeArea = $0.safeAreaInsets
            let bottomPadding = safeArea.bottom / 5
            
            VStack(spacing: 0) {
                TabView(selection: $activeTab) {
                    IndividualTabView(.globe)
                        .tag(SkyLineTab.globe)
                    
                    IndividualTabView(.flights)
                        .tag(SkyLineTab.flights)
                    
                    IndividualTabView(.search)
                        .tag(SkyLineTab.search)
                    
                    IndividualTabView(.profile)
                        .tag(SkyLineTab.profile)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .background {
                    TabViewHelper()
                }
                .compositingGroup()
                
                CustomTabBar()
                    .padding(.bottom, bottomPadding)
            }
            .background(themeManager.currentTheme.colors.background)
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $addFlightView) {
            BottomSheetContentView(sheetPosition: .constant(.dynamicBottom))
                .environmentObject(themeManager)
                .environmentObject(flightStore)
                .environmentObject(authService)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(40)
        }
    }
    
    /// Individual Tab View
    @ViewBuilder
    func IndividualTabView(_ tab: SkyLineTab) -> some View {
        ScrollView(.vertical) {
            VStack {
                HStack {
                    if tab == .flights && selectedFlightForDetails != nil && (selectedDetent == .fraction(0.3) || selectedDetent == .fraction(0.6) || selectedDetent == .large) {
                        // Flight path header
                        Text("\(selectedFlightForDetails?.departure.code ?? "") → \(selectedFlightForDetails?.arrival.code ?? "")")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Spacer(minLength: 0)
                        
                        Button {
                            // Reset globe view first
                            onGlobeReset?()
                            
                            // Then close flight details
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedFlightForDetails = nil
                                selectedDetent = .fraction(0.2)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    } else {
                        Text(tab.rawValue)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Spacer(minLength: 0)
                        
                        Button {
                            addFlightView.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.top, 15)
                .padding(.leading, 10)
            }
            .padding(15)
            
            // Tab-specific content
            switch tab {
            case .globe:
                GlobeTabContent()
            case .flights:
                if let selectedFlight = selectedFlightForDetails, selectedDetent == .fraction(0.3) || selectedDetent == .fraction(0.6) || selectedDetent == .large {
                    FlightDetailsInSheet(
                        flight: selectedFlight,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedFlightForDetails = nil
                                selectedDetent = .fraction(0.2)
                            }
                        }
                    )
                } else {
                    FlightsTabContent()
                }
            case .search:
                SearchTabContent()
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
                        .font(.title3)
                        .symbolVariant(.fill)
                    
                    Text(tab.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(activeTab == tab ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeTab = tab
                    }
                    
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
                .fill(themeManager.currentTheme == .light ? .white : Color.black.opacity(0.6))
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
    func GlobeTabContent() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Main content area - placeholder for now
            VStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 48))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                
                Text("SkyLine")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\(flightStore.flightCount) flights tracked")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    func FlightsTabContent() -> some View {
        if flightStore.flights.isEmpty {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "airplane")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                    
                    Text("No Flights")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add flights to track their status")
                        .font(.body)
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
    func SearchTabContent() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                
                Text("Search Flights")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Find and track flight status")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    func ProfileTabContent() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 48))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                
                Text(authService.authenticationState.user?.displayName ?? "Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Settings and account")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Flight Action Handlers
    
    private func handleFlightTap(_ flight: Flight) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedFlightId = flight.id
            selectedFlightForDetails = flight
        }
        
        // Call the callback to communicate with ContentView
        onFlightSelected?(flight)
    }
    
    private func handleFlightDelete(_ flight: Flight) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        Task {
            let _ = await flightStore.removeFlight(flight.id)
        }
    }
    
    @ViewBuilder
    func FlightRowView(flight: Flight, isSelected: Bool = false, onTap: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            // Flight date
            HStack {
                Text(DateFormatter.flightCardDate.string(from: flight.date))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                Spacer()
            }
            .padding(.bottom, 12)
            
            // Main flight info section
            HStack(spacing: 16) {
                // Departure
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateFormatter.flightTime.string(from: flight.date))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.departure.code)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.departure.city)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Center airplane icon and duration
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(themeManager.currentTheme.colors.text)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "airplane")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.colors.background)
                            .rotationEffect(.degrees(90))
                    }
                    
                    Text("2h 30m")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Arrival
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DateFormatter.flightTimeArrival.string(from: Calendar.current.date(byAdding: .hour, value: 2, to: flight.date) ?? flight.date))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.arrival.code)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.arrival.city)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 16)
            
            // Bottom section with flight details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Airlines")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.airline ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Flight no")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.flightNumber)
                        .font(.system(size: 14, weight: .medium))
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
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text(flight.departure.code)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(flight.departure.city)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "airplane")
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(flight.arrival.code)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(flight.arrival.city)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Status: \(flight.status.displayName)")
                    .font(.caption)
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