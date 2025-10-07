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
                SkyLineBottomBarView(
                    onFlightSelected: handleFlightSelection,
                    onTabSelected: handleTabSelection,
                    onGlobeReset: resetGlobeView,
                    selectedDetent: $selectedDetent
                )
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    .presentationDetents([.height(80), .fraction(0.2), .fraction(0.3), .fraction(0.6), .large], selection: $selectedDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(40)
            }
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .accentColor(themeManager.currentTheme.colors.primary)
    }
    
    // MARK: - Flight Selection Handler
    
    private func handleFlightSelection(_ flight: Flight) {
        print("🎯 Swift: Flight selection requested: \(flight.flightNumber) (ID: \(flight.id))")
        print("🎯 Swift: Flight departure: \(flight.departure.code) → \(flight.arrival.code)")
        
        // Use flight ID and number for reliable identification instead of array index
        let flightSelectionScript = """
            (function() {
                try {
                    console.log('🎯 JS: Flight selection requested: \(flight.flightNumber) (ID: \(flight.id))');
                    console.log('🔍 JS: Available functions:', typeof window.focusOnFlightById, typeof window.updateFlightData);
                    console.log('📊 JS: Current arcsData length:', window.arcsData ? window.arcsData.length : 'undefined');
                    
                    if (typeof window.focusOnFlightById === 'function') {
                        console.log('✅ Focusing on flight by ID: \(flight.id)');
                        const success = window.focusOnFlightById('\(flight.id)', '\(flight.flightNumber)');
                        
                        if (success) {
                            // Send success message back to Swift
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                                window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                    type: 'FLIGHT_FOCUS_SUCCESS',
                                    flightNumber: '\(flight.flightNumber)',
                                    flightId: '\(flight.id)'
                                }));
                            }
                            return true;
                        } else {
                            console.warn('⚠️ Flight not found in globe data: \(flight.flightNumber)');
                            
                            // Send not found message back to Swift
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                                window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                    type: 'FLIGHT_NOT_FOUND',
                                    flightNumber: '\(flight.flightNumber)',
                                    flightId: '\(flight.id)'
                                }));
                            }
                            return false;
                        }
                    } else {
                        console.warn('⚠️ focusOnFlightById function not available yet, will retry...');
                        
                        // Send retry request back to Swift
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                            window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                                type: 'FLIGHT_FOCUS_RETRY_NEEDED',
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
                            flightNumber: '\(flight.flightNumber)',
                            flightId: '\(flight.id)'
                        }));
                    }
                    
                    return false;
                }
            })();
        """
        
        print("🚀 Swift: Executing JavaScript flight selection")
        webViewCoordinator.evaluateJavaScript(flightSelectionScript)
        
        // Expand sheet to show flight details
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedDetent = .fraction(0.3)
        }
    }
    
    // MARK: - Tab Selection Handler
    
    private func handleTabSelection() {
        // Expand sheet to 20% height when tab buttons are tapped
        withAnimation(.easeInOut(duration: 0.3)) {
            if selectedDetent == .height(80) {
                selectedDetent = .fraction(0.2)
            }
        }
    }
    
    // MARK: - Globe Reset Handler
    
    private func resetGlobeView() {
        print("🌍 Swift: Resetting globe view")
        
        let resetScript = """
            (function() {
                try {
                    console.log('🌍 JS: Resetting globe view');
                    
                    // Clear flight highlighting using the proper function
                    if (typeof window.clearFlightHighlight === 'function') {
                        console.log('✅ Clearing flight highlighting');
                        window.clearFlightHighlight();
                    }
                    
                    // Reset globe rotation and position if function exists
                    if (typeof window.resetRotation === 'function') {
                        console.log('✅ Resetting rotation and position');
                        window.resetRotation();
                    }
                    
                    console.log('🌍 Globe reset completed successfully');
                    return true;
                } catch (error) {
                    console.error('❌ Error resetting globe:', error.message);
                    return false;
                }
            })();
        """
        
        webViewCoordinator.evaluateJavaScript(resetScript)
    }
}


#Preview {
    ContentView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}