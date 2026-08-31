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
    /// Seeded to the height the primary surface opens at, because the sheet is
    /// no longer presented until something asks it to be. `.height(80)` was the
    /// old resting height and is gone from the detent set with the resting
    /// state itself.
    @State private var selectedDetent: PresentationDetent = .fraction(0.6)
    @StateObject private var webViewCoordinator = WebViewCoordinator()
    @State private var retryFlightSelection: (() -> Void)? = nil

    /// The surface on screen, and the single source of truth for it.
    ///
    /// It lives up here because the two things that need it are now on opposite
    /// sides of a presentation boundary: the bar is in this ZStack when the
    /// sheet is down, and inside the sheet when it is up. It used to be `@State`
    /// in `SkyLineBottomBarView` with an `onTabChanged` callback mirroring it
    /// into a second `@State` here for the globe — two copies and a message
    /// between them. One value, three readers.
    ///
    /// Starts at `SkyLineTab.primary` rather than nil, so the globe is asked for
    /// the right data on its first update instead of the tab-less default.
    @State private var activeTab: SkyLineTab = .primary

    /// Whether a surface is open, which is now the same question as whether the
    /// sheet is presented at all.
    ///
    /// The sheet used to sit permanently at an 80pt detent and the app "rested"
    /// there. It cannot any more, and the reason is measured rather than
    /// assumed: at a short detent iOS 26 draws a sheet as an INSET FLOATING
    /// PLATTER — on this device 26pt in from each side, 22pt up from the bottom,
    /// filled `#1C1C1E` — and `presentationBackground` cannot remove it. Painted
    /// solid red the platter turns red; painted 35% red it comes back
    /// rgb(107,41,47), which is red over that grey and not red over the globe.
    /// The platter is behind the presentation background, so the modifier cannot
    /// reach it.
    ///
    /// That platter is the rounded rectangle the bar appeared to be nested in.
    /// It measures identically with the bar present and with the bar gone, so it
    /// was never the tab bar's own container. A sheet is also bottom-anchored
    /// and swallows touches, so nothing behind it is tappable: with the bar in
    /// this ZStack and the sheet resting over it, a tap on the bar reached the
    /// sheet and the bar did nothing.
    ///
    /// So the sheet comes DOWN when there is no surface open. The globe then has
    /// nothing over it but the bar.
    @State private var isSurfaceOpen = false

    /// `isPresented` for the sheet, gated on the globe being ready as well.
    ///
    /// `isGlobeReady` still has to be able to force the sheet down on its own —
    /// `SkyLineApp` pulls it low so onboarding can be presented over a stack the
    /// sheet would otherwise sit above.
    private var isSheetPresented: Binding<Bool> {
        Binding(
            get: { isGlobeReady && isSurfaceOpen },
            // Covers the drag-to-dismiss as well as any programmatic close, so
            // the bar comes back to the globe the moment the sheet leaves.
            set: { isSurfaceOpen = $0 }
        )
    }

    /// How much of the screen the sheet currently covers. Drives `SkyLineGlobeScrim`
    /// so the veil under the chrome deepens in step with the sheet instead of
    /// snapping. The values mirror the detent set in `skylineGlobeSheetChrome`.
    private var sheetFraction: CGFloat {
        // Closed. Not zero: the scrim is also what gives the floating bar's
        // glass something with predictable luminance to sample, and a live globe
        // on a black field is not that.
        guard isSurfaceOpen else { return 0.10 }

        if selectedDetent == .large { return 0.94 }
        if selectedDetent == .fraction(0.6) { return 0.60 }
        return 0.30 // .fraction(0.3), the shortest detent the sheet has
    }

    var body: some View {
        ZStack {
            // Background Globe View
            WebViewGlobeView(coordinator: webViewCoordinator, currentTab: activeTab)
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

            // Bottom sheet, now carrying ONLY the active surface, and only while
            // there IS one. The bar is not in it; see `floatingTabBar`.
            Color.clear
                .sheet(isPresented: isSheetPresented) {
                SkyLineBottomBarView(
                    activeTab: $activeTab,
                    selectedDetent: $selectedDetent,
                    onFlightSelected: handleFlightSelection,
                    onTabSelected: handleTabSelection,
                    onGlobeReset: resetGlobeView
                )
                    .environmentObject(themeManager)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    // The bar, over the page, for as long as the page is up.
                    //
                    // `safeAreaInset` rather than an overlay: it floats the bar
                    // above the sheet's own bottom safe area AND shortens the
                    // page's safe area by the same amount, so a scrolled list
                    // ends above the glass instead of under it. This is the one
                    // and only other place the bar is built, and it is mutually
                    // exclusive with the ZStack copy — the sheet is presented
                    // exactly when that one is not.
                    .safeAreaInset(edge: .bottom) {
                        floatingTabBar
                    }
                    // Same detent set as before minus `.height(80)`, moved into
                    // SkyLineGlass so the sheet's presentation config lives with
                    // the rest of the chrome. Existing
                    // `selectedDetent == .fraction(0.3)` checks still hold.
                    .skylineGlobeSheetChrome(selectedDetent: $selectedDetent)
                    // A `.sheet` is a SEPARATE modal presentation, not a child of
                    // the presenting stack, so it does not reliably inherit
                    // `preferredColorScheme` from the ZStack below. Without this
                    // any system material inside it resolves against the device
                    // appearance and renders light in both themes while the globe
                    // behind it goes dark.
                    .preferredColorScheme(themeManager.currentTheme.colorScheme)
            }

            // THE BAR, floating on the globe, while nothing is open over it.
            //
            // Hidden rather than covered when the sheet comes up: the sheet
            // would occlude it and eat its taps anyway, and the copy inside the
            // sheet stands in the same place with the same padding, so the swap
            // does not move anything on screen.
            if !isSurfaceOpen {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    floatingTabBar
                }
                .transition(.identity)
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

    // MARK: - Tab Bar

    /// The bar itself, built once and placed in exactly one of two hosts.
    ///
    /// Identical padding in both, so the swap between "on the globe" and "on the
    /// page" does not move a pixel. `SkyLineFloatingTabBar` is a `struct: View`,
    /// so this property is a placement, not a second copy of the bar's tree.
    private var floatingTabBar: some View {
        SkyLineFloatingTabBar(activeTab: $activeTab, onSelect: handleTabSelection)
            .environmentObject(themeManager)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)
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

    /// A slot was tapped, from the bar or from a surface asking to be opened.
    ///
    /// The tab arrives as an ARGUMENT rather than being read back off
    /// `activeTab`. The bar writes that binding in the same update it calls
    /// this, and a read inside that update is not guaranteed to see the write —
    /// which is exactly the ordering hazard the old `onTabChanged`-then-
    /// `onTabSelected` pair existed to work around.
    private func handleTabSelection(_ tab: SkyLineTab) {
        // Every surface opens at the same height now, and the reason is the
        // bar. It hangs off the sheet as a bottom safe-area inset, so it costs
        // roughly 110pt of page whichever surface is up — which is most of a
        // 0.3 sheet. Profile used to open at the short detent because it was a
        // header and an avatar; at 0.3 with the bar in place the avatar is cut
        // in half and the stats row is below the glass. 0.6 is the smallest
        // height that shows a whole surface.
        //
        // `.fraction(0.3)` is still in the detent set: it is the peek the user
        // can drag DOWN to on the way to dismissing the sheet, which is a
        // different thing from the height a tap opens it at.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            activeTab = tab

            // Only on the way OPEN. Tapping the other slot while a page is
            // already up switches the page and leaves the height where the user
            // dragged it, which is what the old `selectedDetent == .height(80)`
            // guard did back when the closed state was a detent rather than an
            // absent sheet.
            if !isSurfaceOpen {
                selectedDetent = .fraction(0.6)
                isSurfaceOpen = true
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