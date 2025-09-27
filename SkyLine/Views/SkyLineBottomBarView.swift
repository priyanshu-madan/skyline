//
//  SkyLineBottomBarView.swift
//  SkyLine
//
//  Bottom bar view replicating FindMyBottomBar structure
//

import SwiftUI

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
                .padding(.top, 15)
                .padding(.leading, 10)
            }
            .padding(15)
            
            // Tab-specific content
            switch tab {
            case .globe:
                GlobeTabContent()
            case .flights:
                FlightsTabContent()
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
                .foregroundStyle(activeTab == tab ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                    .foregroundColor(.blue)
                
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
                        .foregroundColor(.blue)
                    
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
                        FlightRowView(flight: flight)
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
                    .foregroundColor(.blue)
                
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
                    .foregroundColor(.blue)
                
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
    
    @ViewBuilder
    func FlightRowView(flight: Flight) -> some View {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(8)
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
    SkyLineBottomBarView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}