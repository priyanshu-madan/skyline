//
//  FlightDetailsInSheet.swift
//  SkyLine
//
//  Flight details view displayed within the bottom sheet
//

import SwiftUI

struct FlightDetailsInSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    let flight: Flight
    let onClose: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Flight number and airline info
                VStack(spacing: 8) {
                    Text(flight.flightNumber)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.airline ?? "Unknown Airline")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Flight route section
                VStack(spacing: 20) {
                    // Route visualization
                    HStack(spacing: 0) {
                        // Departure
                        VStack(alignment: .leading, spacing: 8) {
                            Text(flight.departure.displayTime)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            Text(flight.departure.code)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            
                            Text(flight.departure.city)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        // Flight path visualization
                        VStack(spacing: 12) {
                            // Flight status badge
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(getStatusColor(for: flight.status))
                                    .frame(width: 10, height: 10)
                                
                                Text(flight.status.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(getStatusColor(for: flight.status))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(getStatusColor(for: flight.status).opacity(0.1))
                            .cornerRadius(16)
                            
                            // Airplane icon with flight path line
                            ZStack {
                                // Flight path line
                                Rectangle()
                                    .fill(themeManager.currentTheme.colors.textSecondary.opacity(0.3))
                                    .frame(height: 2)
                                    .frame(maxWidth: 100)
                                
                                // Airplane icon
                                Circle()
                                    .fill(themeManager.currentTheme.colors.primary)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "airplane")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                            .rotationEffect(.degrees(45))
                                    )
                            }
                            
                            // Flight duration
                            Text("2h 30m")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Arrival
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(flight.arrival.displayTime)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            Text(flight.arrival.code)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            
                            Text(flight.arrival.city)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
                
                // Flight details sections
                VStack(spacing: 24) {
                    // Basic flight info
                    VStack(spacing: 16) {
                        HStack {
                            Text("Flight Information")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            HStack {
                                FlightInfoItem(title: "Airline", value: flight.airline ?? "Unknown")
                                Spacer()
                                FlightInfoItem(title: "Aircraft", value: flight.aircraft?.displayName ?? "Unknown", alignment: .trailing)
                            }
                            
                            HStack {
                                FlightInfoItem(title: "Date", value: DateFormatter.flightCardDate.string(from: flight.date))
                                Spacer()
                                FlightInfoItem(title: "Flight No.", value: flight.flightNumber, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Terminal and gate info
                    VStack(spacing: 16) {
                        HStack {
                            Text("Terminal & Gate Information")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            HStack {
                                FlightInfoItem(title: "Departure Terminal", value: flight.departure.terminal ?? "TBD")
                                Spacer()
                                FlightInfoItem(title: "Departure Gate", value: flight.departure.gate ?? "TBD", alignment: .trailing)
                            }
                            
                            HStack {
                                FlightInfoItem(title: "Arrival Terminal", value: flight.arrival.terminal ?? "TBD")
                                Spacer()
                                FlightInfoItem(title: "Arrival Gate", value: flight.arrival.gate ?? "TBD", alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Current position info (if available)
                    if let position = flight.currentPosition {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Current Position")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                HStack {
                                    FlightInfoItem(title: "Altitude", value: position.altitudeInFeet)
                                    Spacer()
                                    FlightInfoItem(title: "Speed", value: position.speedInKnots, alignment: .trailing)
                                }
                                
                                HStack {
                                    FlightInfoItem(title: "Coordinates", value: String(format: "%.4f, %.4f", position.latitude, position.longitude))
                                    Spacer()
                                    FlightInfoItem(title: "Heading", value: "\(Int(position.heading))°", alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Data source info
                    VStack(spacing: 12) {
                        HStack {
                            Text("Data Source")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            Spacer()
                        }
                        
                        HStack {
                            FlightInfoItem(title: "Provider", value: flight.dataSource.displayName)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .background(themeManager.currentTheme.colors.background)
    }
    
    private func getStatusColor(for status: FlightStatus) -> Color {
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

struct FlightInfoItem: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let value: String
    let alignment: HorizontalAlignment
    
    init(title: String, value: String, alignment: HorizontalAlignment = .leading) {
        self.title = title
        self.value = value
        self.alignment = alignment
    }
    
    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.text)
                .lineLimit(2)
        }
    }
}

#Preview {
    FlightDetailsInSheet(
        flight: Flight.sample,
        onClose: {}
    )
    .environmentObject(ThemeManager())
}