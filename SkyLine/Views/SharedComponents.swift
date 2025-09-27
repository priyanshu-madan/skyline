//
//  SharedComponents.swift
//  SkyLine
//
//  Shared UI components used across the app
//

import SwiftUI
import PhotosUI

// MARK: - Search Result Card

struct SearchResultCard: View {
    let flight: Flight
    let onSave: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Flight Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.flightNumber)
                        .font(AppTypography.flightNumber)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    Text(flight.airline)
                        .font(AppTypography.flightStatus)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                Spacer()
                
                // Status Badge
                Text(flight.status.displayName)
                    .font(AppTypography.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: flight.status))
                    .cornerRadius(6)
            }
            
            // Route Information
            HStack(spacing: 16) {
                // Departure
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.departure.code)
                        .font(AppTypography.headline)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    Text(flight.departure.airport)
                        .font(AppTypography.footnote)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                    if !flight.departure.time.isEmpty {
                        Text(flight.departure.time)
                            .font(AppTypography.captionBold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                Spacer()
                
                // Flight Icon
                Image(systemName: "airplane")
                    .font(AppTypography.bodyBold)
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .rotationEffect(.degrees(45))
                
                Spacer()
                
                // Arrival
                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.arrival.code)
                        .font(AppTypography.headline)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    Text(flight.arrival.airport)
                        .font(AppTypography.footnote)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                    if !flight.arrival.time.isEmpty {
                        Text(flight.arrival.time)
                            .font(AppTypography.captionBold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
            }
            
            // Save Button with Glass Effect
            Button(action: onSave) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(AppTypography.bodyBold)
                    Text("Save Flight")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.colors.surface)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func statusColor(for status: FlightStatus) -> Color {
        switch status {
        case .boarding: return Color.orange
        case .departed: return Color.blue
        case .inAir: return Color.green
        case .landed: return Color.gray
        case .delayed: return Color.red
        case .cancelled: return Color.red
        }
    }
}

// MARK: - Flight Detail Sheet

struct FlightDetailSheet: View {
    let flight: Flight
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Flight Header
                    VStack(spacing: 12) {
                        Text(flight.flightNumber)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text(flight.airline)
                            .font(AppTypography.body)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        Text(flight.status.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(statusColor(for: flight.status))
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)
                    
                    // Route Details
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            // Departure
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DEPARTURE")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                
                                Text(flight.departure.code)
                                    .font(AppTypography.title)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                Text(flight.departure.airport)
                                    .font(AppTypography.flightTime)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .lineLimit(2)
                                
                                if !flight.departure.time.isEmpty {
                                    Text(flight.departure.time)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(themeManager.currentTheme.colors.primary)
                                }
                                
                                if let gate = flight.departure.gate, !gate.isEmpty {
                                    Text("Gate \(gate)")
                                        .font(AppTypography.flightStatus)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                            }
                            
                            Spacer()
                            
                            // Flight Icon
                            Image(systemName: "airplane")
                                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                                .rotationEffect(.degrees(45))
                            
                            Spacer()
                            
                            // Arrival
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("ARRIVAL")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                
                                Text(flight.arrival.code)
                                    .font(AppTypography.title)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                
                                Text(flight.arrival.airport)
                                    .font(AppTypography.flightTime)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                
                                if !flight.arrival.time.isEmpty {
                                    Text(flight.arrival.time)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(themeManager.currentTheme.colors.primary)
                                }
                                
                                if let gate = flight.arrival.gate, !gate.isEmpty {
                                    Text("Gate \(gate)")
                                        .font(AppTypography.flightStatus)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                            }
                        }
                        .padding(20)
                        .background(themeManager.currentTheme.colors.surface)
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                        
                        // Aircraft Info
                        if let aircraft = flight.aircraft, let type = aircraft.type, !type.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AIRCRAFT")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                
                                HStack {
                                    Text(type)
                                        .font(AppTypography.body)
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    
                                    Spacer()
                                    
                                    if let registration = aircraft.registration, !registration.isEmpty {
                                        Text(registration)
                                            .font(AppTypography.flightTime)
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    }
                                }
                            }
                            .padding(20)
                            .background(themeManager.currentTheme.colors.surface)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }
                        
                        // Flight Date
                        if let flightDate = flight.flightDate, !flightDate.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FLIGHT DATE")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                
                                Text(flightDate)
                                    .font(AppTypography.headline)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                            .padding(20)
                            .background(themeManager.currentTheme.colors.surface)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(themeManager.currentTheme.colors.background)
            .navigationTitle("Flight Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
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

// MARK: - Boarding Pass Confirmation View

struct BoardingPassConfirmationView: View {
    @State var boardingPassData: BoardingPassData
    let onConfirm: (BoardingPassData) -> Void
    let onCancel: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("Confirm Flight Details")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Review the scanned information:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Simple form
                Form {
                    Section("Flight Information") {
                        TextField("Flight Number", text: Binding(
                            get: { boardingPassData.flightNumber ?? "" },
                            set: { boardingPassData.flightNumber = $0.isEmpty ? nil : $0 }
                        ))
                        
                        TextField("From (Airport Code)", text: Binding(
                            get: { boardingPassData.departureCode ?? "" },
                            set: { boardingPassData.departureCode = $0.isEmpty ? nil : $0.uppercased() }
                        ))
                        
                        TextField("To (Airport Code)", text: Binding(
                            get: { boardingPassData.arrivalCode ?? "" },
                            set: { boardingPassData.arrivalCode = $0.isEmpty ? nil : $0.uppercased() }
                        ))
                        
                        TextField("Departure Time", text: Binding(
                            get: { boardingPassData.departureTime ?? "" },
                            set: { boardingPassData.departureTime = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    
                    Section("Optional Details") {
                        TextField("Gate", text: Binding(
                            get: { boardingPassData.gate ?? "" },
                            set: { boardingPassData.gate = $0.isEmpty ? nil : $0 }
                        ))
                        
                        TextField("Seat", text: Binding(
                            get: { boardingPassData.seat ?? "" },
                            set: { boardingPassData.seat = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }
                
                // Buttons
                VStack(spacing: 12) {
                    Button("Save Flight") {
                        print("💾 Saving flight with data:", boardingPassData.summary)
                        onConfirm(boardingPassData)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!boardingPassData.isValid)
                    
                    Button("Cancel") {
                        print("❌ Canceling boarding pass confirmation")
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Boarding Pass")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("📋 Boarding pass confirmation view appeared")
                print("📋 Data summary:", boardingPassData.summary)
            }
        }
    }
}

// MARK: - Profile Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text(title)
                    .font(AppTypography.flightStatus)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.flightTime)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                Text(value)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
}