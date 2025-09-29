//
//  GlobeView.swift
//  SkyLine
//
//  3D Globe view with flight tracking and annotations
//

import SwiftUI
import MapKit

struct GlobeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of USA
        span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
    )
    
    @State private var mapType: MKMapType = .hybrid
    @State private var showingFlightList = false
    @State private var isAutoRotating = false
    @State private var selectedFlight: Flight?
    
    // Auto-rotation timer and state
    @State private var rotationTimer: Timer?
    @State private var rotationSpeed: Double = 1.0 // degrees per update
    @State private var currentLongitude: Double = -98.5795
    
    var body: some View {
        ZStack {
            // Main Map with satellite view for Earth-like appearance
            Map(coordinateRegion: $region, 
                interactionModes: [.pan, .zoom],
                showsUserLocation: false,
                annotationItems: flightAnnotations) { flightAnnotation in
                MapAnnotation(coordinate: flightAnnotation.coordinate) {
                    FlightAnnotationView(
                        flight: flightAnnotation.flight,
                        theme: themeManager,
                        isSelected: selectedFlight?.id == flightAnnotation.flight.id
                    ) {
                        selectedFlight = flightAnnotation.flight
                    }
                }
            }
            // Note: mapStyle is iOS 17+, for iOS 15 compatibility we'll handle this differently
            .ignoresSafeArea()
            
            // Control Panel
            VStack {
                HStack {
                    Spacer()
                    controlPanel
                }
                
                Spacer()
                
                // Bottom flight list toggle
                if !flightStore.flights.isEmpty {
                    bottomControls
                }
            }
            .padding()
            
            // Selected flight detail popup
            if let selectedFlight = selectedFlight {
                flightDetailPopup(flight: selectedFlight)
            }
        }
        .onAppear {
            zoomToGlobeView()
            // Start auto-rotation by default for a more earth-like experience
            startAutoRotation()
        }
        .onDisappear {
            stopAutoRotation()
        }
        .sheet(isPresented: $showingFlightList) {
            flightListSheet
        }
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
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
            
            // Map Type Toggle
            Button(action: toggleMapType) {
                Image(systemName: mapType == .standard ? "map" : "globe.americas.fill")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.success)
                    .clipShape(Circle())
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
            
            // Auto-Rotate Toggle
            Button(action: toggleAutoRotation) {
                Image(systemName: isAutoRotating ? "pause.circle.fill" : "play.circle.fill")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isAutoRotating ? themeManager.currentTheme.colors.success : themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
            
            // Rotation Speed Control (when rotating)
            if isAutoRotating {
                VStack(spacing: 4) {
                    Button(action: increaseRotationSpeed) {
                        Image(systemName: "plus.circle.fill")
                            .font(AppTypography.flightTime)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(themeManager.currentTheme.colors.info)
                            .clipShape(Circle())
                    }
                    
                    Text("\(String(format: "%.1f", rotationSpeed))x")
                        .font(AppTypography.captionBold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .frame(width: 32)
                    
                    Button(action: decreaseRotationSpeed) {
                        Image(systemName: "minus.circle.fill")
                            .font(AppTypography.flightTime)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(themeManager.currentTheme.colors.warning)
                            .clipShape(Circle())
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(themeManager.currentTheme.colors.surface.opacity(0.9))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Reset View
            Button(action: zoomToGlobeView) {
                Image(systemName: "scope")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.textSecondary)
                    .clipShape(Circle())
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack {
            Button(action: { showingFlightList = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(AppTypography.bodyBold)
                    
                    Text("\(flightStore.flights.count) Flights")
                        .font(AppTypography.bodyBold)
                    
                    Image(systemName: "chevron.up")
                        .font(AppTypography.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(25)
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            
            Spacer()
        }
    }
    
    // MARK: - Flight Detail Popup
    
    @ViewBuilder
    private func flightDetailPopup(flight: Flight) -> some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(flight.flightNumber)
                        .font(AppTypography.flightNumber)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Spacer()
                    
                    Button(action: { selectedFlight = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.headline)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                // Route
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.departure.code)
                            .font(AppTypography.airportCode)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text(flight.departure.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.departure.displayTime)
                            .font(AppTypography.flightTime)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "airplane")
                        .font(AppTypography.headline)
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .rotationEffect(.degrees(90))
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(flight.arrival.code)
                            .font(AppTypography.airportCode)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text(flight.arrival.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.arrival.displayTime)
                            .font(AppTypography.flightTime)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                // Status and details
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(for: flight.status))
                                .frame(width: 8, height: 8)
                            
                            Text(flight.status.displayName)
                                .font(AppTypography.flightTime)
                                .foregroundColor(statusColor(for: flight.status))
                        }
                        
                        Text(flight.airline ?? "Unknown Airline")
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("Track Flight") {
                        // Focus on this flight's route
                        focusOnFlight(flight)
                        selectedFlight = nil
                    }
                    .font(AppTypography.flightTime)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.colors.primary)
                    .cornerRadius(8)
                }
            }
            .padding(20)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(16)
            .shadow(
                color: Color.black.opacity(0.2),
                radius: 12,
                x: 0,
                y: 6
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: selectedFlight)
    }
    
    // MARK: - Flight List Sheet
    
    private var flightListSheet: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(flightStore.flights) { flight in
                        Button(action: {
                            focusOnFlight(flight)
                            selectedFlight = flight
                            showingFlightList = false
                        }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flight.flightNumber)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    
                                    Text("\(flight.departure.code) → \(flight.arrival.code)")
                                        .font(AppTypography.body)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(flight.status.displayName)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(statusColor(for: flight.status))
                                        .cornerRadius(4)
                                    
                                    Text(flight.airline ?? "Unknown Airline")
                                        .font(AppTypography.footnote)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                            .padding(16)
                            .background(themeManager.currentTheme.colors.surface)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.colors.background)
            .navigationTitle("Flights on Globe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        showingFlightList = false
                    }
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var flightAnnotations: [FlightAnnotation] {
        flightStore.flights.compactMap { flight in
            // Create annotation for departure location
            guard let depCoordinate = flight.departure.coordinate else { return nil }
            return FlightAnnotation(
                flight: flight,
                coordinate: depCoordinate,
                type: .departure
            )
        } + flightStore.flights.compactMap { flight in
            // Create annotation for arrival location
            guard let arrCoordinate = flight.arrival.coordinate else { return nil }
            return FlightAnnotation(
                flight: flight,
                coordinate: arrCoordinate,
                type: .arrival
            )
        }
    }
    
    // MARK: - Methods
    
    private func toggleMapType() {
        withAnimation(.easeInOut(duration: 0.3)) {
            mapType = mapType == .standard ? .hybrid : .standard
        }
    }
    
    private func toggleAutoRotation() {
        if isAutoRotating {
            stopAutoRotation()
        } else {
            startAutoRotation()
        }
    }
    
    private func increaseRotationSpeed() {
        rotationSpeed = min(rotationSpeed + 0.5, 5.0) // Max 5x speed
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decreaseRotationSpeed() {
        rotationSpeed = max(rotationSpeed - 0.5, 0.2) // Min 0.2x speed
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func startAutoRotation() {
        guard !isAutoRotating else { return }
        isAutoRotating = true
        
        // Start rotation from current position
        currentLongitude = region.center.longitude
        
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Smooth, continuous rotation like Earth
            currentLongitude += rotationSpeed
            
            // Wrap around at 180/-180
            if currentLongitude > 180 {
                currentLongitude = -180 + (currentLongitude - 180)
            }
            
            withAnimation(.linear(duration: 0.05)) {
                region.center.longitude = currentLongitude
            }
        }
    }
    
    private func stopAutoRotation() {
        isAutoRotating = false
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    private func zoomToGlobeView() {
        // Reset to Earth view - show more of the globe
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20.0, longitude: currentLongitude),
                span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 160) // Much wider view
            )
        }
    }
    
    private func focusOnFlight(_ flight: Flight) {
        guard let departureCoord = flight.departure.coordinate,
              let arrivalCoord = flight.arrival.coordinate else {
            // Fallback to global view if coordinates are missing
            zoomToGlobeView()
            return
        }
        
        // Calculate center point between departure and arrival
        let centerLat = (departureCoord.latitude + arrivalCoord.latitude) / 2
        let centerLon = (departureCoord.longitude + arrivalCoord.longitude) / 2
        
        // Calculate span to show both airports
        let latDelta = abs(departureCoord.latitude - arrivalCoord.latitude) * 1.5
        let lonDelta = abs(departureCoord.longitude - arrivalCoord.longitude) * 1.5
        
        withAnimation(.easeInOut(duration: 1.2)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(
                    latitudeDelta: max(latDelta, 10),
                    longitudeDelta: max(lonDelta, 10)
                )
            )
        }
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

// MARK: - Supporting Types

struct FlightAnnotation: Identifiable {
    let id = UUID()
    let flight: Flight
    let coordinate: CLLocationCoordinate2D
    let type: AnnotationType
    
    enum AnnotationType {
        case departure, arrival
    }
}

struct FlightAnnotationView: View {
    let flight: Flight
    let theme: ThemeManager
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer ring (pulse effect when selected)
                Circle()
                    .fill(theme.currentTheme.colors.primary.opacity(0.3))
                    .frame(width: isSelected ? 32 : 20, height: isSelected ? 32 : 20)
                    .scaleEffect(isSelected ? 1.2 : 1.0)
                    .opacity(isSelected ? 1.0 : 0.7)
                
                // Inner circle
                Circle()
                    .fill(statusColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                
                // Flight number (when selected)
                if isSelected {
                    Text(flight.flightNumber)
                        .font(AppTypography.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(theme.currentTheme.colors.primary)
                        .cornerRadius(4)
                        .offset(y: -20)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: isSelected)
    }
    
    private var statusColor: Color {
        switch flight.status {
        case .boarding: return theme.currentTheme.colors.statusBoarding
        case .departed: return theme.currentTheme.colors.statusDeparted
        case .inAir: return theme.currentTheme.colors.statusInAir
        case .landed: return theme.currentTheme.colors.statusLanded
        case .delayed: return theme.currentTheme.colors.statusDelayed
        case .cancelled: return theme.currentTheme.colors.statusCancelled
        }
    }
}

#Preview {
    GlobeView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
}