//
//  FlightDetailView.swift
//  SkyLine
//
//  Detailed flight information view
//

import SwiftUI
import MapKit

struct FlightDetailView: View {
    let flight: Flight
    let theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var flightStore: FlightStore
    @State private var region = MKCoordinateRegion()
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection
                    
                    // Route Map Section
                    if let depCoord = flight.departure.coordinate,
                       let arrCoord = flight.arrival.coordinate {
                        mapSection(departure: depCoord, arrival: arrCoord)
                    }
                    
                    // Flight Information
                    flightInfoSection
                    
                    // Aircraft Information
                    if let aircraft = flight.aircraft {
                        aircraftInfoSection(aircraft)
                    }
                    
                    // Current Position (if available)
                    if let position = flight.currentPosition {
                        currentPositionSection(position)
                    }
                    
                    // Actions Section
                    actionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Flight Details")
            .navigationBarTitleDisplayMode(.inline)
            .background(theme.currentTheme.colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(theme.currentTheme.colors.primary)
                    .font(AppTypography.bodyBold)
                }
            }
        }
        .alert("Delete Flight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                flightStore.removeFlightSync(flight.id)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this flight from your saved flights?")
        }
        .onAppear {
            setupMapRegion()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Flight Number and Airline
            VStack(spacing: 8) {
                Text(flight.flightNumber)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.currentTheme.colors.text)
                
                if let airline = flight.airline {
                    Text(airline)
                        .font(AppTypography.headline)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
            }
            
            // Status Badge
            StatusBadgeView(status: flight.status, theme: theme)
                .scaleEffect(1.2)
        }
        .padding(24)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private func mapSection(departure: CLLocationCoordinate2D, arrival: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            Map(coordinateRegion: $region, annotationItems: mapAnnotations) { annotation in
                MapPin(coordinate: annotation.coordinate, tint: annotation.color)
            }
            .frame(height: 200)
            .cornerRadius(AppRadius.lg)
            .disabled(true) // Make map non-interactive
        }
        .padding(20)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private var flightInfoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Flight Information")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(spacing: 16) {
                // Departure Info
                airportInfoView(
                    title: "Departure",
                    airport: flight.departure,
                    isArrival: false
                )
                
                Divider()
                    .background(theme.currentTheme.colors.border)
                
                // Arrival Info
                airportInfoView(
                    title: "Arrival",
                    airport: flight.arrival,
                    isArrival: true
                )
            }
        }
        .padding(20)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private func airportInfoView(title: String, airport: Airport, isArrival: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.captionBold)
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .textCase(.uppercase)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(airport.code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.currentTheme.colors.text)
                    
                    Text(airport.airport)
                        .font(AppTypography.body)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .lineLimit(2)
                    
                    Text(airport.city)
                        .font(AppTypography.caption)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(airport.displayTime)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.currentTheme.colors.text)
                    
                    if let date = flight.flightDate {
                        Text(formatFlightDate(date))
                            .font(AppTypography.caption)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                    }
                    
                    if airport.hasDelay {
                        Text(airport.delayText)
                            .font(AppTypography.captionBold)
                            .foregroundColor(theme.currentTheme.colors.error)
                    }
                }
            }
            
            // Terminal and Gate info
            if let terminal = airport.terminal, let gate = airport.gate {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terminal")
                            .font(AppTypography.caption)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        Text(terminal)
                            .font(AppTypography.bodyBold)
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gate")
                            .font(AppTypography.caption)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        Text(gate)
                            .font(AppTypography.bodyBold)
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func aircraftInfoSection(_ aircraft: Aircraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Aircraft Information")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(alignment: .leading, spacing: 12) {
                if let type = aircraft.type, !type.isEmpty {
                    infoRow(label: "Aircraft Type", value: type)
                }
                
                if let registration = aircraft.registration, !registration.isEmpty {
                    infoRow(label: "Registration", value: registration)
                }
                
                if let icao24 = aircraft.icao24, !icao24.isEmpty {
                    infoRow(label: "ICAO24", value: icao24)
                }
            }
        }
        .padding(20)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private func currentPositionSection(_ position: FlightPosition) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Position")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(label: "Altitude", value: position.altitudeInFeet)
                        infoRow(label: "Speed", value: position.speedInKnots)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        infoRow(label: "Heading", value: "\(Int(position.heading))°", alignment: .trailing)
                        
                        if let isGround = position.isGround {
                            infoRow(
                                label: "Status", 
                                value: isGround ? "On Ground" : "In Air",
                                alignment: .trailing
                            )
                        }
                    }
                }
                
                if let lastUpdate = position.lastUpdate {
                    Text("Last updated: \(formatLastUpdate(lastUpdate))")
                        .font(AppTypography.caption)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(20)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                showingDeleteAlert = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                    Text("Remove Flight")
                        .font(AppTypography.bodyBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.currentTheme.colors.error)
                .cornerRadius(AppRadius.md)
            }
        }
        .padding(20)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private func infoRow(label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(theme.currentTheme.colors.textSecondary)
            Text(value)
                .font(AppTypography.bodyBold)
                .foregroundColor(theme.currentTheme.colors.text)
        }
    }
    
    // MARK: - Helper Functions
    
    private var mapAnnotations: [MapAnnotation] -> {
        var annotations: [MapAnnotation] = []
        
        if let depCoord = flight.departure.coordinate {
            annotations.append(MapAnnotation(
                id: "departure",
                coordinate: depCoord,
                title: flight.departure.code,
                color: .blue
            ))
        }
        
        if let arrCoord = flight.arrival.coordinate {
            annotations.append(MapAnnotation(
                id: "arrival",
                coordinate: arrCoord,
                title: flight.arrival.code,
                color: .green
            ))
        }
        
        if let currentPos = flight.currentPosition {
            annotations.append(MapAnnotation(
                id: "current",
                coordinate: currentPos.coordinate,
                title: "Current Position",
                color: .red
            ))
        }
        
        return annotations
    }
    
    private func setupMapRegion() {
        guard let depCoord = flight.departure.coordinate,
              let arrCoord = flight.arrival.coordinate else { return }
        
        let centerLat = (depCoord.latitude + arrCoord.latitude) / 2
        let centerLon = (depCoord.longitude + arrCoord.longitude) / 2
        
        let latDelta = abs(depCoord.latitude - arrCoord.latitude) * 1.5
        let lonDelta = abs(depCoord.longitude - arrCoord.longitude) * 1.5
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(
                latitudeDelta: max(latDelta, 0.1),
                longitudeDelta: max(lonDelta, 0.1)
            )
        )
    }
    
    private func formatFlightDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func formatLastUpdate(_ updateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: updateString) else {
            return updateString
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Map Annotation Model

struct MapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: Color
}

#Preview {
    FlightDetailView(
        flight: .sampleInAir,
        theme: ThemeManager()
    )
    .environmentObject(FlightStore())
}