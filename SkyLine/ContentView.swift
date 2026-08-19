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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isGlobeReady: Bool
    @State private var selectedDetent: PresentationDetent = .height(80)
    @StateObject private var webViewCoordinator = WebViewCoordinator()
    @State private var retryFlightSelection: (() -> Void)? = nil
    @State private var currentActiveTab: SkyLineTab? = nil

    /// How much of the screen the sheet currently covers. Drives `SkyLineGlobeScrim`
    /// so the veil under the chrome deepens in step with the sheet instead of
    /// snapping. The values mirror the detent set below; `.height(80)` is expressed
    /// as a rough fraction because the scrim only needs the gradient stop, not points.
    private var sheetFraction: CGFloat {
        if selectedDetent == .large { return 0.94 }
        if selectedDetent == .fraction(0.6) { return 0.60 }
        if selectedDetent == .fraction(0.3) { return 0.30 }
        if selectedDetent == .fraction(0.2) { return 0.20 }
        return 0.10 // .height(80), the resting state
    }

    var body: some View {
        ZStack {
            // Background Globe View
            WebViewGlobeView(coordinator: webViewCoordinator, currentTab: currentActiveTab)
                .environmentObject(themeManager)
                .environmentObject(flightStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)

            // Glass needs predictable luminance under it, and a live 3D globe on a
            // black field is not that — unscrimmed glass over it reads as muddy grey.
            // This sits between the globe and the sheet so the floating tab bar and
            // any other chrome stay legible as the globe rotates underneath.
            SkyLineGlobeScrim(sheetFraction: sheetFraction)
                .environmentObject(themeManager)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sheetFraction)

            // Bottom sheet with tabs
            Color.clear
                .sheet(isPresented: $isGlobeReady) {
                SkyLineBottomBarView(
                    onFlightSelected: handleFlightSelection,
                    onTabSelected: handleTabSelection,
                    onGlobeReset: resetGlobeView,
                    selectedDetent: $selectedDetent,
                    onTabChanged: { newTab in
                        print("📱 ContentView received tab change: \(newTab.rawValue)")
                        currentActiveTab = newTab
                        print("📱 ContentView currentActiveTab set to: \(currentActiveTab?.rawValue ?? "nil")")
                    }
                )
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    // Same detent set as before, moved into SkyLineGlass so the
                    // sheet's presentation config lives with the rest of the chrome.
                    // Existing `selectedDetent == .fraction(0.3)` checks still hold.
                    .skylineGlobeSheetChrome(selectedDetent: $selectedDetent)
                    // A `.sheet` is a SEPARATE modal presentation, not a child of
                    // the presenting stack, so it does not reliably inherit
                    // `preferredColorScheme` from the ZStack below. Without this
                    // the tab bar's `.glassEffect` - a system material that
                    // resolves against the environment's colorScheme - renders
                    // light in both themes while the globe behind it goes dark.
                    .preferredColorScheme(themeManager.currentTheme.colorScheme)
            }
        }
        // Hoisted from the sheet host onto the whole stack.
        //
        // `preferredColorScheme` is what makes any dynamic system colour still
        // reachable in a child view resolve against the THEME the user picked
        // rather than the DEVICE appearance — the exact failure mode that gave a
        // white page with dark cards. Applied to `Color.clear` it only covered
        // the sheet; on the ZStack it covers the globe host as well, so the
        // status bar and the WebView's own chrome agree with the palette.
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        // `.tint` rather than the deprecated `.accentColor`. It reaches system
        // controls we do not draw ourselves — the sheet grabber, text-field
        // carets, `.glassProminent` labels — and `primary` is legible on both
        // palettes by construction (5.9:1 light, 7.3:1 dark on background).
        .tint(themeManager.currentTheme.colors.primary)
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            selectedDetent = .fraction(0.3)
        }
    }

    // MARK: - Tab Selection Handler

    private func handleTabSelection() {
        // Expand the sheet when a tab button is tapped. Places opens further than
        // the rest: it is the product surface, and a large title plus a search
        // field plus a row of places does not fit in 20% of the screen.
        // `onTabChanged` fires before this, so `currentActiveTab` is already correct.
        let target: PresentationDetent = currentActiveTab == .places ? .fraction(0.6) : .fraction(0.2)

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            if selectedDetent == .height(80) {
                selectedDetent = target
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
    ContentView(isGlobeReady: .constant(true))
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}