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
    
    @ObservedObject var coordinator: WebViewCoordinator
    let currentTab: SkyLineTab?
    @State private var isGlobeReady = false
    @State private var isAutoRotating = true
    @State private var lastFlightDataHash: String = ""
    @State private var lastVisitedCitiesHash: String = ""
    @State private var lastTripLocationsHash: String = ""
    @State private var lastTabHash: String = ""
    
    
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
                            // Temporarily override currentTab for this update
                            let originalTab = self.currentTab
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
        
        // Determine what data to show based on provided tab
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
        
        // Collect departure and arrival airports (only when showing flights)
        let departureAirports = shouldShowFlights ? flightStore.flights.compactMap { flight -> [String: Any]? in
            guard let coordinate = flight.departure.coordinate else { return nil }
            return [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude,
                "name": flight.departure.code,
                "color": "#007AFF"
            ]
        } : []
        
        let arrivalAirports = shouldShowFlights ? flightStore.flights.compactMap { flight -> [String: Any]? in
            guard let coordinate = flight.arrival.coordinate else { return nil }
            return [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude,
                "name": flight.arrival.code,
                "color": "#007AFF"
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
                "color": "#00C851", // Green color for visited cities
                "isVisited": true,
                "tripCount": city.tripCount,
                "lastVisited": city.lastVisited.timeIntervalSince1970
            ]
        } : []

        // Add all trip locations with status (only when showing cities)
        let tripLocations = shouldShowCities ? tripStore.tripLocations.map { location -> [String: Any] in
            // Color based on trip status:
            // Completed: #006bff (blue, same as flight paths)
            // Upcoming: #FFA500 (orange)
            // Active: #00C851 (green)
            let color: String
            switch location.status {
            case "completed":
                color = "#006bff"
            case "upcoming":
                color = "#FFA500"
            case "active":
                color = "#00C851"
            default:
                color = "#006bff"
            }

            return [
                "lat": location.latitude,
                "lng": location.longitude,
                "name": location.name,
                "state": location.state ?? "",
                "country": location.country ?? "",
                "tripId": location.tripId,
                "status": location.status,
                "color": color,
                "startDate": location.startDate.timeIntervalSince1970,
                "endDate": location.endDate.timeIntervalSince1970
            ]
        } : []
        
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
        
        // Use the updated function call with visited cities and trip locations
        let tabMode = tab?.rawValue ?? "all"
        let jsCode = """
            console.log('🎯 Globe update for tab mode: \(tabMode)');
            console.log('About to call updateGlobeData with:', {
                flightPaths: \(flightPathsJson),
                airports: \(airportsJson),
                visitedCities: \(visitedCitiesJson),
                tripLocations: \(tripLocationsJson),
                tabMode: '\(tabMode)'
            });

            if (window.updateGlobeData) {
                console.log('Calling updateGlobeData function...');
                window.updateGlobeData(\(flightPathsJson), \(airportsJson), \(visitedCitiesJson), \(tripLocationsJson), '\(tabMode)');
                console.log('updateGlobeData called successfully');
            } else if (window.updateFlightData) {
                console.log('Falling back to updateFlightData function...');
                window.updateFlightData(\(flightPathsJson), \(airportsJson));
                console.log('updateFlightData called successfully (fallback)');
            } else {
                console.error('Neither window.updateGlobeData nor window.updateFlightData found!');
            }
        """
        
        coordinator.evaluateJavaScript(jsCode)
    }
    
    // MARK: - Control Actions
    
    private func toggleAutoRotation() {
        coordinator.evaluateJavaScript("""
            if (window.toggleAutoRotate) {
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
        return """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { 
      margin: 0; 
      padding: 0;
      background: #000011;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
      font-family: Arial, sans-serif;
    }
    #globeViz {
      width: 100vw;
      height: 100vh;
    }
    .status {
      position: absolute;
      top: 20px;
      left: 20px;
      color: white;
      background: rgba(0,0,0,0.7);
      padding: 10px;
      border-radius: 5px;
      z-index: 1000;
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
          const world = new Globe(document.getElementById('globeViz'))
            .globeImageUrl('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAwMDAiLz48L3N2Zz4=')
            .backgroundColor('#000011')
            .showAtmosphere(true)
            .atmosphereColor('#4F94CD')
            .enablePointerInteraction(true);
            
          world.controls().autoRotate = true;
          world.controls().autoRotateSpeed = 0.3;
          
          // Set initial zoom level (higher = more zoomed out)
          world.pointOfView({ altitude: 4.0 });
          
          // Initialize empty flight data
          let arcsData = [];
          let pointsData = [];
          
          // Setup flight paths
          world
            .arcsData(arcsData)
            .arcStartLat(d => d.startLat)
            .arcStartLng(d => d.startLng)
            .arcEndLat(d => d.endLat)
            .arcEndLng(d => d.endLng)
            .arcLabel(d => d.flightNumber + ': ' + (d.status || 'Unknown'))
            .arcColor(() => ['#006bff', 'rgba(0, 107, 255, 0.8)'])
            .arcStroke(2.0)
            .arcDashLength(0.4)
            .arcDashGap(0.05)
            .arcDashAnimateTime(3000);
          
          // Store current theme globally
          window.currentTheme = 'dark';

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

          // Helper function to apply trip-aware hexagon coloring
          window.applyHexagonColors = function() {
            const defaultColor = window.currentTheme === 'light' ? '#000000' : '#ffffff';

            world
              .hexPolygonColor(d => {
                // Check if this country contains any trip location
                const countryTrips = (window.currentTripLocations || []).filter(trip => {
                  return isPointInCountry(trip.lat, trip.lng, d);
                });

                if (countryTrips.length > 0) {
                  // Prioritize: active > upcoming > completed
                  const activeTrip = countryTrips.find(t => t.status === 'active');
                  const upcomingTrip = countryTrips.find(t => t.status === 'upcoming');
                  const completedTrip = countryTrips.find(t => t.status === 'completed');

                  if (activeTrip) return '#00C851'; // Green
                  if (upcomingTrip) return '#FFA500'; // Orange
                  if (completedTrip) return '#006bff'; // Blue
                }

                return defaultColor;
              })
              .hexPolygonAltitude(() => 0.01)
              .hexPolygonUseDots(d => {
                const countryTrips = (window.currentTripLocations || []).filter(trip => {
                  return isPointInCountry(trip.lat, trip.lng, d);
                });
                return countryTrips.length === 0;
              });
          };

          // Add theme switching function
          window.setTheme = function(theme) {
            console.log('🎨 Setting theme to:', theme);
            window.currentTheme = theme; // Store theme for later use
            if (theme === 'light') {
              world.globeImageUrl('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiNGRkZGRkYiLz48L3N2Zz4=');
              world.backgroundColor('#FFFFFF');
              world.atmosphereColor('#CCE7FF');
              document.body.style.background = 'linear-gradient(180deg, #E8F4FD 0%, #B8E0FF 30%, #87CEEB 70%, #F0F8FF 100%)';
            } else {
              world.globeImageUrl('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAwMDAiLz48L3N2Zz4=');
              world.backgroundColor('#000011');
              world.atmosphereColor('#4F94CD');
              document.body.style.background = 'radial-gradient(ellipse at center, #1a1a2e 0%, #16213e 25%, #0f0f23 50%, #0a0a0a 100%)';
            }

            // Reapply trip-aware hexagon colors after theme change
            window.applyHexagonColors();
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
          
          // Enhanced globe data update function with visited cities, trip locations, and tab filtering
          window.updateGlobeData = function(flightPaths, airports, visitedCities, tripLocations, tabMode) {
            console.log('🎯 updateGlobeData called with:', flightPaths?.length, 'flights,', visitedCities?.length, 'visited cities,', tripLocations?.length, 'trip locations, tab mode:', tabMode);
            
            // Clear existing data first
            world.arcsData([]);
            world.pointsData([]);
            world.htmlElementsData([]);
            
            // Update flight paths - Swift already filtered the data, just display what we received
            if (flightPaths && flightPaths.length > 0) {
              arcsData = flightPaths.slice(0, 20); // Limit to 20 flights for performance
              world.arcsData(arcsData);
              console.log('✅ Flight paths updated:', arcsData.length, 'for tab:', tabMode);
            } else {
              arcsData = [];
              world.arcsData([]);
              console.log('🚫 No flight paths for tab:', tabMode);
            }
            
            // Combine airports and visited cities for display
            let allLocations = [];
            
            // Add airports - Swift already filtered the data, just display what we received
            if (flightPaths && flightPaths.length > 0) {
              // Create airport code overlays from flight paths
              const airportLabels = [];
              flightPaths.forEach(flight => {
                // Add departure airport
                airportLabels.push({
                  lat: flight.startLat,
                  lng: flight.startLng,
                  code: flight.departureCode || 'DEP',
                  type: 'airport',
                  color: '#007AFF'
                });
                // Add arrival airport  
                airportLabels.push({
                  lat: flight.endLat,
                  lng: flight.endLng,
                  code: flight.arrivalCode || 'ARR',
                  type: 'airport',
                  color: '#007AFF'
                });
              });
              allLocations = allLocations.concat(airportLabels);
            }
            
            // Store trip locations globally for country coloring
            window.currentTripLocations = tripLocations || [];

            // Apply trip-aware hexagon colors
            if (window.applyHexagonColors) {
              window.applyHexagonColors();
            }

            // Clear point markers (we're using hexagons instead)
            world.pointsData([]);

            // Keep only airport labels (no trip/city labels)
            const uniqueLabels = [];
            allLocations.forEach(location => {
              // Skip trip and visited city labels - we're using country colors instead
              if (location.type === 'trip' || location.type === 'visited') {
                return;
              }

              const exists = uniqueLabels.find(existing =>
                Math.abs(existing.lat - location.lat) < 0.5 &&
                Math.abs(existing.lng - location.lng) < 0.5
              );
              if (!exists) {
                uniqueLabels.push(location);
              }
            });
            
            // Add location labels as HTML elements
            if (uniqueLabels.length > 0) {
              world.htmlElementsData(uniqueLabels.slice(0, 40))
                .htmlLat(d => d.lat)
                .htmlLng(d => d.lng)
                .htmlAltitude(0.01)
                .htmlElement(d => {
                  const el = document.createElement('div');
                  el.innerHTML = d.code;

                  // Only show airport labels (simple styling)
                  el.style.cssText = `
                    color: #007AFF;
                    font-family: 'GeistMono-Regular', 'Monaco', 'Menlo', 'Consolas', monospace;
                    font-size: 9px;
                    font-weight: bold;
                    background: rgba(255, 255, 255, 0.9);
                    padding: 2px 4px;
                    border-radius: 3px;
                    border: 1px solid #007AFF;
                    text-align: center;
                    pointer-events: none;
                    white-space: nowrap;
                    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
                    transform: translate(-50%, -50%);
                  `;
                  return el;
                });
              
              console.log('✅ Location labels updated:', uniqueLabels.length, 'for tab:', tabMode);
            }
          };
          
          // Backward compatibility function
          window.updateFlightData = function(flightPaths, airports) {
            console.log('🎯 updateFlightData called (fallback mode)');
            window.updateGlobeData(flightPaths, airports, [], [], 'all');
          };
          
          // Add auto-rotation toggle
          window.toggleAutoRotate = function() {
            const controls = world.controls();
            controls.autoRotate = !controls.autoRotate;
            return controls.autoRotate;
          };
          
          // Add reset function
          window.resetRotation = function() {
            world.pointOfView({ lat: 0, lng: 0, altitude: 4.0 }, 1000);
            world.controls().autoRotate = true;
          };
          
          // Enhanced flight focusing with ID-based matching and visual highlighting
          let selectedFlightId = null;
          
          window.focusOnFlightById = function(flightId, flightNumber) {
            console.log("🎯 Attempting to focus on flight:", flightNumber, "ID:", flightId);
            console.log("📊 Available arcsData:", arcsData?.length || 0, "flights");
            
            if (!arcsData || arcsData.length === 0) {
              console.warn("⚠️ No flight data available in arcsData");
              return false;
            }
            
            // Find flight by ID first, then by flight number as fallback
            let flight = null;
            let flightIndex = -1;
            
            for (let i = 0; i < arcsData.length; i++) {
              const arc = arcsData[i];
              if (arc.flightId === flightId || 
                  (arc.flightNumber && arc.flightNumber === flightNumber)) {
                flight = arc;
                flightIndex = i;
                break;
              }
            }
            
            if (!flight) {
              console.warn("⚠️ Flight not found in arcsData:", flightNumber, "ID:", flightId);
              return false;
            }
            
            console.log("✅ Flight found at index:", flightIndex);
            
            // Calculate center point and focus
            const lat = (flight.startLat + flight.endLat) / 2;
            const lng = (flight.startLng + flight.endLng) / 2;
            
            // Set the point of view
            world.pointOfView({ lat, lng, altitude: 2.5 }, 1500);
            
            // Highlight the selected flight
            selectedFlightId = flightId;
            
            // Update arc colors to highlight selected flight
            world.arcColor((arc, index) => {
              console.log("🎨 Checking arc:", arc.flightNumber, "ID:", arc.flightId, "index:", index);
              console.log("🎯 Looking for:", flightNumber, "ID:", flightId);
              
              // Use ONLY flight ID for exact matching (no flight number fallback)
              if (arc.flightId === flightId) {
                console.log("🔵 EXACT MATCH! Setting BLUE for:", arc.flightNumber, "ID:", arc.flightId);
                return ["#006BFF", "rgba(0, 107, 255, 0.8)"]; // Highlighted flight - blue (same as default)
              } else {
                console.log("📏 No exact match, setting VERY THIN for:", arc.flightNumber, "ID:", arc.flightId);
                return ["rgba(0, 107, 255, 0.4)", "rgba(0, 107, 255, 0.3)"]; // Light blue for thin lines
              }
            });
            
            // Update stroke width for emphasis
            world.arcStroke((arc, index) => {
              if (arc.flightId === flightId) {
                return 4.0; // Thick stroke for selected flight
              } else {
                return 0.0001; // Nearly invisible stroke for background flights
              }
            });
            
            // Filter airport labels to show only selected flight's airports
            console.log("🏷️ Filtering airport labels for selected flight");
            const selectedFlightLabels = [
              {
                lat: flight.startLat,
                lng: flight.startLng,
                code: flight.departureCode || 'DEP'
              },
              {
                lat: flight.endLat,
                lng: flight.endLng,
                code: flight.arrivalCode || 'ARR'
              }
            ];
            
            world.htmlElementsData(selectedFlightLabels)
              .htmlLat(d => d.lat)
              .htmlLng(d => d.lng)
              .htmlAltitude(0.01)
              .htmlElement(d => {
                const el = document.createElement('div');
                el.innerHTML = d.code;
                el.style.cssText = `
                  color: #007AFF;
                  font-family: 'GeistMono-Regular', 'Monaco', 'Menlo', 'Consolas', monospace;
                  font-size: 10px;
                  font-weight: bold;
                  background: rgba(255, 255, 255, 0.9);
                  padding: 2px 4px;
                  border-radius: 3px;
                  border: 1px solid #007AFF;
                  text-align: center;
                  pointer-events: none;
                  white-space: nowrap;
                  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
                  transform: translate(-50%, -50%);
                `;
                return el;
              });
            
            console.log("🎨 Applied visual highlighting to flight:", flightId);
            console.log("🎯 Successfully focused on flight:", flightNumber);
            return true;
          };
          
          // Clear highlighting function
          window.clearFlightHighlight = function() {
            selectedFlightId = null;
            world.arcColor(() => ["#006bff", "rgba(0, 107, 255, 0.8)"]);
            world.arcStroke(2.0);
            
            // Restore all airport labels
            console.log("🏷️ Restoring all airport labels");
            if (arcsData && arcsData.length > 0) {
              const airportLabels = [];
              arcsData.forEach(flight => {
                // Add departure airport
                airportLabels.push({
                  lat: flight.startLat,
                  lng: flight.startLng,
                  code: flight.departureCode || 'DEP'
                });
                // Add arrival airport  
                airportLabels.push({
                  lat: flight.endLat,
                  lng: flight.endLng,
                  code: flight.arrivalCode || 'ARR'
                });
              });
              
              // Remove duplicates based on location
              const uniqueLabels = [];
              airportLabels.forEach(label => {
                const exists = uniqueLabels.find(existing => 
                  Math.abs(existing.lat - label.lat) < 0.1 && 
                  Math.abs(existing.lng - label.lng) < 0.1
                );
                if (!exists) {
                  uniqueLabels.push(label);
                }
              });
              
              // Restore airport code labels as HTML elements
              world.htmlElementsData(uniqueLabels.slice(0, 30))
                .htmlLat(d => d.lat)
                .htmlLng(d => d.lng)
                .htmlAltitude(0.01)
                .htmlElement(d => {
                  const el = document.createElement('div');
                  el.innerHTML = d.code;
                  el.style.cssText = `
                    color: #007AFF;
                    font-family: 'GeistMono-Regular', 'Monaco', 'Menlo', 'Consolas', monospace;
                    font-size: 10px;
                    font-weight: bold;
                    background: rgba(255, 255, 255, 0.9);
                    padding: 2px 4px;
                    border-radius: 3px;
                    border: 1px solid #007AFF;
                    text-align: center;
                    pointer-events: none;
                    white-space: nowrap;
                    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
                    transform: translate(-50%, -50%);
                  `;
                  return el;
                });
            }
            
            console.log("🎨 Cleared flight highlighting and restored all airport labels");
          };
          
          document.getElementById('status').innerHTML = 'Globe ready, loading countries...';
          console.log('🌍 Globe with flight support created successfully');
          console.log('📋 Available functions:', typeof window.updateFlightData, typeof window.setTheme);
          
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
            
            // Load country-level data
            fetch('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson')
              .then(res => {
                clearTimeout(timeoutId);
                if (!res.ok) throw new Error('Failed to fetch countries data');
                return res.json();
              })
              .then(countries => {
                console.log('✅ Countries data loaded:', countries.features.length);

                document.getElementById('status').innerHTML = 'Adding regions...';

                try {
                  world
                    .hexPolygonsData(countries.features)
                    .hexPolygonResolution(3) // Medium resolution for hexagons
                    .hexPolygonMargin(0.5) // Even larger margin for very small hexagons
                    .hexPolygonUseDots(true) // Use dots instead of solid polygons
                    .hexPolygonColor(() => '#ffffff')
                    .hexPolygonAltitude(0.01) // Elevated from globe surface
                    .hexPolygonLabel(() => null);
                } catch (error) {
                  console.log('⚠️ Full dataset failed, trying reduced set:', error.message);
                  // Fallback to reduced dataset if full one causes issues
                  world
                    .hexPolygonsData(regions.features.slice(0, 500))
                    .hexPolygonResolution(3)
                    .hexPolygonMargin(0.5)
                    .hexPolygonUseDots(true)
                    .hexPolygonColor(() => '#ffffff')
                    .hexPolygonAltitude(0.01)
                    .hexPolygonLabel(() => null);
                }

                console.log('🗺️ States/provinces added successfully');
                document.getElementById('status').innerHTML = 'Globe with countries ready!';
                
                // Monitor performance after adding countries
                window.monitorPerformance();
                
                // Signal that globe is fully ready for flight data
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
          document.getElementById('status').style.color = 'red';
        }
      };
      script.onerror = function() {
        console.error('❌ Failed to load Globe.gl');
        document.getElementById('status').innerHTML = 'Failed to load Globe.gl library';
        document.getElementById('status').style.color = 'red';
      };
      document.head.appendChild(script);
    }, 2000);
  </script>
</body>
</html>
"""
    }
    
    private func getGlobeHTML() -> String {
        return """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { 
      margin: 0; 
      padding: 0;
      background: #000;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
    }
    #globeViz {
      width: 100vw;
      height: 100vh;
    }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/globe.gl"></script>
</head>
<body>
  <div id="globeViz"></div>
  <script>
    console.log('🌍 Globe script started');
    window.INITIAL_ZOOM = 15.0;

    // Load country-level data only
    console.log('📡 Fetching countries data...');
    fetch('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson')
      .then(res => res.json())
      .then(countries => {
        console.log('✅ Countries data loaded:', countries.features.length);

        const initialTheme = window.initialTheme || 'dark';
        console.log('🎨 Initial theme:', initialTheme);
        
        let currentTheme;
        if (initialTheme === 'light') {
          currentTheme = {
            globeImage: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiNGRkZGRkYiLz48L3N2Zz4=',
            backgroundColor: '#F0F0F0',
            atmosphereColor: '#CCE7FF',
            countryColor: '#000000',
            flightPathColors: ['#006bff', 'rgba(0, 107, 255, 0.8)'],
            spaceBackground: 'linear-gradient(180deg, #E8F4FD 0%, #B8E0FF 30%, #87CEEB 70%, #F0F8FF 100%)'
          };
        } else {
          currentTheme = {
            globeImage: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAwMDAiLz48L3N2Zz4=',
            backgroundColor: '#000011',
            atmosphereColor: '#4F94CD',
            countryColor: '#ffffff',
            flightPathColors: ['#006bff', 'rgba(0, 107, 255, 0.8)'],
            spaceBackground: 'radial-gradient(ellipse at center, #1a1a2e 0%, #16213e 25%, #0f0f23 50%, #0a0a0a 100%)'
          };
        }

        document.body.style.background = currentTheme.spaceBackground;
        
        console.log('🌍 Creating Globe instance...');
        const world = new Globe(document.getElementById('globeViz'))
          .globeImageUrl(currentTheme.globeImage)
          .backgroundColor(currentTheme.backgroundColor)
          .showAtmosphere(false)
          .atmosphereColor(currentTheme.atmosphereColor)
          .atmosphereAltitude(0.15)
          .hexPolygonsData(countries.features)
          .hexPolygonResolution(3)
          .hexPolygonMargin(0.5)
          .hexPolygonUseDots(true)
          .hexPolygonColor(() => currentTheme.countryColor)
          .hexPolygonAltitude(0.01) // Elevated from globe surface
          .hexPolygonLabel(() => null)
          .enablePointerInteraction(true);
          
        // Set auto-rotation
        world.controls().autoRotate = true;
        world.controls().autoRotateSpeed = 0.3;
        world.controls().enableDamping = true;
        world.controls().dampingFactor = 0.05;
        
        let updateTimeout;
        function updateVisualsDebounced() {
          clearTimeout(updateTimeout);
          updateTimeout = setTimeout(() => {
            const pov = world.pointOfView();
            const altitude = pov.altitude || 4.0;
            const strokeWidth = Math.max(0.3, Math.min(3.0, altitude * 0.4));
            world.arcStroke(strokeWidth);
            
            if (pointsData && pointsData.length > 0) {
              const processedAirports = processAirportLabels(pointsData);
              world.htmlElementsData(processedAirports);
            }
          }, 200);
        }
        
        // Add debounced listener - only fires when interaction ends
        world.controls().addEventListener('end', updateVisualsDebounced);
        
        world.pointOfView({ altitude: window.INITIAL_ZOOM || 15.0 });
        
        const highlightedCities = [
          { lat: 40.7128, lng: -74.0060, name: 'NYC' },
          { lat: 51.5074, lng: -0.1278, name: 'LON' },
          { lat: 35.6762, lng: 139.6503, name: 'TYO' },
          { lat: -33.8688, lng: 151.2093, name: 'SYD' },
          { lat: 34.0522, lng: -118.2437, name: 'LAX' }
        ];
        
        // Add highlighted cities as small points with labels  
        world
          .pointsData(highlightedCities)
          .pointColor(() => 'orange')
          .pointAltitude(0)
          .pointRadius(0.04)
          .pointLabel(d => d.name)
          .pointsMerge(true);
        
        // Function to process airport labels with zoom-based visibility
        function processAirportLabels(airports) {
          if (!airports || airports.length === 0) return [];
          
          const pov = world.pointOfView();
          const altitude = pov.altitude || 4.0;
          
          // Dynamic distance threshold based on zoom level
          // Zoomed out: larger threshold (fewer airports), Zoomed in: smaller threshold (more airports)
          let DISTANCE_THRESHOLD;
          if (altitude > 5.0) {
            DISTANCE_THRESHOLD = 8.0; // Very far: only show well-spaced airports
          } else if (altitude > 3.0) {
            DISTANCE_THRESHOLD = 4.0; // Medium: show more airports
          } else if (altitude > 2.0) {
            DISTANCE_THRESHOLD = 2.0; // Close: show most airports
          } else {
            DISTANCE_THRESHOLD = 1.0; // Very close: show nearly all airports
          }
          
          const processed = [];
          
          // Sort airports by some priority (could be by importance or just keep original order)
          const sortedAirports = [...airports];
          
          for (let i = 0; i < sortedAirports.length; i++) {
            const airport = sortedAirports[i];
            let shouldShow = true;
            
            // Check if this airport is too close to any already processed airport
            for (let j = 0; j < processed.length; j++) {
              const existingAirport = processed[j];
              const distance = Math.sqrt(
                Math.pow(airport.lat - existingAirport.lat, 2) + 
                Math.pow(airport.lng - existingAirport.lng, 2)
              );
              
              if (distance < DISTANCE_THRESHOLD) {
                shouldShow = false;
                break;
              }
            }
            
            if (shouldShow) {
              processed.push(airport);
            }
          }
          
          return processed;
        }
        
        
        // Initialize flight data
        let arcsData = [];
        let pointsData = highlightedCities;
        
        world
          .arcsData(arcsData)
          .arcStartLat(d => d.startLat)
          .arcStartLng(d => d.startLng)
          .arcEndLat(d => d.endLat)
          .arcEndLng(d => d.endLng)
          .arcLabel(d => d.flightNumber + ': ' + (d.status || 'Unknown'))
          .arcColor(() => currentTheme.flightPathColors)
          .arcStroke(2.0) // Initial stroke, will be updated by debounced function
          .arcDashLength(0.4)
          .arcDashGap(0.05)
          .arcDashAnimateTime(3000)
          .arcCircularResolution(64)
          .onArcClick(arc => {
            world.controls().autoRotate = false;
            
            const midLat = (arc.startLat + arc.endLat) / 2;
            const midLng = (arc.startLng + arc.endLng) / 2;
            const latDiff = Math.abs(arc.endLat - arc.startLat);
            const lngDiff = Math.abs(arc.endLng - arc.startLng);
            const maxDiff = Math.max(latDiff, lngDiff);
            
            let altitude = 15.0;
            if (maxDiff > 50) altitude = 18.0;
            else if (maxDiff < 20) altitude = 12.0;
            
            world.pointOfView({ lat: midLat, lng: midLng, altitude: altitude }, 1500);
            setTimeout(updateVisualsDebounced, 1700);
            
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
              window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                type: 'FLIGHT_SELECTED',
                flight: arc
              }));
            }
            
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reactNativeWebView) {
              window.webkit.messageHandlers.reactNativeWebView.postMessage(JSON.stringify({
                type: 'AUTO_ROTATE_TOGGLED',
                autoRotate: false
              }));
            }
          });

        // Enhanced globe data update function with visited cities, trip locations, and tab filtering
        window.updateGlobeData = function(newFlightData, newAirportData, visitedCities, tripLocations, tabMode) {
          console.log('🎯 updateGlobeData called with:', newFlightData?.length, 'flights,', visitedCities?.length, 'visited cities,', tripLocations?.length, 'trip locations, tab mode:', tabMode);
          
          // Clear existing data first
          world.arcsData([]);
          world.pointsData([]);
          world.htmlElementsData([]);
          
          // Update flight paths - Swift already filtered the data, just display what we received
          if (newFlightData && newFlightData.length > 0) {
            const validFlights = newFlightData.filter(flight => 
              flight.startLat && flight.startLng && flight.endLat && flight.endLng
            );
            
            arcsData = validFlights.slice(0, 50);
            world.arcsData(arcsData);
            
            setTimeout(() => {
              world.arcStroke(world.arcStroke());
            }, 100);
            
            console.log('✅ Flight paths updated:', arcsData.length, 'for tab:', tabMode);
          } else {
            arcsData = [];
            world.arcsData([]);
            console.log('🚫 No flight paths for tab:', tabMode);
          }
          
          // Combine airports and visited cities
          let allLocations = [];
          
          // Add airports - Swift already filtered the data, just display what we received
          if (newAirportData && newAirportData.length > 0) {
            const airportLabels = newAirportData.map(airport => ({
              ...airport,
              type: 'airport'
            }));
            allLocations = allLocations.concat(airportLabels);
          }
          
          // Store trip locations globally for country coloring
          window.currentTripLocations = tripLocations || [];

          // Helper function to check if a point is in a country's boundaries
          function isPointInCountry(lat, lng, countryFeature) {
            if (!countryFeature || !countryFeature.geometry) return false;

            const geometry = countryFeature.geometry;
            const coords = geometry.coordinates;

            // Simple bounding box check for performance
            function isInBoundingBox(lat, lng, polygonCoords) {
              let minLat = Infinity, maxLat = -Infinity;
              let minLng = Infinity, maxLng = -Infinity;

              function processPoly(poly) {
                poly.forEach(point => {
                  const [pLng, pLat] = point;
                  if (pLat < minLat) minLat = pLat;
                  if (pLat > maxLat) maxLat = pLat;
                  if (pLng < minLng) minLng = pLng;
                  if (pLng > maxLng) maxLng = pLng;
                });
              }

              if (geometry.type === 'Polygon') {
                polygonCoords.forEach(processPoly);
              } else if (geometry.type === 'MultiPolygon') {
                polygonCoords.forEach(polygon => {
                  polygon.forEach(processPoly);
                });
              }

              // Use very tight margin to avoid overlapping neighboring countries
              const margin = 0.05; // Very small margin (~5.5km) for precise matching
              return lat >= (minLat - margin) && lat <= (maxLat + margin) &&
                     lng >= (minLng - margin) && lng <= (maxLng + margin);
            }

            return isInBoundingBox(lat, lng, coords);
          }

          // Update hexagon colors based on trips
          if (tripLocations && tripLocations.length > 0) {
            // Force refresh hexagon colors
            world.hexPolygonColor(d => {
              // Check if this country contains any trip location
              const countryTrips = window.currentTripLocations.filter(trip => {
                return isPointInCountry(trip.lat, trip.lng, d);
              });

              if (countryTrips.length > 0) {
                // Prioritize: active > upcoming > completed
                const activeTrip = countryTrips.find(t => t.status === 'active');
                const upcomingTrip = countryTrips.find(t => t.status === 'upcoming');
                const completedTrip = countryTrips.find(t => t.status === 'completed');

                if (activeTrip) return '#00C851'; // Green
                if (upcomingTrip) return '#FFA500'; // Orange
                if (completedTrip) return '#006bff'; // Blue
              }

              // Default color
              return currentTheme.countryColor;
            });
          } else {
            // Reset to default colors when no trips
            world.hexPolygonColor(() => currentTheme.countryColor);
          }

          // Clear point markers (we're using hexagons instead)
          world.pointsData([]);

          // Filter out trip/city labels - keep only airports
          const airportOnlyLocations = allLocations.filter(loc => loc.type !== 'trip' && loc.type !== 'visited');

          if (airportOnlyLocations.length > 0) {
            const processedLocations = processAirportLabels(airportOnlyLocations);
            
            world
              .htmlElementsData(processedLocations)
              .htmlLat(d => d.lat)
              .htmlLng(d => d.lng)
              .htmlAltitude(0.01)
              .htmlElement(d => {
                const el = document.createElement('div');
                el.innerHTML = d.name;

                // Only show airport labels (theme-aware styling)
                const isDark = currentTheme.backgroundColor === '#000011';
                const labelStyles = isDark ? {
                  color: 'rgba(255, 255, 255, 0.95)',
                  background: 'rgba(0, 0, 0, 0.7)',
                  border: '0.5px solid rgba(255, 255, 255, 0.3)',
                  shadow: '0 1px 3px rgba(0, 0, 0, 0.4)'
                } : {
                  color: 'rgba(0, 0, 0, 0.9)',
                  background: 'rgba(255, 255, 255, 0.8)',
                  border: '0.5px solid rgba(0, 0, 0, 0.2)',
                  shadow: '0 1px 3px rgba(0, 0, 0, 0.3)'
                };

                el.style.cssText = `
                  color: ${labelStyles.color};
                  font-family: 'GeistMono-Regular', 'Monaco', 'Menlo', 'Consolas', monospace;
                  font-size: 9px;
                  font-weight: 500;
                  background: ${labelStyles.background};
                  padding: 1px 4px;
                  border-radius: 2px;
                  border: ${labelStyles.border};
                  text-align: center;
                  pointer-events: none;
                  white-space: nowrap;
                  box-shadow: ${labelStyles.shadow};
                  transform: translate(-50%, -50%);
                `;
                return el;
              });
            
            console.log('✅ Location labels updated:', processedLocations.length, 'for tab:', tabMode);
          }
        };
        
        // Backward compatibility function
        window.updateFlightData = function(newFlightData, newAirportData) {
          console.log('🎯 updateFlightData called (fallback mode)');
          window.updateGlobeData(newFlightData, newAirportData, [], [], 'all');
        };

        // Control functions
        window.setTheme = function(theme) {
          if (theme === 'light') {
            currentTheme = {
              globeImage: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiNGRkZGRkYiLz48L3N2Zz4=',
              backgroundColor: '#F0F0F0',
              atmosphereColor: '#CCE7FF',
              countryColor: '#000000',
              flightPathColors: ['#006bff', 'rgba(0, 107, 255, 0.8)'],
              spaceBackground: 'linear-gradient(180deg, #E8F4FD 0%, #B8E0FF 30%, #87CEEB 70%, #F0F8FF 100%)'
            };
          } else {
            currentTheme = {
              globeImage: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAwMDAiLz48L3N2Zz4=',
              backgroundColor: '#000011',
              atmosphereColor: '#4F94CD',
              countryColor: '#ffffff',
              flightPathColors: ['#006bff', 'rgba(0, 107, 255, 0.8)'],
              spaceBackground: 'radial-gradient(ellipse at center, #1a1a2e 0%, #16213e 25%, #0f0f23 50%, #0a0a0a 100%)'
            };
          }
          
          document.body.style.background = currentTheme.spaceBackground;
          world
            .globeImageUrl(currentTheme.globeImage)
            .backgroundColor(currentTheme.backgroundColor)
            .atmosphereColor(currentTheme.atmosphereColor)
            .hexPolygonColor(() => currentTheme.countryColor)
            .arcColor(() => currentTheme.flightPathColors);
          
          if (pointsData && pointsData.length > 0) {
            const processedAirports = processAirportLabels(pointsData);
            world.htmlElementsData(processedAirports);
          }
        };
        
        window.toggleAutoRotate = function() {
          const controls = world.controls();
          controls.autoRotate = !controls.autoRotate;
          return controls.autoRotate;
        };
        
        
        window.resetRotation = function() {
          world.pointOfView({ lat: 0, lng: 0, altitude: 15.0 }, 1000);
          world.controls().autoRotate = true;
          setTimeout(updateVisualsDebounced, 1200);
        };
        
        
        // Enhanced flight focusing with ID-based matching and visual highlighting
        let selectedFlightId = null;
        
        window.focusOnFlightById = function(flightId, flightNumber) {
          console.log("🎯 Attempting to focus on flight:", flightNumber, "ID:", flightId);
          console.log("📊 Available arcsData:", arcsData?.length || 0, "flights");
          
          if (!arcsData || arcsData.length === 0) {
            console.warn("⚠️ No flight data available in arcsData");
            return false;
          }
          
          // Find flight by ID first, then by flight number as fallback
          let flight = null;
          let flightIndex = -1;
          
          for (let i = 0; i < arcsData.length; i++) {
            const arc = arcsData[i];
            if (arc.flightId === flightId || 
                (arc.flightNumber && arc.flightNumber === flightNumber)) {
              flight = arc;
              flightIndex = i;
              break;
            }
          }
          
          if (!flight) {
            console.warn("⚠️ Flight not found in arcsData:", flightNumber, "ID:", flightId);
            return false;
          }
          
          console.log("✅ Flight found at index:", flightIndex);
          
          // Calculate center point and focus
          const lat = (flight.startLat + flight.endLat) / 2;
          const lng = (flight.startLng + flight.endLng) / 2;
          
          // Set the point of view
          world.pointOfView({ lat, lng, altitude: 12.0 }, 1500);
          
          // Highlight the selected flight
          highlightFlight(flightId, flightIndex);
          
          setTimeout(updateVisualsDebounced, 1800);
          
          console.log("🎯 Successfully focused on flight:", flightNumber);
          return true;
        };
        
        // Visual highlighting function
        function highlightFlight(flightId, flightIndex) {
          selectedFlightId = flightId;
          
          // Update arc colors to highlight selected flight
          world.arcColor((arc, index) => {
            if (index === flightIndex) {
              return ["#FF6B35", "#FF8C42"]; // Highlighted flight - bright orange
            } else {
              return ["rgba(0, 107, 255, 0.3)", "rgba(0, 107, 255, 0.2)"]; // Dimmed
            }
          });
          
          // Update stroke width for emphasis
          world.arcStroke((arc, index) => {
            return index === flightIndex ? 3.5 : 1.5;
          });
          
          console.log("🎨 Applied visual highlighting to flight:", flightId);
        }
        
        // Clear highlighting function
        window.clearFlightHighlight = function() {
          selectedFlightId = null;
          world.arcColor(() => currentTheme.flightPathColors);
          world.arcStroke(2.0);
          
          // Restore all airport labels
          console.log("🏷️ Restoring all airport labels");
          if (arcsData && arcsData.length > 0) {
            const airportLabels = [];
            arcsData.forEach(flight => {
              // Add departure airport
              airportLabels.push({
                lat: flight.startLat,
                lng: flight.startLng,
                code: flight.departureCode || 'DEP'
              });
              // Add arrival airport  
              airportLabels.push({
                lat: flight.endLat,
                lng: flight.endLng,
                code: flight.arrivalCode || 'ARR'
              });
            });
            
            // Remove duplicates based on location
            const uniqueLabels = [];
            airportLabels.forEach(label => {
              const exists = uniqueLabels.find(existing => 
                Math.abs(existing.lat - label.lat) < 0.1 && 
                Math.abs(existing.lng - label.lng) < 0.1
              );
              if (!exists) {
                uniqueLabels.push(label);
              }
            });
            
            // Restore airport code labels as HTML elements
            world.htmlElementsData(uniqueLabels.slice(0, 30))
              .htmlLat(d => d.lat)
              .htmlLng(d => d.lng)
              .htmlAltitude(0.01)
              .htmlElement(d => {
                const el = document.createElement('div');
                el.innerHTML = d.code;
                el.style.cssText = `
                  color: #007AFF;
                  font-family: 'GeistMono-Regular', 'Monaco', 'Menlo', 'Consolas', monospace;
                  font-size: 10px;
                  font-weight: bold;
                  background: rgba(255, 255, 255, 0.9);
                  padding: 2px 4px;
                  border-radius: 3px;
                  border: 1px solid #007AFF;
                  text-align: center;
                  pointer-events: none;
                  white-space: nowrap;
                  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
                  transform: translate(-50%, -50%);
                `;
                return el;
              });
          }
          
          console.log("🎨 Cleared flight highlighting and restored all airport labels");
        };

        window.focusOnFlight = function(flightIndex) {
          if (arcsData[flightIndex]) {
            const flight = arcsData[flightIndex];
            const lat = (flight.startLat + flight.endLat) / 2;
            const lng = (flight.startLng + flight.endLng) / 2;
            world.pointOfView({ lat, lng, altitude: 15.0 }, 1000);
            setTimeout(updateVisualsDebounced, 1200);
          }
        };
        
        window.clearFlightPaths = function() {
          arcsData = [];
          world.arcsData(arcsData);
          world.htmlElementsData([]);
        };
        
        setTimeout(() => {
          updateVisualsDebounced();
        }, 300);
        
        // Globe initialization complete
        console.log('🎉 Globe initialized successfully');
        console.log('📋 Available functions:', typeof window.updateFlightData, typeof window.setTheme);
      })
      .catch(error => {
        const world = new Globe(document.getElementById('globeViz'))
          .globeImageUrl('https://cdn.jsdelivr.net/npm/three-globe/example/img/earth-night.jpg')
          .backgroundColor('#000011')
          .showAtmosphere(false)
          .atmosphereColor('#4F94CD')
          .enablePointerInteraction(true);
          
        world.controls().autoRotate = true;
        
        console.log('Globe fallback initialized');
      });</an_parameter>
</invoke>
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