//
//  NativeGlobeView.swift
//  SkyLine
//
//  Using iOS 15+ native MapKit globe view for authentic Earth experience
//

import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct NativeGlobeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360) // Global view
    )
    
    @State private var useImageryStyle = true // Premium iOS 17+ satellite imagery
    @State private var showingFlightList = false
    @State private var selectedFlight: Flight?
    @State private var isAutoRotating = false
    @State private var rotationTimer: Timer?
    @State private var currentLongitude: Double = 0
    @State private var rotationSpeed: Double = 0.5
    
    var body: some View {
        ZStack {
            // Premium iOS 17+ MapKit Globe with full 3D features
            Map(coordinateRegion: $region,
                interactionModes: [.pan, .zoom, .rotate],
                showsUserLocation: false,
                annotationItems: flightAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    FlightPinView(
                        flight: annotation.flight,
                        isSelected: selectedFlight?.id == annotation.flight.id,
                        theme: themeManager
                    ) {
                        selectedFlight = annotation.flight
                    }
                }
            }
            .mapStyle(useImageryStyle ? .imagery(elevation: .realistic) : .standard(elevation: .realistic)) // Stunning 3D globe!
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
            setupGlobeView()
            // Don't auto-start rotation to prevent initial glitches
            // User can manually enable it
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
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            // Map Style Toggle
            Button(action: toggleMapStyle) {
                Image(systemName: useImageryStyle ? "map.fill" : "globe.americas.fill")
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.success)
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
            
            // Rotation Speed Controls (when auto-rotating)
            if isAutoRotating {
                VStack(spacing: 4) {
                    Button(action: increaseSpeed) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(themeManager.currentTheme.colors.info)
                            .clipShape(Circle())
                    }
                    
                    Text("\(String(format: "%.1f", rotationSpeed))x")
                        .font(AppTypography.footnote)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .frame(width: 32)
                    
                    Button(action: decreaseSpeed) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
            
            // Reset Globe View
            Button(action: resetGlobeView) {
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
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
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
                HStack {
                    Text(flight.flightNumber)
                        .font(AppTypography.headline)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Spacer()
                    
                    Button(action: { selectedFlight = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.departure.code)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Text(flight.departure.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        Text(flight.departure.displayTime)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Text(flight.arrival.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        Text(flight.arrival.displayTime)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                Button("Focus on Route") {
                    focusOnFlight(flight)
                    selectedFlight = nil
                }
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(8)
            }
            .padding(20)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
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
                                        .font(AppTypography.airportCode)
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    Text("\(flight.departure.code) → \(flight.arrival.code)")
                                        .font(AppTypography.bodySmall)
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
                                    Text(flight.airline)
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
            guard let depCoordinate = flight.departure.coordinate else { return nil }
            return FlightAnnotation(
                flight: flight,
                coordinate: depCoordinate,
                type: .departure
            )
        } + flightStore.flights.compactMap { flight in
            guard let arrCoordinate = flight.arrival.coordinate else { return nil }
            return FlightAnnotation(
                flight: flight,
                coordinate: arrCoordinate,
                type: .arrival
            )
        }
    }
    
    // MARK: - Actions
    
    private func setupGlobeView() {
        // Set up for globe view - center at equator, maximum zoom out
        withAnimation(.easeInOut(duration: 1.0)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
        }
        currentLongitude = 0
    }
    
    private func toggleMapStyle() {
        withAnimation(.easeInOut(duration: 0.5)) {
            useImageryStyle.toggle()
        }
    }
    
    private func toggleAutoRotation() {
        if isAutoRotating {
            stopAutoRotation()
        } else {
            startAutoRotation()
        }
        isAutoRotating.toggle()
    }
    
    private func startAutoRotation() {
        guard !isAutoRotating else { return }
        
        currentLongitude = region.center.longitude
        
        // Use a slower, smoother timer interval to reduce glitching
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            currentLongitude += rotationSpeed * 0.3
            
            if currentLongitude > 180 {
                currentLongitude = -180 + (currentLongitude - 180)
            }
            
            // Remove animation for smoother performance
            region.center.longitude = currentLongitude
        }
    }
    
    private func stopAutoRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    private func increaseSpeed() {
        rotationSpeed = min(rotationSpeed + 0.2, 2.0) // Max 2.0x for smoother performance
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decreaseSpeed() {
        rotationSpeed = max(rotationSpeed - 0.2, 0.1) // Min 0.1x for very slow rotation
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func resetGlobeView() {
        setupGlobeView()
    }
    
    private func focusOnFlight(_ flight: Flight) {
        guard let departureCoord = flight.departure.coordinate,
              let arrivalCoord = flight.arrival.coordinate else {
            resetGlobeView()
            return
        }
        
        // Calculate center point and span to show both airports
        let centerLat = (departureCoord.latitude + arrivalCoord.latitude) / 2
        let centerLon = (departureCoord.longitude + arrivalCoord.longitude) / 2
        let latDelta = abs(departureCoord.latitude - arrivalCoord.latitude) * 2.0
        let lonDelta = abs(departureCoord.longitude - arrivalCoord.longitude) * 2.0
        
        withAnimation(.easeInOut(duration: 1.5)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(
                    latitudeDelta: max(latDelta, 20),
                    longitudeDelta: max(lonDelta, 20)
                )
            )
        }
        
        // Update current longitude for rotation
        currentLongitude = centerLon
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

// MARK: - Flight Pin View

struct FlightPinView: View {
    let flight: Flight
    let isSelected: Bool
    let theme: ThemeManager
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse ring (when selected)
                Circle()
                    .fill(theme.currentTheme.colors.primary.opacity(0.3))
                    .frame(width: isSelected ? 40 : 24, height: isSelected ? 40 : 24)
                    .scaleEffect(isSelected ? 1.3 : 1.0)
                    .opacity(isSelected ? 0.8 : 0.6)
                
                // Inner flight pin
                Circle()
                    .fill(statusColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Flight number label (when selected)
                if isSelected {
                    Text(flight.flightNumber)
                        .font(AppTypography.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.currentTheme.colors.primary)
                        .cornerRadius(6)
                        .offset(y: -30)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
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

// MARK: - Supporting Types
// FlightAnnotation is defined in GlobeView.swift and shared across views

// MARK: - Fallback for iOS 14 and below

struct LegacyGlobeView: View {
    var body: some View {
        VStack(spacing: 30) {
            Text("🌍")
                .font(.system(size: 64))
            
            Text("Globe View")
                .font(.title)
            
            Text("Requires iOS 15+ for 3D Globe")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    if #available(iOS 17.0, *) {
        NativeGlobeView()
            .environmentObject(ThemeManager())
            .environmentObject(FlightStore())
    } else {
        LegacyGlobeView()
    }
}