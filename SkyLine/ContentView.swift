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
    @State private var selectedDetent: PresentationDetent = .height(80)
    @StateObject private var webViewCoordinator = WebViewCoordinator()
    @State private var retryFlightSelection: (() -> Void)? = nil
    
    var body: some View {
        // Background Globe View (replaces Map in original)
        WebViewGlobeView(coordinator: webViewCoordinator)
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
                SkyLineBottomBarView(onFlightSelected: handleFlightSelection)
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    .presentationDetents([.height(80), .fraction(0.6), .large], selection: $selectedDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(40)
            }
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .accentColor(themeManager.currentTheme.colors.primary)
    }
    
    // MARK: - Flight Selection Handler
    
    private func handleFlightSelection(_ flight: Flight) {
        // Find the flight index in the sorted flights array
        let sortedFlights = flightStore.sortedFlights
        if let flightIndex = sortedFlights.firstIndex(where: { $0.id == flight.id }) {
            // Enhanced flight selection with better error handling and feedback
            let flightSelectionScript = """
                (function() {
                    try {
                        console.log('🎯 Flight selection requested: index \(flightIndex), flight \(flight.flightNumber)');
                        
                        if (typeof window.focusOnFlight === 'function') {
                            console.log('✅ Focusing on flight at index \(flightIndex): \(flight.flightNumber)');
                            window.focusOnFlight(\(flightIndex));
                            
                            // Send success message back to Swift
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                                window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                    type: 'FLIGHT_FOCUS_SUCCESS',
                                    flightIndex: \(flightIndex),
                                    flightNumber: '\(flight.flightNumber)',
                                    flightId: '\(flight.id)'
                                }));
                            }
                            
                            return true;
                        } else {
                            console.warn('⚠️ focusOnFlight function not available yet, will retry...');
                            
                            // Send retry request back to Swift
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                                window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                    type: 'FLIGHT_FOCUS_RETRY_NEEDED',
                                    flightIndex: \(flightIndex),
                                    flightNumber: '\(flight.flightNumber)',
                                    flightId: '\(flight.id)'
                                }));
                            }
                            
                            return false;
                        }
                    } catch (error) {
                        console.error('❌ Error focusing on flight:', error.message);
                        
                        // Send error message back to Swift
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                            window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                type: 'FLIGHT_FOCUS_ERROR',
                                error: error.message,
                                flightIndex: \(flightIndex),
                                flightNumber: '\(flight.flightNumber)',
                                flightId: '\(flight.id)'
                            }));
                        }
                        
                        return false;
                    }
                })();
            """
            
            webViewCoordinator.evaluateJavaScript(flightSelectionScript)
            
            // Auto-collapse the bottom sheet to show more of the globe
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    selectedDetent = .height(80)
                }
            }
        } else {
            print("❌ Flight not found in sorted flights array: \(flight.flightNumber)")
        }
    }
}


#Preview {
    ContentView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}