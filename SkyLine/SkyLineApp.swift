//
//  SkyLineApp.swift
//  SkyLine
//
//  Created by Priyanshu Madan on 8/24/25.
//

import SwiftUI
import CloudKit
import AuthenticationServices

@main
struct SkyLineApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var flightStore = FlightStore()
    @StateObject private var authService = AuthenticationService.shared
    @State private var isGlobeReady = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch authService.authenticationState {
                    case .authenticated:
                        ContentView(isGlobeReady: $isGlobeReady)
                            .environmentObject(themeManager)
                            .environmentObject(flightStore)
                            .environmentObject(authService)
                            .onAppear {
                                // Sync trip data when user is authenticated
                                Task {
                                    await TripStore.shared.syncIfNeeded()

                                    // Seed initial airline data if needed
                                    await AirlineService.shared.seedInitialAirlines()
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                                // Sync when app comes to foreground
                                Task {
                                    await TripStore.shared.syncIfNeeded()
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GlobeReady"))) { _ in
                                // Hide splash when globe is fully loaded
                                withAnimation(.easeOut(duration: 0.5)) {
                                    isGlobeReady = true
                                }
                            }

                    case .authenticating:
                        // Show loading screen while checking existing authentication
                        AppLoadingView()
                            .environmentObject(themeManager)

                    case .unauthenticated, .error:
                        AuthenticationView()
                            .environmentObject(themeManager)
                            .environmentObject(authService)
                    }
                }

                // Splash overlay - show until globe is ready
                if authService.authenticationState.isAuthenticated && !isGlobeReady {
                    AppLoadingView()
                        .environmentObject(themeManager)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .onAppear {
                // Enable CloudKit background sync
                CloudKitService.shared.enableBackgroundSync()
                
                // Configure immersive navigation and status bars
                configureImmersiveAppearance(for: themeManager.currentTheme)
            }
            .onChange(of: themeManager.currentTheme) { theme in
                // Update bar appearance when theme changes
                configureImmersiveAppearance(for: theme)
            }
        }
    }
    
    // MARK: - Immersive UI Configuration
    
    private func configureImmersiveAppearance(for theme: AppTheme) {
        // Configure Navigation Bar Appearance
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(theme.colors.surface)
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.text),
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.text),
            .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .bold)
        ]
        
        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        
        // Configure Tab Bar Appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(theme.colors.surface)
        
        // Configure tab bar item appearance
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(theme.colors.textSecondary)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.textSecondary),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]
        
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(theme.colors.primary)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.primary),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Configure Status Bar Style for all windows
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = theme == .light ? .light : .dark
            }
        }
    }
}

// MARK: - App Loading View
struct AppLoadingView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Image("SplashScreen")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}

// MARK: - Previews
#Preview("Splash - Light Mode") {
    AppLoadingView()
        .environmentObject(ThemeManager())
        .preferredColorScheme(.light)
}

#Preview("Splash - Dark Mode") {
    AppLoadingView()
        .environmentObject(ThemeManager())
        .preferredColorScheme(.dark)
}