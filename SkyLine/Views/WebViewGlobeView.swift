//
//  WebViewGlobeView.swift
//  SkyLine
//
//  Globe.gl WebView implementation matching original Expo app functionality
//

import SwiftUI
import WebKit
import CoreLocation

struct WebViewGlobeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @StateObject private var tripStore = TripStore.shared
    @StateObject private var placeStore = PlaceStore.shared
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var coordinator: WebViewCoordinator
    let currentTab: SkyLineTab?
    @State private var isGlobeReady = false
    @State private var isAutoRotating = true
    @State private var lastFlightDataHash: String = ""
    @State private var lastVisitedCitiesHash: String = ""
    @State private var lastTripLocationsHash: String = ""
    @State private var lastTabHash: String = ""
    @State private var lastPlacePointsHash: String = ""
    
    
    // Globe background color matching the WebGL globe theme
    private var globeBackgroundColor: Color {
        return themeManager.currentTheme == .light ? 
            Color(red: 240/255, green: 240/255, blue: 240/255) :  // #F0F0F0
            Color(red: 0/255, green: 0/255, blue: 17/255)        // #000011
    }
    
    var body: some View {
        ZStack {
            // Globe.gl WebView - Full Screen with Status Bar
            WebView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
                .onAppear {
                    if !isGlobeReady {
                        setupWebView()
                    } else {
                        updateGlobeTheme()
                    }
                }
                .onChange(of: themeManager.currentTheme) { _ in
                    updateGlobeTheme()
                }
                .onChange(of: flightStore.flights) { newFlights in
                    let newFlightHash = createFlightDataHash(flights: newFlights)
                    
                    if newFlightHash != lastFlightDataHash {
                        lastFlightDataHash = newFlightHash
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            updateGlobeData()
                        }
                    }
                }
                .onChange(of: tripStore.visitedCities) { newCities in
                    let newCitiesHash = createVisitedCitiesHash(cities: newCities)

                    if newCitiesHash != lastVisitedCitiesHash {
                        lastVisitedCitiesHash = newCitiesHash
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            updateGlobeData()
                        }
                    }
                }
                .onChange(of: tripStore.tripLocations) { newLocations in
                    let newLocationsHash = createTripLocationsHash(locations: newLocations)

                    if newLocationsHash != lastTripLocationsHash {
                        lastTripLocationsHash = newLocationsHash
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            updateGlobeData()
                        }
                    }
                }
                .onChange(of: reduceMotion) {
                    applyMotionPreference()
                }
                .onChange(of: placeStore.places) {
                    schedulePlaceGlobeUpdate()
                }
                .onChange(of: placeStore.visits) {
                    schedulePlaceGlobeUpdate()
                }
                .onChange(of: currentTab) { newTab in
                    print("🌍 WebViewGlobeView onChange triggered with: \(newTab?.rawValue ?? "nil")")
                    let newTabHash = newTab?.rawValue ?? "none"
                    
                    if newTabHash != lastTabHash {
                        lastTabHash = newTabHash
                        print("🌍 WebViewGlobeView scheduling globe update for tab: \(newTabHash)")
                        
                        // Capture the tab value explicitly to avoid closure capture issues
                        let capturedTab = newTab
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            print("🌍 WebViewGlobeView executing delayed update for captured tab: \(capturedTab?.rawValue ?? "nil")")
                            self.updateGlobeDataWithTab(capturedTab)
                        }
                    }
                }
                .onReceive(AirportService.shared.coordinatesUpdated) { airportCode in
                    // EMERGENCY FIX: Disable updateFlightCoordinates calls to stop infinite loop
                    print("⚠️ Airport coordinates updated for \(airportCode) but enhancement disabled")

                    // Only update the globe view data, don't trigger flight coordinate updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        updateGlobeData()
                    }
                }

            // Status bar background overlay
            VStack {
                Rectangle()
                    .fill(globeBackgroundColor)
                    .frame(maxWidth: .infinity, maxHeight: 0)
                    .background(globeBackgroundColor)
                    .ignoresSafeArea(.container, edges: [.top])
                Spacer()
            }
            
            // Control Panel
            VStack {
                HStack {
                    Spacer()
                    controlPanel
                        .padding(.top, 50) // Move buttons down to avoid status bar
                }
                
                Spacer()
            }
            .padding()
            
        }
        .background(globeBackgroundColor)
        .ignoresSafeArea(.container, edges: [.top, .horizontal, .bottom])
    }
    
    // MARK: - Control Panel
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Theme Toggle
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                themeManager.toggleTheme()
            }) {
                Image(systemName: themeManager.currentTheme == .light ? "moon.fill" : "sun.max.fill")
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            // Auto-Rotation Toggle
            Button(action: toggleAutoRotation) {
                Image(systemName: isAutoRotating ? "pause.circle.fill" : "play.circle.fill")
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isAutoRotating ? themeManager.currentTheme.colors.success : themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            
            
            // Reset Globe View
            Button(action: resetGlobe) {
                Image(systemName: "globe")
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.textSecondary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - Data Change Detection
    
    private func createFlightDataHash(flights: [Flight]) -> String {
        let flightIds = flights.map { flight in
            "\(flight.id)-\(flight.flightNumber)-\(flight.departure.code)-\(flight.arrival.code)"
        }.sorted().joined(separator: "|")
        
        return flightIds
    }
    
    private func createVisitedCitiesHash(cities: [VisitedCity]) -> String {
        let cityIds = cities.map { city in
            "\(city.name)-\(city.latitude)-\(city.longitude)-\(city.lastVisited.timeIntervalSince1970)"
        }.sorted().joined(separator: "|")

        return cityIds
    }

    /// Places run through the same hash-then-debounce guard as flights,
    /// cities and trip locations. `PlaceStore.globePointsHash` already reduces
    /// the log to the only three things the globe draws - id, verdict, visit
    /// count - so a note edit or a rename never repaints the globe.
    private func schedulePlaceGlobeUpdate() {
        let newHash = placeStore.globePointsHash

        if newHash != lastPlacePointsHash {
            lastPlacePointsHash = newHash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                updateGlobeData()
            }
        }
    }

    private func createTripLocationsHash(locations: [TripLocation]) -> String {
        let locationIds = locations.map { location in
            "\(location.tripId)-\(location.name)-\(location.status)-\(location.latitude)-\(location.longitude)"
        }.sorted().joined(separator: "|")

        return locationIds
    }
    
    // MARK: - WebView Setup and Communication
    
    private func setupWebView() {
        coordinator.onMessageReceived = handleWebViewMessage
        
        if !isGlobeReady {
            coordinator.webView?.reload()
        }
        
        // Set initial theme immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let themeString = self.themeManager.currentTheme == .light ? "light" : "dark"
            self.coordinator.evaluateJavaScript("""
                if (window.setTheme) {
                    window.setTheme('\(themeString)');
                } else {
                    window.initialTheme = '\(themeString)';
                }
            """)
        }
        
        // Test for globe functions and mark ready when available
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.coordinator.evaluateJavaScript("""
                if (typeof window.updateFlightData === 'function') {
                    console.log('Globe functions ready');
                    window.ReactNativeWebView?.postMessage('Globe functions ready');
                } else {
                    console.log('Globe functions NOT ready');
                    window.ReactNativeWebView?.postMessage('Globe functions NOT ready');
                }
            """)
        }
        
        // Mark as ready after delay to ensure globe.gl is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if !self.isGlobeReady {
                self.isGlobeReady = true
                self.updateGlobeTheme()
                self.updateGlobeData()
                self.lastFlightDataHash = self.createFlightDataHash(flights: self.flightStore.flights)
                self.lastVisitedCitiesHash = self.createVisitedCitiesHash(cities: self.tripStore.visitedCities)
                self.lastTripLocationsHash = self.createTripLocationsHash(locations: self.tripStore.tripLocations)
                self.lastPlacePointsHash = self.placeStore.globePointsHash
                self.applyMotionPreference()

                // Notify app that globe is fully ready
                NotificationCenter.default.post(name: NSNotification.Name("GlobeReady"), object: nil)
            }
        }
    }
    
    private func handleWebViewMessage(_ message: String) {
        // Handle simple string messages
        if message == "Globe ready" || message == "Globe ready (fallback)" {
            DispatchQueue.main.async {
                if !self.isGlobeReady {
                    self.isGlobeReady = true
                    self.updateGlobeTheme()
                }
                // Wait a bit longer to ensure everything is settled
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.updateGlobeData()
                    self.lastFlightDataHash = self.createFlightDataHash(flights: self.flightStore.flights)
                    self.lastVisitedCitiesHash = self.createVisitedCitiesHash(cities: self.tripStore.visitedCities)
                    self.lastTripLocationsHash = self.createTripLocationsHash(locations: self.tripStore.tripLocations)
                    self.lastPlacePointsHash = self.placeStore.globePointsHash
                    self.applyMotionPreference()

                    // Notify app that globe is fully ready
                    NotificationCenter.default.post(name: NSNotification.Name("GlobeReady"), object: nil)
                }
            }
            return
        }

        if message == "Globe functions ready" {
            DispatchQueue.main.async {
                if !self.isGlobeReady {
                    self.isGlobeReady = true
                    self.updateGlobeTheme()
                    self.updateGlobeData()
                    self.applyMotionPreference()

                    // Notify app that globe is fully ready
                    NotificationCenter.default.post(name: NSNotification.Name("GlobeReady"), object: nil)
                }
            }
            return
        }
        
        // Try to parse JSON messages
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("❌ Failed to parse WebView message: \(message)")
            return
        }
        
        print("📨 WebView message received: \(type)")
        
        switch type {
        case "AUTO_ROTATE_TOGGLED":
            if let autoRotate = json["autoRotate"] as? Bool {
                DispatchQueue.main.async {
                    self.isAutoRotating = autoRotate
                }
            }
            
        case "FLIGHT_FOCUS_SUCCESS":
            if let flightNumber = json["flightNumber"] as? String,
               let flightId = json["flightId"] as? String {
                print("✅ Flight focus successful: \(flightNumber) (ID: \(flightId))")
            }
            
        case "FLIGHT_FOCUS_RETRY_NEEDED":
            if let flightNumber = json["flightNumber"] as? String,
               let flightId = json["flightId"] as? String {
                print("🔄 Retrying flight focus for: \(flightNumber) (ID: \(flightId))")
                // Retry the focus after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.coordinator.evaluateJavaScript("""
                        if (window.focusOnFlightById) {
                            console.log('Retry: Focusing on flight by ID: \(flightId)');
                            window.focusOnFlightById('\(flightId)', '\(flightNumber)');
                        }
                    """)
                }
            }
            
        case "FLIGHT_FOCUS_ERROR":
            if let error = json["error"] as? String,
               let flightNumber = json["flightNumber"] as? String {
                print("❌ Flight focus error for \(flightNumber): \(error)")
            }
            
        case "FLIGHT_NOT_FOUND":
            if let flightNumber = json["flightNumber"] as? String,
               let flightId = json["flightId"] as? String {
                print("⚠️ Flight not found in globe data: \(flightNumber) (ID: \(flightId))")
                // Try to refresh flight data and retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.updateGlobeData()
                    
                    // Retry after data refresh
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.coordinator.evaluateJavaScript("""
                            if (window.focusOnFlightById) {
                                console.log('Retry after data refresh: \(flightId)');
                                window.focusOnFlightById('\(flightId)', '\(flightNumber)');
                            }
                        """)
                    }
                }
            }
            
        case "PLACE_SELECTED":
            if let placeId = json["placeId"] as? String {
                let name = json["name"] as? String ?? "Unknown"
                print("📍 Place selected from globe: \(name) (\(placeId))")
            }

        case "FLIGHT_SELECTED":
            if let flight = json["flight"] as? [String: Any],
               let flightNumber = flight["flightNumber"] as? String {
                print("🎯 Flight selected from globe: \(flightNumber)")
            }
            
        default:
            print("⚠️ Unknown WebView message type: \(type)")
        }
    }
    
    private func updateGlobeTheme() {
        guard isGlobeReady else { return }
        
        let themeString = themeManager.currentTheme == .light ? "light" : "dark"
        coordinator.evaluateJavaScript("""
            if (window.setTheme) {
                window.setTheme('\(themeString)');
            }
        """)
    }
    
    private func updateGlobeData() {
        updateGlobeDataWithTab(currentTab)
    }
    
    private func updateGlobeDataWithTab(_ tab: SkyLineTab?) {
        guard isGlobeReady else { return }
        
        // Determine what data to show based on provided tab.
        // Flights and trip countries are context and stay tab-scoped. Places
        // are not: the log the user built is on the globe on every tab.
        let shouldShowFlights = tab == .flights || tab == .profile || tab == nil  // Show flights on Flights tab
        let shouldShowCities = tab == .trips || tab == .profile || tab == nil    // Show cities on Trips tab

        print("🎯 Globe data update - Tab: \(tab?.rawValue ?? "none"), Show flights: \(shouldShowFlights), Show cities: \(shouldShowCities)")
        
        // Prepare flight data
        let flightPaths = shouldShowFlights ? flightStore.flights.compactMap { flight -> [String: Any]? in
            guard let depLat = flight.departure.coordinate?.latitude,
                  let depLng = flight.departure.coordinate?.longitude,
                  let arrLat = flight.arrival.coordinate?.latitude,
                  let arrLng = flight.arrival.coordinate?.longitude else {
                return nil
            }
            
            return [
                "startLat": depLat,
                "startLng": depLng,
                "endLat": arrLat,
                "endLng": arrLng,
                "flightNumber": flight.flightNumber,
                "flightId": flight.id,
                "status": flight.status.rawValue,
                "departureCode": flight.departure.code,
                "arrivalCode": flight.arrival.code
            ]
        } : []
        
        // Collect departure and arrival airports (only when showing flights).
        // No colour is sent: every colour on the globe now comes from either
        // the desaturated palette in the JS or Verdict.globeHexColor, never
        // from a hex literal wired in over here.
        let departureAirports = shouldShowFlights ? flightStore.flights.compactMap { flight -> [String: Any]? in
            guard let coordinate = flight.departure.coordinate else { return nil }
            return [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude,
                "name": flight.departure.code
            ]
        } : []

        let arrivalAirports = shouldShowFlights ? flightStore.flights.compactMap { flight -> [String: Any]? in
            guard let coordinate = flight.arrival.coordinate else { return nil }
            return [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude,
                "name": flight.arrival.code
            ]
        } : []
        
        // Combine and remove duplicates manually
        var airportsDict: [String: [String: Any]] = [:]
        for airport in departureAirports + arrivalAirports {
            if let name = airport["name"] as? String {
                airportsDict[name] = airport
            }
        }
        let airports = Array(airportsDict.values)
        
        // Add visited cities from completed trips (only when showing cities)
        let visitedCities = shouldShowCities ? tripStore.visitedCities.map { city -> [String: Any] in
            return [
                "lat": city.latitude,
                "lng": city.longitude,
                "name": city.name,
                "isVisited": true,
                "tripCount": city.tripCount,
                "lastVisited": city.lastVisited.timeIntervalSince1970
            ]
        } : []

        // Add all trip locations with status (only when showing cities)
        let tripLocations = shouldShowCities ? tripStore.tripLocations.map { location -> [String: Any] in
            // `status` travels; the colour does not. The globe picks the tint
            // for a trip country out of its own palette, which is the only
            // place the country colours are defined.
            return [
                "lat": location.latitude,
                "lng": location.longitude,
                "name": location.name,
                "state": location.state ?? "",
                "country": location.country ?? "",
                "tripId": location.tripId,
                "status": location.status,
                "startDate": location.startDate.timeIntervalSince1970,
                "endDate": location.endDate.timeIntervalSince1970
            ]
        } : []
        
        // Places: one dot per logged place, coloured by verdict. The payload
        // shape and the JSON encoding both live in PlaceQueries so the globe
        // and any future map share exactly one definition of a place point.
        let placePoints = placeStore.globePoints
        let placesJson = PlaceGlobePoint.jsonString(from: placePoints)

        guard let flightPathsData = try? JSONSerialization.data(withJSONObject: flightPaths),
              let airportsData = try? JSONSerialization.data(withJSONObject: airports),
              let visitedCitiesData = try? JSONSerialization.data(withJSONObject: visitedCities),
              let tripLocationsData = try? JSONSerialization.data(withJSONObject: tripLocations),
              let flightPathsJson = String(data: flightPathsData, encoding: .utf8),
              let airportsJson = String(data: airportsData, encoding: .utf8),
              let visitedCitiesJson = String(data: visitedCitiesData, encoding: .utf8),
              let tripLocationsJson = String(data: tripLocationsData, encoding: .utf8) else {
            return
        }
        
        // One update path into the WebView. `places` is appended on the end of
        // the existing argument list so the five-argument fallback below keeps
        // working. Wrapped in an IIFE because `evaluateJavaScript` runs each
        // script in the page's global scope, where a repeated top-level `const`
        // would throw on the second update.
        let tabMode = tab?.rawValue ?? "all"
        let jsCode = """
            (function() {
                var flights = \(flightPathsJson);
                var airports = \(airportsJson);
                var visitedCities = \(visitedCitiesJson);
                var tripLocations = \(tripLocationsJson);
                var places = \(placesJson);

                console.log('🎯 Globe update for tab mode: \(tabMode)', {
                    flights: flights.length,
                    places: places.length,
                    tripLocations: tripLocations.length
                });

                if (window.updateGlobeData) {
                    window.updateGlobeData(flights, airports, visitedCities, tripLocations, '\(tabMode)', places);
                } else if (window.updateFlightData) {
                    console.log('Falling back to updateFlightData function...');
                    window.updateFlightData(flights, airports);
                } else {
                    console.error('Neither window.updateGlobeData nor window.updateFlightData found!');
                }
            })();
        """

        coordinator.evaluateJavaScript(jsCode)
    }
    
    // MARK: - Control Actions
    
    private func toggleAutoRotation() {
        // Drive the state from Swift so the play/pause icon is the truth
        // rather than a guess: the WebView only reports back on tap-to-focus.
        isAutoRotating.toggle()
        setGlobeAutoRotate(isAutoRotating)
    }

    /// Reduce Motion stops the idle spin. The globe stays draggable - the
    /// setting is about movement the user did not ask for, not interaction.
    private func applyMotionPreference() {
        guard isGlobeReady else { return }
        isAutoRotating = !reduceMotion
        setGlobeAutoRotate(isAutoRotating)
    }

    private func setGlobeAutoRotate(_ enabled: Bool) {
        coordinator.evaluateJavaScript("""
            if (window.setAutoRotate) {
                window.setAutoRotate(\(enabled));
            } else if (window.toggleAutoRotate) {
                window.toggleAutoRotate();
            }
        """)
    }
    
    
    private func resetGlobe() {
        coordinator.evaluateJavaScript("""
            if (window.resetRotation) {
                window.resetRotation();
            }
        """)
    }
    
    
    private func statusColor(for status: FlightStatus) -> Color {
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

// MARK: - WebView Coordinator

class WebViewCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView?
    var onMessageReceived: ((String) -> Void)?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        
        // Add message handler for JavaScript communication
        configuration.userContentController.add(self, name: "reactNativeWebView")
        
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
        
        let htmlString = getSimpleTestHTML()
        webView?.loadHTMLString(htmlString, baseURL: nil)
    }
    
    private func getSimpleTestHTML() -> String {
        // Load countries GeoJSON from bundle for offline support
        var countriesJSON = "{}"
        if let path = Bundle.main.path(forResource: "countries", ofType: "geojson"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let jsonString = String(data: data, encoding: .utf8) {
            countriesJSON = jsonString
        } else {
            print("⚠️ Failed to load countries.geojson from bundle")
        }

        return """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script type="text/javascript">
    // Preload countries data from bundle (offline support)
    window.COUNTRIES_DATA = \(countriesJSON);
  </script>
  <style>
    body {
      margin: 0;
      padding: 0;
      background: #000011;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif;
    }
    #globeViz {
      width: 100vw;
      height: 100vh;
    }
    /* Boot status: bare type, no pill. It is hidden the moment the globe is
       ready, and anything with a border fights the glass the app lays on top. */
    .status {
      position: absolute;
      top: 20px;
      left: 20px;
      color: rgba(255, 255, 255, 0.7);
      font-size: 11px;
      letter-spacing: 0.02em;
      text-shadow: 0 0 3px rgba(0, 0, 0, 0.95), 0 1px 4px rgba(0, 0, 0, 0.8);
      z-index: 1000;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div class="status" id="status">Starting...</div>
  <div id="globeViz"></div>

  <script>
    console.log('🚀 HTML loaded');
    document.getElementById('status').innerHTML = 'HTML loaded, testing basic JS...';

    // Test basic functionality
    setTimeout(() => {
      document.getElementById('status').innerHTML = 'Basic JS working, loading Globe.gl...';
      console.log('✅ Basic JavaScript working');
    }, 1000);

    setTimeout(() => {
      document.getElementById('status').innerHTML = 'Loading Globe.gl library...';
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/globe.gl';
      script.onload = function() {
        console.log('✅ Globe.gl loaded successfully');
        document.getElementById('status').innerHTML = 'Globe.gl loaded, creating globe...';

        try {
          // ────────────────────────────────────────────────────────────────
          // Palette
          //
          // The globe is context; the verdicts are the content. Every
          // structural colour below is the app palette pulled down to roughly
          // 60% saturation, so the three verdict colours Swift pushes in
          // (Verdict.globeHexColor) are the only saturated things on screen.
          // The old #006bff arcs and country fills were the exact blue of the
          // UI accent and turned to mush under tinted glass.
          // ────────────────────────────────────────────────────────────────
          const TILE_BLACK = 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAwMDAiLz48L3N2Zz4=';
          const TILE_WHITE = 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiNGRkZGRkYiLz48L3N2Zz4=';

          const PALETTE = {
            dark: {
              globeImage: TILE_BLACK,
              background: '#000011',
              space: 'radial-gradient(ellipse at center, #1a1a2e 0%, #16213e 25%, #0f0f23 50%, #0a0a0a 100%)',
              atmosphere: '#4F94CD',
              country: 'rgba(255, 255, 255, 0.60)',
              tripActive: 'rgba(40, 160, 89, 0.85)',      // #28A059, 60% sat
              tripUpcoming: 'rgba(204, 150, 51, 0.85)',   // #CC9633, 60% sat
              tripCompleted: 'rgba(51, 115, 204, 0.85)',  // #3373CC, 60% sat
              arc: ['rgba(51, 115, 204, 0.55)', 'rgba(51, 115, 204, 0.20)'],
              arcMuted: ['rgba(128, 128, 128, 0.16)', 'rgba(128, 128, 128, 0.08)'],
              label: 'rgba(255, 255, 255, 0.82)',
              labelShadow: '0 0 3px rgba(0, 0, 0, 0.95), 0 1px 4px rgba(0, 0, 0, 0.8)'
            },
            light: {
              globeImage: TILE_WHITE,
              background: '#FFFFFF',
              space: 'linear-gradient(180deg, #E8F4FD 0%, #B8E0FF 30%, #87CEEB 70%, #F0F8FF 100%)',
              atmosphere: '#CCE7FF',
              country: 'rgba(0, 0, 0, 0.60)',
              tripActive: 'rgba(31, 122, 68, 0.85)',
              tripUpcoming: 'rgba(154, 113, 38, 0.85)',
              tripCompleted: 'rgba(38, 87, 153, 0.85)',
              arc: ['rgba(38, 87, 153, 0.50)', 'rgba(38, 87, 153, 0.18)'],
              arcMuted: ['rgba(90, 90, 96, 0.16)', 'rgba(90, 90, 96, 0.08)'],
              label: 'rgba(18, 18, 24, 0.88)',
              labelShadow: '0 0 3px rgba(255, 255, 255, 0.95), 0 1px 4px rgba(255, 255, 255, 0.85)'
            }
          };

          window.currentTheme = (window.initialTheme === 'light') ? 'light' : 'dark';
          function palette() { return PALETTE[window.currentTheme] || PALETTE.dark; }

          const world = new Globe(document.getElementById('globeViz'))
            .globeImageUrl(palette().globeImage)
            .backgroundColor(palette().background)
            .showAtmosphere(true)
            .atmosphereColor(palette().atmosphere)
            .enablePointerInteraction(true);

          document.body.style.background = palette().space;

          world.controls().autoRotate = true;
          world.controls().autoRotateSpeed = 0.3;
          // Close enough to pull a city apart into its individual places
          // (three spots 8km apart separate at roughly this altitude), far
          // enough out that the whole log fits on one sphere.
          world.controls().minDistance = 115;  // altitude 0.15
          world.controls().maxDistance = 800;  // altitude 7.00

          // Set initial zoom level (higher = more zoomed out)
          world.pointOfView({ altitude: 4.0 });

          // ── State ──────────────────────────────────────────────────────
          let arcsData = [];        // flight arcs: trip metadata, quiet context
          let placesData = [];      // PlaceGlobePoint payloads: the actual log
          let focusedFlightId = null;
          let autoRotateAllowed = true;   // false while Reduce Motion is on
          window.currentTripLocations = [];

          const MAX_PLACES = 400;
          const MAX_ARCS = 20;
          const MAX_LABELS = 40;

          function post(payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
              window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify(payload));
            }
          }

          function currentAltitude() {
            const pov = world.pointOfView() || {};
            return pov.altitude || 4.0;
          }

          // globe.gl sizes points and arcs in angular degrees on a sphere of
          // fixed radius, while on-screen size scales as 1/altitude. So every
          // number below is proportional to altitude, which holds a marker at
          // a constant pixel size instead of letting it swell into a blob as
          // you zoom in. The 1.2 exponent on the radius makes places shrink
          // slightly faster than that, so a dozen dots in one city separate as
          // you come down: ~4.8px across the whole globe, ~2.8px over a region.
          function placeRadiusFor(altitude) {
            return Math.max(0.02, Math.min(3.0, 0.9 * Math.pow(altitude / 3.0, 1.2)));
          }
          function arcStrokeFor(altitude) {
            // Holds ~2.4px. The flight tracker drew these at 2.0deg, three
            // times heavier than this, in the same blue as the UI accent.
            return Math.max(0.03, Math.min(1.2, altitude * 0.16));
          }
          function labelSpacingFor(altitude) {
            // Roughly 45px of clear space between two labels at any zoom.
            return Math.max(0.05, Math.min(14.0, altitude * 3.0));
          }

          // ── Places: the one saturated layer ────────────────────────────
          world
            .pointsData([])
            .pointLat(d => d.lat)
            .pointLng(d => d.lng)
            .pointColor(d => d.color || '#8E8E93')
            // Fixed lift, just clear of the hex dots at 0.01, so a place never
            // z-fights the land under it and never grows into a tower when you
            // zoom in. Places live in the same shell as the country dots.
            .pointAltitude(0.014)
            .pointRadius(placeRadiusFor(4.0))
            .pointResolution(8)
            .pointLabel(d => d.name || '')
            .onPointClick(place => {
              if (!place) return;
              world.controls().autoRotate = false;
              world.pointOfView({ lat: place.lat, lng: place.lng, altitude: 0.8 }, 1200);
              post({
                type: 'PLACE_SELECTED',
                placeId: place.placeId || '',
                name: place.name || '',
                verdict: place.verdict || 'unrated'
              });
              post({ type: 'AUTO_ROTATE_TOGGLED', autoRotate: false });
              setTimeout(applyZoomDependentVisuals, 1400);
            });

          // ── Flights: context, not content ──────────────────────────────
          world
            .arcsData(arcsData)
            .arcStartLat(d => d.startLat)
            .arcStartLng(d => d.startLng)
            .arcEndLat(d => d.endLat)
            .arcEndLng(d => d.endLng)
            .arcLabel(d => d.flightNumber + ': ' + (d.status || 'Unknown'))
            .arcColor(() => palette().arc)
            .arcStroke(arcStrokeFor(4.0))
            .arcAltitudeAutoScale(0.35)  // hug the surface: arcs sit behind places
            .arcDashLength(0.35)
            .arcDashGap(0.35)
            .arcDashAnimateTime(6000)
            .arcCircularResolution(24);

          // ── Labels: bare type, no chrome ───────────────────────────────
          // Pills with a blue border were 2019 chrome fighting 2026 glass. A
          // text-shadow carries the same legibility over both hemispheres and
          // disappears into the composite.
          function makeGlobeLabel(d) {
            const el = document.createElement('div');
            el.textContent = d.text;  // user-entered place names: never innerHTML
            const isPlace = d.kind === 'place';
            el.style.cssText = `
              color: ${isPlace ? (d.color || palette().label) : palette().label};
              font-family: 'GeistMono-Regular', ui-monospace, 'Monaco', 'Menlo', 'Consolas', monospace;
              font-size: ${isPlace ? '10px' : '9px'};
              font-weight: ${isPlace ? '600' : '500'};
              letter-spacing: 0.06em;
              text-shadow: ${palette().labelShadow};
              opacity: ${isPlace ? '1' : '0.72'};
              text-align: center;
              pointer-events: none;
              white-space: nowrap;
              transform: translate(-50%, -50%);
            `;
            return el;
          }

          function dedupeByDistance(candidates, threshold) {
            const kept = [];
            for (let i = 0; i < candidates.length; i++) {
              const candidate = candidates[i];
              let clear = true;
              for (let j = 0; j < kept.length; j++) {
                const distance = Math.sqrt(
                  Math.pow(candidate.lat - kept[j].lat, 2) +
                  Math.pow(candidate.lng - kept[j].lng, 2)
                );
                if (distance < threshold) { clear = false; break; }
              }
              if (clear) kept.push(candidate);
            }
            return kept;
          }

          function buildLabels(altitude) {
            const candidates = [];

            // Places claim the label budget first; airport codes get whatever
            // room is left. Names only appear once you have zoomed in far
            // enough for them to mean something.
            if (altitude < 2.6) {
              placesData.forEach(place => {
                if (!place.name) return;
                candidates.push({
                  lat: place.lat,
                  lng: place.lng,
                  text: place.name,
                  color: place.color,
                  kind: 'place'
                });
              });
            }

            const labelledArcs = focusedFlightId
              ? arcsData.filter(arc => arc.flightId === focusedFlightId)
              : arcsData;

            labelledArcs.forEach(flight => {
              candidates.push({ lat: flight.startLat, lng: flight.startLng, text: flight.departureCode || 'DEP', kind: 'airport' });
              candidates.push({ lat: flight.endLat, lng: flight.endLng, text: flight.arrivalCode || 'ARR', kind: 'airport' });
            });

            return dedupeByDistance(candidates, labelSpacingFor(altitude)).slice(0, MAX_LABELS);
          }

          world
            .htmlElementsData([])
            .htmlLat(d => d.lat)
            .htmlLng(d => d.lng)
            .htmlAltitude(0.05)  // clears the tallest place pillar (0.04)
            .htmlElement(makeGlobeLabel);

          // ── One place where zoom-dependent visuals get applied ──────────
          function applyArcColor() {
            const theme = palette();
            if (focusedFlightId) {
              world.arcColor(arc => (arc.flightId === focusedFlightId ? theme.arc : theme.arcMuted));
            } else {
              world.arcColor(() => theme.arc);
            }
          }

          function applyArcStroke(altitude) {
            const base = arcStrokeFor(altitude);
            if (focusedFlightId) {
              world.arcStroke(arc => (arc.flightId === focusedFlightId ? base * 2.2 : 0.0001));
            } else {
              world.arcStroke(base);
            }
          }

          function applyZoomDependentVisuals() {
            const altitude = currentAltitude();
            const base = placeRadiusFor(altitude);
            // Somewhere you keep going back to reads a little heavier - up to
            // 28% wider at five visits. Colour still carries the verdict.
            world.pointRadius(d => base * (1 + Math.min((d.visitCount || 1) - 1, 4) * 0.07));
            applyArcColor();
            applyArcStroke(altitude);
            world.htmlElementsData(buildLabels(altitude));
          }

          // Debounced so a pinch does not rebuild every label mid-gesture.
          let visualsTimeout;
          function updateVisualsDebounced() {
            clearTimeout(visualsTimeout);
            visualsTimeout = setTimeout(applyZoomDependentVisuals, 200);
          }
          world.controls().addEventListener('end', updateVisualsDebounced);

          // Helper function to check if a trip is in a country (using point-in-polygon)
          function isPointInCountry(lat, lng, countryFeature) {
            if (!countryFeature || !countryFeature.geometry) return false;

            const geometry = countryFeature.geometry;

            // Point-in-polygon test using ray casting algorithm
            // Note: GeoJSON coordinates are [longitude, latitude]
            function pointInPolygon(lat, lng, polygon) {
              let inside = false;
              for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
                const [lngI, latI] = polygon[i];  // GeoJSON is [lng, lat]
                const [lngJ, latJ] = polygon[j];

                const intersect = ((latI > lat) !== (latJ > lat)) &&
                  (lng < (lngJ - lngI) * (lat - latI) / (latJ - latI) + lngI);
                if (intersect) inside = !inside;
              }
              return inside;
            }

            // Check all polygons in the geometry
            if (geometry.type === 'Polygon') {
              // Polygon has rings (first is outer, rest are holes)
              const outerRing = geometry.coordinates[0];
              if (pointInPolygon(lat, lng, outerRing)) {
                // Check if point is in any hole
                for (let i = 1; i < geometry.coordinates.length; i++) {
                  if (pointInPolygon(lat, lng, geometry.coordinates[i])) {
                    return false; // In a hole
                  }
                }
                return true; // In outer ring, not in any hole
              }
            } else if (geometry.type === 'MultiPolygon') {
              // MultiPolygon has multiple polygons
              for (let poly of geometry.coordinates) {
                const outerRing = poly[0];
                if (pointInPolygon(lat, lng, outerRing)) {
                  // Check if point is in any hole
                  let inHole = false;
                  for (let i = 1; i < poly.length; i++) {
                    if (pointInPolygon(lat, lng, poly[i])) {
                      inHole = true;
                      break;
                    }
                  }
                  if (!inHole) return true; // In a polygon, not in any hole
                }
              }
            }

            return false;
          }

          function tripsInCountry(countryFeature) {
            return (window.currentTripLocations || []).filter(trip => {
              return isPointInCountry(trip.lat, trip.lng, countryFeature);
            });
          }

          // Trip-aware hexagon colouring, in the desaturated palette.
          window.applyHexagonColors = function() {
            const theme = palette();

            world
              .hexPolygonColor(d => {
                const countryTrips = tripsInCountry(d);
                if (countryTrips.length > 0) {
                  // Prioritize: active > upcoming > completed
                  if (countryTrips.some(trip => trip.status === 'active')) return theme.tripActive;
                  if (countryTrips.some(trip => trip.status === 'upcoming')) return theme.tripUpcoming;
                  return theme.tripCompleted;
                }
                return theme.country;
              })
              .hexPolygonAltitude(() => 0.01)
              .hexPolygonUseDots(d => tripsInCountry(d).length === 0);
          };

          // Add theme switching function
          window.setTheme = function(theme) {
            console.log('🎨 Setting theme to:', theme);
            window.currentTheme = (theme === 'light') ? 'light' : 'dark';
            const next = palette();

            world
              .globeImageUrl(next.globeImage)
              .backgroundColor(next.background)
              .atmosphereColor(next.atmosphere);

            document.body.style.background = next.space;

            window.applyHexagonColors();
            // Arc colours and label colours both come out of the palette.
            applyZoomDependentVisuals();
          };

          // Add performance monitoring
          window.monitorPerformance = function() {
            const startTime = performance.now();
            setTimeout(() => {
              const renderTime = performance.now() - startTime;
              if (renderTime > 100) {
                console.log('⚠️ Slow rendering detected:', renderTime.toFixed(2), 'ms');
              }
            }, 0);
          };

          // ── The single update path from Swift ──────────────────────────
          // Argument list is append-only: `places` was added on the end, so a
          // five-argument caller still works. `airports` and `visitedCities`
          // are kept for that compatibility - airport labels are derived from
          // the arcs themselves, and visited cities are superseded by places.
          window.updateGlobeData = function(flightPaths, airports, visitedCities, tripLocations, tabMode, places) {
            console.log('🎯 updateGlobeData called with:', flightPaths?.length, 'flights,', places?.length, 'places,', tripLocations?.length, 'trip locations, tab mode:', tabMode);

            // Places: the log the user built. Drawn on every tab - this is the
            // product, not a per-screen decoration.
            placesData = (places || [])
              .filter(place => typeof place.lat === 'number' && typeof place.lng === 'number')
              .slice(0, MAX_PLACES);
            world.pointsData(placesData);

            // Flights: Swift already tab-filtered these, just draw what arrived.
            const validFlights = (flightPaths || []).filter(flight =>
              flight.startLat && flight.startLng && flight.endLat && flight.endLng
            );
            arcsData = validFlights.slice(0, MAX_ARCS);
            world.arcsData(arcsData);
            if (focusedFlightId && !arcsData.some(arc => arc.flightId === focusedFlightId)) {
              focusedFlightId = null;
            }

            // Store trip locations globally for country colouring
            window.currentTripLocations = tripLocations || [];
            window.applyHexagonColors();

            applyZoomDependentVisuals();

            console.log('✅ Globe updated:', placesData.length, 'places,', arcsData.length, 'arcs for tab:', tabMode);
          };

          // Backward compatibility function
          window.updateFlightData = function(flightPaths, airports) {
            console.log('🎯 updateFlightData called (fallback mode)');
            window.updateGlobeData(flightPaths, airports, [], [], 'all', placesData);
          };

          // Auto-rotation. `setAutoRotate` is the one the app drives from the
          // Reduce Motion setting; `toggleAutoRotate` is the on-screen button.
          window.setAutoRotate = function(enabled) {
            autoRotateAllowed = !!enabled;
            world.controls().autoRotate = autoRotateAllowed;
            return autoRotateAllowed;
          };

          window.toggleAutoRotate = function() {
            return window.setAutoRotate(!world.controls().autoRotate);
          };

          // Add reset function
          window.resetRotation = function() {
            focusedFlightId = null;
            world.pointOfView({ lat: 0, lng: 0, altitude: 4.0 }, 1000);
            world.controls().autoRotate = autoRotateAllowed;
            setTimeout(applyZoomDependentVisuals, 1200);
          };

          window.focusOnPlace = function(placeId) {
            const place = placesData.find(candidate => candidate.placeId === placeId);
            if (!place) {
              console.warn('⚠️ Place not found on globe:', placeId);
              return false;
            }
            world.controls().autoRotate = false;
            world.pointOfView({ lat: place.lat, lng: place.lng, altitude: 0.8 }, 1200);
            setTimeout(applyZoomDependentVisuals, 1400);
            return true;
          };

          // Enhanced flight focusing with ID-based matching and visual highlighting
          window.focusOnFlightById = function(flightId, flightNumber) {
            console.log("🎯 Attempting to focus on flight:", flightNumber, "ID:", flightId);

            if (!arcsData || arcsData.length === 0) {
              console.warn("⚠️ No flight data available in arcsData");
              return false;
            }

            let flight = null;
            for (let i = 0; i < arcsData.length; i++) {
              const arc = arcsData[i];
              if (arc.flightId === flightId ||
                  (arc.flightNumber && arc.flightNumber === flightNumber)) {
                flight = arc;
                break;
              }
            }

            if (!flight) {
              console.warn("⚠️ Flight not found in arcsData:", flightNumber, "ID:", flightId);
              return false;
            }

            focusedFlightId = flight.flightId || flightId;

            const lat = (flight.startLat + flight.endLat) / 2;
            const lng = (flight.startLng + flight.endLng) / 2;
            world.pointOfView({ lat, lng, altitude: 2.5 }, 1500);

            // Highlighting and label filtering both fall out of the one
            // apply pass, keyed off focusedFlightId.
            applyZoomDependentVisuals();
            setTimeout(applyZoomDependentVisuals, 1700);

            console.log("🎯 Successfully focused on flight:", flightNumber);
            return true;
          };

          // Clear highlighting function
          window.clearFlightHighlight = function() {
            focusedFlightId = null;
            applyZoomDependentVisuals();
            console.log("🎨 Cleared flight highlighting");
          };

          window.focusOnFlight = function(flightIndex) {
            const flight = arcsData[flightIndex];
            if (!flight) return;
            world.pointOfView({
              lat: (flight.startLat + flight.endLat) / 2,
              lng: (flight.startLng + flight.endLng) / 2,
              altitude: 2.5
            }, 1000);
            setTimeout(applyZoomDependentVisuals, 1200);
          };

          window.clearFlightPaths = function() {
            arcsData = [];
            focusedFlightId = null;
            world.arcsData(arcsData);
            applyZoomDependentVisuals();
          };

          window.getCurrentFlights = function() { return arcsData; };
          window.getCurrentPlaces = function() { return placesData; };

          document.getElementById('status').innerHTML = 'Globe ready, loading countries...';
          console.log('🌍 Globe with place + flight support created successfully');
          console.log('📋 Available functions:', typeof window.updateGlobeData, typeof window.updateFlightData, typeof window.setTheme);

          // Try to load countries data with timeout and error handling
          const loadCountries = () => {
            const timeoutId = setTimeout(() => {
              console.log('⚠️ Countries data fetch timeout, using basic globe');
              document.getElementById('status').innerHTML = 'Globe ready (basic mode)';

              // Signal ready even on timeout
              setTimeout(() => {
                console.log('✅ Globe ready (timeout), signaling to Swift');
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                  window.webkit.messageHandlers.reactNativeWebView.postMessage('Globe ready (fallback)');
                }
                document.getElementById('status').style.display = 'none';
              }, 1000);
            }, 10000); // 10 second timeout

            // Load country-level data from preloaded bundle data (offline support)
            Promise.resolve(window.COUNTRIES_DATA)
              .then(countries => {
                clearTimeout(timeoutId);
                console.log('✅ Countries data loaded:', countries.features.length);

                document.getElementById('status').innerHTML = 'Adding regions...';

                try {
                  world
                    .hexPolygonsData(countries.features)
                    .hexPolygonResolution(3) // Medium resolution for hexagons
                    .hexPolygonMargin(0.5)
                    .hexPolygonUseDots(true)
                    .hexPolygonAltitude(0.01) // Elevated from globe surface
                    .hexPolygonLabel(() => null);
                } catch (error) {
                  console.log('⚠️ Full dataset failed, trying reduced set:', error.message);
                  // Fallback to reduced dataset if full one causes issues
                  world
                    .hexPolygonsData(countries.features.slice(0, 500))
                    .hexPolygonResolution(3)
                    .hexPolygonMargin(0.5)
                    .hexPolygonUseDots(true)
                    .hexPolygonAltitude(0.01)
                    .hexPolygonLabel(() => null);
                }

                window.applyHexagonColors();

                console.log('🗺️ Countries added successfully');
                document.getElementById('status').innerHTML = 'Globe with countries ready!';

                // Monitor performance after adding countries
                window.monitorPerformance();

                // Signal that globe is fully ready for data
                setTimeout(() => {
                  console.log('✅ Globe fully ready, signaling to Swift');
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                    window.webkit.messageHandlers.reactNativeWebView.postMessage('Globe ready');
                  }
                  document.getElementById('status').style.display = 'none';
                }, 1000);
              })
              .catch(error => {
                clearTimeout(timeoutId);
                console.log('⚠️ Failed to load countries:', error.message);
                document.getElementById('status').innerHTML = 'Globe ready (basic mode)';

                // Signal ready even in fallback mode
                setTimeout(() => {
                  console.log('✅ Globe ready (fallback), signaling to Swift');
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
                    window.webkit.messageHandlers.reactNativeWebView.postMessage('Globe ready (fallback)');
                  }
                  document.getElementById('status').style.display = 'none';
                }, 1000);
              });
          };

          // Load countries after a brief delay to ensure globe is stable
          setTimeout(loadCountries, 1000);

        } catch (error) {
          console.error('❌ Error creating globe:', error);
          document.getElementById('status').innerHTML = 'Error: ' + error.message;
          document.getElementById('status').style.color = '#FF7A6B';
        }
      };
      script.onerror = function() {
        console.error('❌ Failed to load Globe.gl');
        document.getElementById('status').innerHTML = 'Failed to load Globe.gl library';
        document.getElementById('status').style.color = '#FF7A6B';
      };
      document.head.appendChild(script);
    }, 2000);
  </script>
</body>
</html>
"""
    }
    
    
    func evaluateJavaScript(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "reactNativeWebView",
           let messageBody = message.body as? String {
            onMessageReceived?(messageBody)
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // WebView finished loading
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // WebView started loading content
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // WebView failed to load
    }
}

// MARK: - WebView SwiftUI Bridge

struct WebView: UIViewRepresentable {
    let coordinator: WebViewCoordinator
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = coordinator.webView ?? WKWebView()
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.scrollView.contentInsetAdjustmentBehavior = .never
    }
}

#Preview {
    WebViewGlobeView(coordinator: WebViewCoordinator(), currentTab: nil)
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
}