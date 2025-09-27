//
//  ContentView.swift
//  SkyLine
//
//  Created by Priyanshu Madan on 7/14/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var authService: AuthenticationService
    @State private var showBottomBar: Bool = true
    
    var body: some View {
        // Background Globe View (replaces Map in original)
        WebViewGlobeView()
            .environmentObject(themeManager)
            .environmentObject(flightStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .id("mainGlobe") // Force unique instance
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Rectangle()
                    .foregroundStyle(.clear)
                    .frame(height: 60)
            }
            .sheet(isPresented: $showBottomBar) {
                SkyLineBottomBarView()
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    .presentationDetents([.height(80), .fraction(0.6), .large])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.regularMaterial)
                    .presentationCornerRadius(40)
            }
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .accentColor(themeManager.currentTheme.colors.primary)
    }
}


#Preview {
    ContentView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}