//
//  ModernFlightDetailView.swift
//  SkyLine
//
//  Extracted flight details view for reuse
//

import SwiftUI

struct ModernFlightDetailView: View {
    let flight: Flight
    let theme: ThemeManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header - exactly like Builder.io
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flight Details")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        if let aircraft = flight.aircraft?.type {
                            Text(aircraft)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Airplane icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.currentTheme.colors.primary.opacity(0.1))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "airplane")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(theme.currentTheme.colors.primary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Flight metrics grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    // Speed
                    MetricCard(
                        icon: "speedometer",
                        title: "SPEED",
                        value: speedValue,
                        unit: speedUnit,
                        theme: theme
                    )
                    
                    // Altitude
                    MetricCard(
                        icon: "arrow.up.circle",
                        title: "ALTITUDE",
                        value: altitudeValue,
                        unit: altitudeUnit,
                        theme: theme
                    )
                    
                    // Status
                    MetricCard(
                        icon: "info.circle",
                        title: "STATUS",
                        value: flight.status.displayName,
                        unit: "",
                        theme: theme
                    )
                    
                    // Progress
                    MetricCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "PROGRESS",
                        value: progressValue,
                        unit: "%",
                        theme: theme
                    )
                }
                .padding(.horizontal, 20)
                
                // Route visualization
                routeSection
                    .padding(.horizontal, 20)
                
                // Flight status card
                statusCard
                    .padding(.horizontal, 20)
                
                // Actions section
                actionsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .background(theme.currentTheme.colors.background)
    }
    
    // MARK: - Route Section
    
    private var routeSection: some View {
        VStack(spacing: 24) {
            // Route visualization
            HStack {
                // Departure
                VStack(spacing: 4) {
                    Text(flight.departure.code)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.text)
                    
                    Text(flight.departure.city)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                // Flight path
                VStack(spacing: 8) {
                    ZStack {
                        // Progress line background
                        Rectangle()
                            .fill(theme.currentTheme.colors.border)
                            .frame(height: 2)
                        
                        // Progress line fill
                        HStack {
                            Rectangle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(width: progressLineWidth, height: 2)
                            Spacer()
                        }
                        
                        // Airplane icon on the line
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(theme.currentTheme.colors.surface)
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: "airplane")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.currentTheme.colors.primary)
                                    .rotationEffect(.degrees(90))
                            }
                            .offset(x: progressOffset)
                            Spacer()
                        }
                    }
                    .frame(height: 24)
                    
                    Text(statusText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.primary)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Arrival
                VStack(spacing: 4) {
                    Text(flight.arrival.code)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.text)
                    
                    Text(flight.arrival.city)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                }
            }
        }
        .padding(24)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(24)
        .shadow(color: theme.currentTheme.colors.border.opacity(0.1), radius: 20, x: 0, y: 8)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Flight Information")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
                
                Spacer()
                
                Text(flight.departure.displayTime)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(theme.currentTheme.colors.text)
            }
            
            HStack {
                Text("Estimated Arrival")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
                
                Spacer()
                
                Text(flight.arrival.displayTime)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(theme.currentTheme.colors.text)
            }
            
            if let gate = flight.arrival.gate {
                HStack {
                    Text("Gate")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                    
                    Spacer()
                    
                    Text(gate)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.text)
                }
            }
            
            if let terminal = flight.arrival.terminal {
                HStack {
                    Text("Terminal")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                    
                    Spacer()
                    
                    Text(terminal)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(theme.currentTheme.colors.text)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    theme.currentTheme.colors.primary.opacity(0.05),
                    theme.currentTheme.colors.primary.opacity(0.02)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(theme.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 16) {
            // Add to Trip Button (instead of Track Live Flight)
            Button(action: {
                // TODO: Implement add to trip functionality
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Add to Trip")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            theme.currentTheme.colors.primary,
                            theme.currentTheme.colors.primary.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: theme.currentTheme.colors.primary.opacity(0.3), radius: 20, x: 0, y: 8)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var speedValue: String {
        if let position = flight.currentPosition {
            return String(format: "%.0f", position.speed)
        }
        return "N/A"
    }
    
    private var speedUnit: String {
        return flight.currentPosition != nil ? "km/h" : ""
    }
    
    private var altitudeValue: String {
        if let position = flight.currentPosition {
            let feet = Int(position.altitude * 3.28084)
            return feet.formatted()
        }
        return "N/A"
    }
    
    private var altitudeUnit: String {
        return flight.currentPosition != nil ? "ft" : ""
    }
    
    private var progressValue: String {
        if let progress = flight.progress {
            return String(format: "%.0f", progress * 100)
        }
        return "0"
    }
    
    private var progressLineWidth: CGFloat {
        let progress = flight.progress ?? 0.0
        return 120 * progress // Assuming 120pt wide line
    }
    
    private var progressOffset: CGFloat {
        let progress = flight.progress ?? 0.0
        return (120 * progress) - 60 // Center at start, move right with progress
    }
    
    private var statusText: String {
        switch flight.status {
        case .boarding:
            return "Boarding"
        case .departed:
            return "Departed" 
        case .inAir:
            return "In Flight"
        case .landed:
            return "Landed"
        case .delayed:
            return "Delayed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

#Preview {
    ModernFlightDetailView(
        flight: .sampleInAir,
        theme: ThemeManager()
    )
}