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
    
    
    // Globe background. `globeBackground` already carries exactly this value in
    // both palettes; the literals here were a second source of truth that would
    // drift the moment the palette moved.
    private var globeBackgroundColor: Color {
        themeManager.currentTheme.colors.globeBackground
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
        // Glass, not three filled discs.
        //
        // These were solid `primary` / `success` / `textSecondary` circles: on a
        // near-black globe a saturated blue and a saturated green read as the
        // loudest objects on the screen, louder than the flight path they sit
        // over. They are utilities, not content. `SkyLineGlassIconButton` is the
        // app's own 44pt glass control and already carries the Reduce
        // Transparency fallback and the hit target - this panel simply predated
        // it and never adopted it.
        //
        // One `GlassEffectContainer` around all three so they render as one
        // piece of glass rather than three unrelated lenses.
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm) {
                SkyLineGlassIconButton(
                    systemImage: themeManager.currentTheme == .light ? "moon.fill" : "sun.max.fill",
                    accessibilityLabel: themeManager.currentTheme == .light
                        ? "Switch to dark appearance"
                        : "Switch to light appearance"
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    themeManager.toggleTheme()
                }

                SkyLineGlassIconButton(
                    systemImage: isAutoRotating ? "pause.fill" : "play.fill",
                    accessibilityLabel: isAutoRotating ? "Pause rotation" : "Resume rotation",
                    action: toggleAutoRotation
                )

                SkyLineGlassIconButton(
                    systemImage: "arrow.counterclockwise",
                    accessibilityLabel: "Reset the globe",
                    action: resetGlobe
                )
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

// MARK: - Globe Web Font

/// Geist Mono, encoded once, for the globe's `WKWebView`.
///
/// A font registered through `UIAppFonts` is available to UIKit and SwiftUI but
/// NOT to a `WKWebView`: the web view resolves families through its own stack and
/// cannot see the ones the app registered. So `font-family: 'GeistMono-Regular'`
/// in the injected CSS never matched anything, and every globe label has been
/// silently rendering in `ui-monospace` (SF Mono) since the day it was written.
/// Nothing warns you about this — the labels just quietly are not the app's face.
///
/// The page is loaded with `loadHTMLString(_:baseURL: nil)`, so its origin is
/// about:blank and a relative `url('GeistMono-Regular.ttf')` has nothing to
/// resolve against. Re-pointing `baseURL` into the bundle would make relative
/// URLs work but changes the page's origin and read permissions for the sake of
/// a font, so this uses a `data:` URI instead: self-contained, origin-independent,
/// and it cannot be broken by a later change to how the page is loaded.
///
/// Roughly 300 KB of base64 across two faces. `static let` is lazy and evaluated
/// once per process, so the encode never runs on a globe rebuild or a reload.
private enum GlobeWebFont {
    /// The family name the injected CSS asks for. One family, two weights — the
    /// weight is chosen by `font-weight`, not by naming a second family.
    static let family = "GeistMono"

    /// The faces the globe actually uses: body copy at 400, labels at 600.
    /// A web font gets no synthetic weights either, so a 600 rule with only the
    /// 400 face loaded would be faux-bolded by WebKit — smeared, not semibold.
    private static let bundled: [(file: String, weight: Int)] = [
        ("GeistMono-Regular", 400),
        ("GeistMono-SemiBold", 600)
    ]

    /// `@font-face` rules ready to drop into the page's `<style>`. Empty if the
    /// files are missing from the bundle, in which case the CSS falls straight
    /// through to `ui-monospace` — today's behaviour, not a serif.
    static let faceCSS: String = bundled.compactMap { face in
        guard let url = Bundle.main.url(forResource: face.file, withExtension: "ttf"),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ Globe: \(face.file).ttf is not in the bundle — labels fall back to ui-monospace")
            return nil
        }
        return """
            @font-face {
              font-family: '\(family)';
              src: url("data:font/ttf;base64,\(data.base64EncodedString())") format('truetype');
              font-weight: \(face.weight);
              font-style: normal;
            }
        """
    }.joined(separator: "\n")

    /// The stack every rule on the globe should use. Geist Mono first, then the
    /// same fallback the page has been getting all along, so a failure to decode
    /// degrades to exactly what shipped yesterday.
    static let stack = "'\(family)', ui-monospace, 'Menlo', monospace"
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
    /* Geist Mono, inlined as a data: URI. See GlobeWebFont — a UIAppFonts
       registration does not reach a WKWebView, so the font has to travel with
       the page. */
\(GlobeWebFont.faceCSS)
    body {
      margin: 0;
      padding: 0;
      background: #000011;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
      /* Was -apple-system/Helvetica: the one block in the app set in a
         proportional sans, on the surface everything else is monospaced. */
      font-family: \(GlobeWebFont.stack);
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
              arc: ['rgba(97, 170, 255, 0.95)', 'rgba(97, 170, 255, 0.55)'],
              arcMuted: ['rgba(128, 128, 128, 0.16)', 'rgba(128, 128, 128, 0.08)'],
              label: 'rgba(255, 255, 255, 0.96)',
              labelShadow: '0 0 3px rgba(0, 0, 0, 0.95), 0 1px 4px rgba(0, 0, 0, 0.8)'
            },
            light: {
              globeImage: TILE_WHITE,
              background: '#FFFFFF',
              // Neutral, not sky blue. `#B8E0FF` through `#87CEEB` was a
              // literal daytime sky, which read as a themed illustration behind
              // a product that is otherwise paper-white. These are the app's own
              // light tokens - surface, background, and a shade below border -
              // so the globe sits on the same ground as every other screen.
              space: 'linear-gradient(180deg, #FFFFFF 0%, #F7F8FC 45%, #EDF0F7 100%)',
              // Grey, faintly cool, so the sphere still has an edge without
              // casting blue onto the neutral ground behind it.
              atmosphere: '#DCE2EF',
              country: 'rgba(0, 0, 0, 0.60)',
              tripActive: 'rgba(31, 122, 68, 0.85)',
              tripUpcoming: 'rgba(154, 113, 38, 0.85)',
              tripCompleted: 'rgba(38, 87, 153, 0.85)',
              arc: ['rgba(11, 99, 197, 0.95)', 'rgba(11, 99, 197, 0.55)'],
              arcMuted: ['rgba(90, 90, 96, 0.16)', 'rgba(90, 90, 96, 0.08)'],
              label: 'rgba(12, 12, 18, 0.98)',
              labelShadow: '0 0 3px rgba(255, 255, 255, 0.95), 0 1px 4px rgba(255, 255, 255, 0.85)'
            }
          };

          // ────────────────────────────────────────────────────────────────
          // Place pills - the one thing on this page that does NOT follow the
          // theme.
          //
          // The globe is a dark OBJECT, not a themed surface: it is lit black
          // space with a lit sphere in it whether the app is in Light or Dark,
          // exactly like a photograph. That is the argument `PhotoOverlay` in
          // PlaceCard.swift already makes for text laid over a photo, and the
          // same conclusion follows here - flipping these to dark-on-cream in
          // Light theme would put cream pills on a black sky.
          //
          // Opaque, not glass, for a second reason: a rotating sphere presents
          // a different backdrop under every pill on every frame, so a glass
          // pill has nothing stable to sample and reads as a smear. Polarsteps'
          // Explore globe uses solid pills for precisely this.
          //
          // `fill` and `ink` mirror ThemeColors.dark.background / .text, the
          // same pair PhotoOverlay borrows, so there is one place to change the
          // day a real on-photo token lands.
          const PILL = {
            fill: '#0A0F1C',
            ink: '#E9EDF7',
            hairline: 'rgba(233, 237, 247, 0.14)',
            shadow: '0 1px 6px rgba(0, 0, 0, 0.55)'
          };

          window.currentTheme = (window.initialTheme === 'light') ? 'light' : 'dark';
          function palette() { return PALETTE[window.currentTheme] || PALETTE.dark; }

          // ── Stars ──────────────────────────────────────────────────────
          //
          // Drawn once into an offscreen canvas and handed to globe.gl as a
          // data URI, rather than fetched. The globe.gl script already comes
          // from a CDN by floating tag; a second network dependency for the
          // backdrop would mean the app's signature screen has two ways to
          // arrive half-drawn.
          //
          // Seeded rather than `Math.random()`, so the sky is the same sky
          // after a theme toggle or a reload. Stars that rearrange themselves
          // every time the user taps the sun icon read as a glitch.
          //
          // Dark only. On the light palette the ground is near-white paper and
          // stars on it would be soot.
          function makeStarfield(width, height, isLight) {
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            // Deliberately NOT filled. The tile is transparent so the palette's
            // own `space` gradient shows through underneath it - those values
            // are CSS gradients, not colours, so painting one here with
            // `fillStyle` silently does nothing and leaves the canvas black.
            // That is what the first version did, and dark mode looked right
            // only by accident.

            // Mulberry32: small, seeded, and good enough for scattering points.
            let seed = 1013904223;
            function random() {
              seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
              let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
              t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
              return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }

            // Three passes, faint and many to bright and few, so the field has
            // depth instead of reading as evenly-spaced noise. The seed is
            // fixed, so light and dark are the SAME sky - toggling the theme
            // inverts the ink and leaves every star where it was.
            const layers = [
              { count: 520, maxRadius: 0.7, alpha: 0.30 },
              { count: 180, maxRadius: 1.1, alpha: 0.55 },
              { count: 46,  maxRadius: 1.6, alpha: 0.85 }
            ];

            layers.forEach(layer => {
              for (let i = 0; i < layer.count; i++) {
                const x = random() * width;
                const y = random() * height;
                const radius = 0.3 + random() * layer.maxRadius;
                const jitter = 0.6 + random() * 0.4;
                if (isLight) {
                  // Near-black specks, at full layer alpha.
                  //
                  // The first attempt reasoned that dark-on-light reads heavier
                  // and scaled the alpha to 0.55 - which put the faint layer at
                  // about 0.17 over a pale blue sky, where it simply vanished.
                  // The light gradient is much closer in value to a mid grey
                  // than the dark gradient is to white, so the ink needs MORE
                  // contrast here, not less.
                  const grey = 96 + Math.floor(random() * 40);
                  ctx.fillStyle = 'rgba(' + grey + ', ' + grey + ', ' + (grey + 10) + ', ' + Math.min(1, layer.alpha * jitter * 0.95) + ')';
                } else {
                  // A touch of blue in the brighter stars, to sit with the
                  // atmosphere halo rather than fight it.
                  const blue = 235 + Math.floor(random() * 20);
                  ctx.fillStyle = 'rgba(255, 255, ' + blue + ', ' + (layer.alpha * jitter) + ')';
                }
                ctx.beginPath();
                ctx.arc(x, y, radius, 0, Math.PI * 2);
                ctx.fill();
              }
            });

            return canvas.toDataURL('image/png');
          }

          const starfieldCache = {};
          function starfield(themeName) {
            if (starfieldCache[themeName] === undefined) {
              try {
                starfieldCache[themeName] = makeStarfield(512, 512, themeName === 'light');
              } catch (error) {
                console.warn('Starfield unavailable:', error);
                starfieldCache[themeName] = '';
              }
            }
            return starfieldCache[themeName] || null;
          }

          function canvasClearColor() {
            // Transparent in BOTH themes. Returning an opaque colour here for
            // light painted the canvas over the page background - and the page
            // background is where the starfield lives, so light mode had stars
            // that were drawn, layered and then completely covered up. The
            // globe's own backdrop is `applyBackdrop()`, on the body, for both
            // themes; the canvas contributes the sphere and nothing else.
            return 'rgba(0,0,0,0)';
          }

          function applyBackdrop() {
            const stars = starfield(window.currentTheme);
            // Two layers in one declaration: the star tile on top, the
            // palette's own gradient beneath it. `background` shorthand rather
            // than `backgroundColor`, because `space` IS a gradient and a
            // gradient assigned to `backgroundColor` is simply dropped.
            if (stars) {
              document.body.style.background =
                'url(' + stars + ') repeat top left / 512px 512px, ' + palette().space;
            } else {
              document.body.style.background = palette().space;
            }
          }

          const world = new Globe(document.getElementById('globeViz'))
            .globeImageUrl(palette().globeImage)
            .backgroundColor(canvasClearColor())
            .showAtmosphere(true)
            .atmosphereColor(palette().atmosphere)
            .enablePointerInteraction(true);

          applyBackdrop();

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
            // This was tuned down to a third of the old flight tracker's weight
            // so the arcs would read as a wash BEHIND the place pills. With the
            // pills gone the arcs are the only content on the sphere, and at
            // that weight a transatlantic flight was a hairline you had to hunt
            // for. Still well under the original 2.0deg, which was a solid rope.
            return Math.max(0.10, Math.min(1.2, altitude * 0.34));
          }
          function labelSpacingFor(altitude) {
            // A label is a ~3-character word, not a point, so it needs clearance
            // for its own width plus the neighbour's. 3.0 was tuned when the
            // comparison was still measuring raw longitude and therefore
            // overestimating every east-west gap.
            return Math.max(0.05, Math.min(20.0, altitude * 5.0));
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
            .arcAltitudeAutoScale(0.55)  // lift off the surface now nothing sits above them
            // Near-solid, with one small travelling break.
            //
            // 0.35 length against a 0.35 gap draws only half the arc at any
            // moment, in two chunks - so PHL to DEN read as loose fragments
            // and you could not tell which end joined which. The route has to
            // be continuous to be a route. The remaining 10% gap runs the
            // length of the arc, which is what still shows direction of travel;
            // taking it to zero would give a clean line that says nothing about
            // which way the flight went.
            .arcDashLength(0.9)
            .arcDashGap(0.1)
            .arcDashAnimateTime(4500)
            .arcCircularResolution(24);

          // ── Labels ─────────────────────────────────────────────────────
          // Two kinds, and they are deliberately different objects. A logged
          // place is CONTENT - the reason the globe is on screen at all - so it
          // gets an opaque pill. An airport code is CONTEXT belonging to a
          // flight arc, so it stays bare type that disappears into the
          // composite. Pills with a blue border were 2019 chrome fighting 2026
          // glass; a pill that carries the user's own verdict is not chrome.
          function makeGlobeLabel(d) {
            const el = d.kind === 'place' ? makePlacePill(d) : makeAirportLabel(d);
            // The visibility pass gets an element, not a datum, so the position
            // has to travel on the element itself.
            el.dataset.lat = d.lat;
            el.dataset.lng = d.lng;
            return el;
          }

          function makeAirportLabel(d) {
            const el = document.createElement('div');
            el.textContent = d.text;
            el.style.cssText = `
              color: ${palette().label};
              font-family: \(GlobeWebFont.stack);
              font-size: 11px;
              font-weight: 600;
              letter-spacing: 0.08em;
              text-shadow: ${palette().labelShadow};
              opacity: 1;
              text-align: center;
              pointer-events: none;
              white-space: nowrap;
              transform: translate(-50%, -50%);
            `;
            return el;
          }

          const SVG_NS = 'http://www.w3.org/2000/svg';

          // Silhouette first, colour second - the same rule the SwiftUI side
          // follows. Burst / circle / diamond / open ring are four distinct
          // outlines, so a pill still says which verdict it carries in
          // greyscale and under any colour vision deficiency. Colour alone,
          // at 11px, on a moving sphere, would be the weakest signal in the
          // app rather than the strongest.
          function sealPoints() {
            const points = [];
            const spikes = 10;
            for (let i = 0; i < spikes * 2; i++) {
              const radius = (i % 2 === 0) ? 5.7 : 4.4;
              const angle = (Math.PI * i) / spikes - Math.PI / 2;
              points.push(
                (6 + radius * Math.cos(angle)).toFixed(2) + ',' +
                (6 + radius * Math.sin(angle)).toFixed(2)
              );
            }
            return points.join(' ');
          }

          const VERDICT_GLYPHS = {
            worth_it: {
              tag: 'polygon',
              attrs: { points: sealPoints() },
              mark: 'M3.5 6.2 L5.3 8.0 L8.6 4.4'
            },
            fine: {
              tag: 'circle',
              attrs: { cx: '6', cy: '6', r: '5.3' },
              mark: 'M3.2 4.8 H8.8 M3.2 7.2 H8.8'
            },
            skip: {
              tag: 'polygon',
              attrs: { points: '6,0.6 11.4,6 6,11.4 0.6,6' },
              mark: 'M4.2 4.2 L7.8 7.8 M7.8 4.2 L4.2 7.8'
            }
          };

          function verdictGlyph(verdict, color) {
            const svg = document.createElementNS(SVG_NS, 'svg');
            svg.setAttribute('viewBox', '0 0 12 12');
            svg.setAttribute('width', '11');
            svg.setAttribute('height', '11');
            svg.setAttribute('aria-hidden', 'true');
            svg.style.flex = '0 0 auto';

            const spec = VERDICT_GLYPHS[verdict];

            if (!spec) {
              // Undecided: an open ring. A fourth silhouette rather than a
              // fourth colour, because "not yet judged" is a real state in this
              // product and it should look like an empty slot, not a verdict.
              const ring = document.createElementNS(SVG_NS, 'circle');
              ring.setAttribute('cx', '6');
              ring.setAttribute('cy', '6');
              ring.setAttribute('r', '4.3');
              ring.setAttribute('fill', 'none');
              ring.setAttribute('stroke', color);
              ring.setAttribute('stroke-width', '1.6');
              svg.appendChild(ring);
              return svg;
            }

            const body = document.createElementNS(SVG_NS, spec.tag);
            Object.keys(spec.attrs).forEach(function(key) {
              body.setAttribute(key, spec.attrs[key]);
            });
            body.setAttribute('fill', color);
            svg.appendChild(body);

            // The mark is knocked out in the pill's own fill, so it stays
            // legible whatever the verdict colour is and needs no second token.
            const mark = document.createElementNS(SVG_NS, 'path');
            mark.setAttribute('d', spec.mark);
            mark.setAttribute('fill', 'none');
            mark.setAttribute('stroke', PILL.fill);
            mark.setAttribute('stroke-width', '1.5');
            mark.setAttribute('stroke-linecap', 'round');
            mark.setAttribute('stroke-linejoin', 'round');
            svg.appendChild(mark);

            return svg;
          }

          // The log, pinned to the globe. Opaque fill, fixed ink, verdict in
          // colour. `max-width` + `overflow: hidden` clips a long name rather
          // than ellipsing it - a monospace ellipsis at a fixed advance is
          // three wasted cells, and pills are already allowed to clip at the
          // frame edge.
          function makePlacePill(d) {
            const el = document.createElement('div');
            el.style.cssText = `
              display: inline-flex;
              align-items: center;
              gap: 4px;
              max-width: 140px;
              padding: 3px 8px 3px 6px;
              border-radius: 999px;
              background: ${PILL.fill};
              color: ${PILL.ink};
              border: 0.5px solid ${PILL.hairline};
              box-shadow: ${PILL.shadow};
              font-family: \(GlobeWebFont.stack);
              font-size: 10px;
              font-weight: 600;
              letter-spacing: 0.04em;
              line-height: 1.25;
              white-space: nowrap;
              overflow: hidden;
              pointer-events: none;
              transform: translate(-50%, -50%);
            `;

            el.appendChild(verdictGlyph(d.verdict, d.color || PILL.ink));

            const name = document.createElement('span');
            name.textContent = d.text;  // user-entered place names: never innerHTML
            name.style.cssText = 'overflow: hidden;';
            el.appendChild(name);

            return el;
          }

          function dedupeByDistance(candidates, threshold) {
            const kept = [];
            for (let i = 0; i < candidates.length; i++) {
              const candidate = candidates[i];
              let clear = true;
              for (let j = 0; j < kept.length; j++) {
                // Longitude has to be scaled by cos(latitude) before it can be
                // compared with latitude at all. A degree of longitude is a
                // degree of distance only at the equator; at Chicago's latitude
                // it is about three quarters of one. Measuring raw degrees made
                // ORD and JFK look 14 apart when they render about 10 apart, so
                // they cleared the threshold and drew on top of each other as
                // "ORJFK".
                const meanLat = ((candidate.lat + kept[j].lat) / 2) * Math.PI / 180;
                const dLat = candidate.lat - kept[j].lat;
                const dLng = (candidate.lng - kept[j].lng) * Math.cos(meanLat);
                const distance = Math.sqrt(dLat * dLat + dLng * dLng);
                if (distance < threshold) { clear = false; break; }
              }
              if (clear) kept.push(candidate);
            }
            return kept;
          }

          // How many pills the whole-globe view can carry before it stops
          // being a globe. Pills are culled by ZOOM, never hidden outright:
          // the resting view has to say something about the log or the globe
          // is wallpaper, so there is no altitude at which the count is zero.
          function placeLabelBudgetFor(altitude) {
            if (altitude >= 3.2) return 16;   // whole sphere
            if (altitude >= 2.0) return 26;   // a continent
            return MAX_LABELS;                // a city, pulled apart
          }

          // Proportional to altitude for the same reason every other number in
          // this file is: near the sub-camera point the projection scales as
          // 1/altitude, so a linear threshold holds a CONSTANT on-screen gap.
          // ~28px here against `labelSpacingFor`'s ~45px - pills are allowed to
          // sit much closer than airport codes, because a pill is ~90px wide
          // and is MEANT to overlap its neighbours. Overlap reads as density,
          // which is the whole argument for putting the log on the globe. What
          // this does still buy is the collapse of a genuine pile-up: three
          // places 4km apart are 2px apart even at maximum zoom, and stacking
          // three pills on one pixel is noise, not density. The dots underneath
          // keep drawing all of them.
          function placeSpacingFor(altitude) {
            return Math.max(0.03, Math.min(8.0, altitude * 1.8));
          }

          // Which places win a pill when they cannot all have one. A verdict is
          // what the log is FOR, so a decided place outranks an undecided one;
          // after that, somewhere you keep going back to outranks somewhere you
          // passed through once. Ties keep the order Swift sent, which is
          // already most-recent-first.
          function rankedPlaces() {
            return placesData
              .filter(place => !!place.name)
              .map((place, index) => ({ place: place, index: index }))
              .sort((a, b) => {
                const aDecided = (a.place.verdict && a.place.verdict !== 'unrated') ? 0 : 1;
                const bDecided = (b.place.verdict && b.place.verdict !== 'unrated') ? 0 : 1;
                if (aDecided !== bDecided) return aDecided - bDecided;
                const aVisits = a.place.visitCount || 1;
                const bVisits = b.place.visitCount || 1;
                if (aVisits !== bVisits) return bVisits - aVisits;
                return a.index - b.index;
              })
              .map(entry => entry.place);
          }

          function buildLabels(altitude) {
            // Places claim the label budget first; airport codes get whatever
            // room is left.
            // No place pills while the app is scoped to flights. Every place
            // on this globe was derived from a flight, so each pill repeated an
            // airport the arc already labels - and repeated it as "Newark
            // Liberty International Airport" next to a 3-letter code. Restoring
            // the place log restores these; the budget and spacing maths below
            // is left intact for that.
            const showPlacePills = false;
            const places = !showPlacePills ? [] : dedupeByDistance(
              rankedPlaces().map(place => ({
                lat: place.lat,
                lng: place.lng,
                text: place.name,
                color: place.color,
                verdict: place.verdict,
                kind: 'place'
              })),
              placeSpacingFor(altitude)
            ).slice(0, placeLabelBudgetFor(altitude));

            const labelledArcs = focusedFlightId
              ? arcsData.filter(arc => arc.flightId === focusedFlightId)
              : arcsData;

            const airportCandidates = [];
            labelledArcs.forEach(flight => {
              airportCandidates.push({ lat: flight.startLat, lng: flight.startLng, text: flight.departureCode || 'DEP', kind: 'airport' });
              airportCandidates.push({ lat: flight.endLat, lng: flight.endLng, text: flight.arrivalCode || 'ARR', kind: 'airport' });
            });

            // Seeded with the surviving pills, so an airport code never lands
            // on top of one, then filtered back down to the airports it added.
            const airports = dedupeByDistance(
              places.concat(airportCandidates),
              labelSpacingFor(altitude)
            ).filter(candidate => candidate.kind === 'airport');

            return places.concat(airports).slice(0, MAX_LABELS);
          }

          world
            .htmlElementsData([])
            .htmlLat(d => d.lat)
            .htmlLng(d => d.lng)
            .htmlAltitude(0.05)  // clears the tallest place pillar (0.04)
            .htmlElement(makeGlobeLabel);

          // HTML labels are DOM, not geometry, so nothing occludes them: a pill
          // on the far side of the sphere draws straight through it. Bare type
          // got away with that; an opaque pill does not - Tokyo would appear to
          // be in the Atlantic. Only `visibility` is touched, so the airport
          // label's own 0.72 opacity survives. Feature-tested because the hook
          // arrived in globe.gl 2.31 and the library is loaded from a CDN by
          // floating tag; without it the labels behave exactly as before.
          // Whether a label is on the near face is measured here rather than
          // taken from the library's `isBehindGlobe` argument. The script tag
          // is `npm/globe.gl` with no version, so whatever the CDN serves today
          // is what runs - and trusting that flag put every label on the FAR
          // side of the sphere and hid the ones being looked at. A dot product
          // against the camera cannot drift with the dependency.
          function isFacingCamera(lat, lng) {
            if (typeof world.getCoords !== 'function' || typeof world.camera !== 'function') return true;
            const point = world.getCoords(lat, lng, 0);
            const camera = world.camera().position;
            const pointLength = Math.hypot(point.x, point.y, point.z);
            const cameraLength = Math.hypot(camera.x, camera.y, camera.z);
            if (!pointLength || !cameraLength) return true;
            const facing =
              (point.x * camera.x + point.y * camera.y + point.z * camera.z) /
              (pointLength * cameraLength);
            // Slightly above zero: a label exactly on the silhouette edge sits
            // half over empty space and reads as detached from the globe.
            return facing > 0.12;
          }

          if (typeof world.htmlElementVisibilityModifier === 'function') {
            world.htmlElementVisibilityModifier(el => {
              const lat = parseFloat(el.dataset.lat);
              const lng = parseFloat(el.dataset.lng);
              const visible = Number.isFinite(lat) && Number.isFinite(lng)
                ? isFacingCamera(lat, lng)
                : true;
              // Only `visibility` is touched, so a label's own opacity survives.
              el.style.visibility = visible ? 'visible' : 'hidden';
            });
          }

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
              .backgroundColor(canvasClearColor())
              .atmosphereColor(next.atmosphere);

            applyBackdrop();

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