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

            // The scan sheet. Hung off its own `Color.clear` rather than off
            // the surface sheet below, because the bar's "+" is reachable with
            // no surface open at all - presenting from a sheet that is not
            // there would do nothing.
            //
            // `onDismiss` is how the scan gets from here to the confirmation;
            // see `presentScannedPass`.
            Color.clear
                .sheet(isPresented: $isShowingAddFlight, onDismiss: presentScannedPass) {
                    BoardingPassMenuContent()
                        .environmentObject(themeManager)
                        .environmentObject(flightStore)
                        // Its own presentation: it inherits neither the theme
                        // object nor the colour scheme resolved further up.
                        .preferredColorScheme(themeManager.currentTheme.colorScheme)
                        .presentationDetents([.height(280)])
                        .presentationBackground(themeManager.currentTheme.colors.background)
                        .presentationCornerRadius(AppRadius.sheet)
                }

            // Where a scanned pass is confirmed before it becomes a flight.
            //
            // This USED to live inside `SkyLineBottomBarView`, along with the
            // observer that fills it, and that was the bug: the bar view only
            // exists while the surface sheet is up, so a scan started from the
            // globe parsed correctly and was then handed to a view that was not
            // mounted. Nothing appeared and nothing failed. Here it is as
            // durable as the globe.
            //
            // A sibling of the scan sheet rather than a second `.sheet` on the
            // same `Color.clear`: one view presents one sheet.
            Color.clear
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

                                        // Auto-focus on the new flight. This was
                                        // `handleFlightTap`, which lived on the bar
                                        // view and did two things: set that view's
                                        // own flight-detail state, and call back
                                        // here. Only the callback half is reachable
                                        // from outside the sheet, and it is exactly
                                        // this function - so the globe still swings
                                        // to the new flight, but the detail page no
                                        // longer opens by itself.
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            handleFlightSelection(flight)
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
                    // Same reason as the scan sheet above: a separate
                    // presentation resolves system colours against the DEVICE
                    // appearance unless the theme's scheme is restated on it.
                    .preferredColorScheme(themeManager.currentTheme.colorScheme)
                    .onAppear {
                        print("📋 Presenting confirmation sheet with data: \(boardingPassData.summary)")
                    }
                }

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
        // The one listener for a scanned pass, on the one view that is always
        // mounted. `BoardingPassMenuContent` reports its result by posting this
        // notification and then dismissing itself, so whoever observes it has to
        // outlive the scanner - which the bar view did not.
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BoardingPassScanned"))) { notification in
            if let boardingPassData = notification.object as? BoardingPassData {
                Task {
                    await handleBoardingPassScanned(boardingPassData)
                }
            }
        }
    }

    // MARK: - Tab Bar

    /// The bar itself, built once and placed in exactly one of two hosts.
    ///
    /// Identical padding in both, so the swap between "on the globe" and "on the
    /// page" does not move a pixel. `SkyLineFloatingTabBar` is a `struct: View`,
    /// so this property is a placement, not a second copy of the bar's tree.
    private var floatingTabBar: some View {
        SkyLineFloatingTabBar(
            activeTab: $activeTab,
            onSelect: handleTabSelection,
            onAdd: openScanner
        )
            .environmentObject(themeManager)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Boarding Pass Scanning

    /// Opens the scanner. That is the whole action.
    ///
    /// It used to open the Flights surface first and present the scanner a
    /// third of a second later, because the observer for the scan result lived
    /// inside `SkyLineBottomBarView` and only existed while that surface was
    /// up. The observer is on this view now, so the app no longer has to travel
    /// somewhere the user did not ask to go in order to hear the answer.
    private func openScanner() {
        isShowingAddFlight = true
    }

    /// Hands a parked pass to the confirmation sheet once the scanner is gone.
    ///
    /// `BoardingPassMenuContent` posts its result and dismisses itself in the
    /// same turn, so the confirmation would otherwise be asked to present from
    /// this same host while the scanner is still leaving it. `onDismiss` runs
    /// after the dismissal finishes, which is the one ordering here that is
    /// defined rather than hoped for.
    ///
    /// Not observed failing without this - a real scan needs a photo and cannot
    /// be driven headlessly - but presenting into a dismissal is a known way to
    /// lose a sheet, and losing this one is the exact bug being fixed.
    private func presentScannedPass() {
        guard let pending = pendingBoardingPassData else { return }
        pendingBoardingPassData = nil
        scannedBoardingPassData = pending
    }

    /// The scan sheet, presented from the bar's trailing action.
    ///
    /// Reachable from the globe with no surface open, which the header "+" never
    /// was - that one only existed once you had already opened Flights, and it
    /// is gone now that the bar owns this.
    @State private var isShowingAddFlight = false

    /// A parsed pass waiting for the scanner sheet to finish leaving the screen.
    /// Only ever set while `isShowingAddFlight` is true; `presentScannedPass`
    /// empties it.
    @State private var pendingBoardingPassData: BoardingPassData?

    /// The pass being confirmed. Non-nil IS the confirmation sheet being up.
    @State private var scannedBoardingPassData: BoardingPassData?

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

// MARK: - Boarding Pass -> Flight

/// The scan pipeline, moved here from `SkyLineBottomBarView`.
///
/// It sat on a view that only exists while the surface sheet is up, so a scan
/// started from the globe had nowhere to land. Nothing here needs the bar:
/// `createFlightFromBoardingPass` reaches `AirportService.shared`, a singleton,
/// and `combineDateAndTime` is pure.
private extension ContentView {
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
        
        // Show confirmation sheet with compact time pickers by setting the data.
        await MainActor.run {
            if isShowingAddFlight {
                // The scanner posted this and is dismissing itself right now.
                // Park the pass and let `presentScannedPass` put it up once the
                // scanner is off screen, rather than asking one host to present
                // a second sheet while the first is still leaving.
                pendingBoardingPassData = boardingPassData
                isShowingAddFlight = false
                print("📋 Parked scanned pass until the scanner is down: \(boardingPassData.summary)")
            } else {
                scannedBoardingPassData = boardingPassData
                print("📋 Set scannedBoardingPassData to trigger sheet: \(scannedBoardingPassData?.summary ?? "nil")")
            }
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
            // Nil, never 0.0. `Airport.latitude` is already `Double?` and
            // `coordinate` already returns nil for a missing pair - this was
            // forcing a real value where the model allowed none. When the
            // airport lookup failed (its API key dies, or the code is not in
            // the bundled table) the flight was saved at 0°N 0°E and synced to
            // iCloud permanently, drawing an arc through the Gulf of Guinea.
            latitude: depCoordinates?.latitude,
            longitude: depCoordinates?.longitude,
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
            latitude: arrCoordinates?.latitude,
            longitude: arrCoordinates?.longitude,
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
}

#Preview {
    ContentView(isGlobeReady: .constant(true))
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}