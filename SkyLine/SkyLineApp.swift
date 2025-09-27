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
    
    var body: some Scene {
        WindowGroup {
            Group {
                if case .authenticated = authService.authenticationState {
                    ContentView()
                        .environmentObject(themeManager)
                        .environmentObject(flightStore)
                        .environmentObject(authService)
                } else {
                    AuthenticationView()
                        .environmentObject(themeManager)
                        .environmentObject(authService)
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
        
        // Configure Status Bar Style globally
        UIApplication.shared.statusBarStyle = theme == .light ? .darkContent : .lightContent
    }
}