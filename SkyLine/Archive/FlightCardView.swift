//
//  FlightCardView.swift
//  SkyLine
//
//  Boarding pass-style flight card component matching React Native design
//

import SwiftUI

struct FlightCardView: View {
    let flight: Flight
    let showSaveButton: Bool
    let showDeleteButton: Bool
    let theme: ThemeManager
    let onTap: () -> Void
    let onSave: (() -> Void)?
    let onDelete: (() -> Void)?
    
    init(
        flight: Flight,
        showSaveButton: Bool = false,
        showDeleteButton: Bool = false,
        theme: ThemeManager,
        onTap: @escaping () -> Void = {},
        onSave: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.flight = flight
        self.showSaveButton = showSaveButton
        self.showDeleteButton = showDeleteButton
        self.theme = theme
        self.onTap = onTap
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Main boarding pass section
                HStack(spacing: 16) {
                    // Left section - Departure
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.departure.code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        Text(flight.departure.city)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.departure.displayTime)
                            .font(AppTypography.bodyBold)
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    
                    // Center section - Flight path
                    VStack(spacing: 8) {
                        // Flight number
                        Text(flight.flightNumber)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.currentTheme.colors.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.currentTheme.colors.primary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(theme.currentTheme.colors.primary, lineWidth: 1)
                            )
                            .cornerRadius(4)
                        
                        // Flight path visualization
                        HStack(spacing: 0) {
                            Circle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(width: 6, height: 6)
                            
                            Rectangle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(height: 2)
                                .frame(maxWidth: 60)
                            
                            Image(systemName: "airplane")
                                .font(AppTypography.caption)
                                .foregroundColor(theme.currentTheme.colors.primary)
                                .rotationEffect(.degrees(90))
                            
                            Rectangle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(height: 2)
                                .frame(maxWidth: 60)
                            
                            Circle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(width: 6, height: 6)
                        }
                        
                        // Airline
                        Text(flight.airline ?? "Unknown Airline")
                            .font(AppTypography.footnote)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                    }
                    
                    Spacer()
                    
                    // Right section - Arrival
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(flight.arrival.code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        Text(flight.arrival.city)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.arrival.displayTime)
                            .font(AppTypography.bodyBold)
                            .foregroundColor(theme.currentTheme.colors.text)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(theme.currentTheme.colors.surface)
                
                // Perforation line
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { _ in
                        Circle()
                            .fill(theme.currentTheme.colors.background)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.vertical, 2)
                .background(theme.currentTheme.colors.surface)
                
                // Bottom section - Details and status
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        // Status badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(flight.status.displayName)
                                .font(AppTypography.captionBold)
                                .foregroundColor(statusColor)
                        }
                        
                        // Additional details
                        if let gate = flight.departure.gate {
                            Text("Gate \(gate)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                        }
                        
                        if let aircraft = flight.aircraft {
                            Text(aircraft.model)
                                .font(AppTypography.footnote)
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                                .textCase(.uppercase)
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        if showDeleteButton {
                            Button(action: { onDelete?() }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(theme.currentTheme.colors.error)
                                    .clipShape(Circle())
                            }
                        }
                        
                        if showSaveButton {
                            Button(action: { onSave?() }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(theme.currentTheme.colors.success)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(theme.currentTheme.colors.surface)
            }
            .background(theme.currentTheme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.currentTheme.colors.border, lineWidth: 1)
            )
            .shadow(
                color: theme.currentTheme.colors.shadow.opacity(0.1),
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    let themeManager = ThemeManager()
    let sampleFlight = Flight.sampleData[0]
    
    VStack(spacing: 16) {
        FlightCardView(
            flight: sampleFlight,
            showSaveButton: true,
            theme: themeManager
        ) {
            print("Tapped flight")
        } onSave: {
            print("Save flight")
        }
        
        FlightCardView(
            flight: Flight.sampleData[1],
            showDeleteButton: true,
            theme: themeManager
        ) {
            print("Tapped flight")
        } onDelete: {
            print("Delete flight")
        }
    }
    .padding()
    .background(themeManager.currentTheme.colors.background)
    .environmentObject(themeManager)
}