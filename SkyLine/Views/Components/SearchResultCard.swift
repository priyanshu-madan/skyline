//
//  SearchResultCard.swift
//  SkyLine
//
//  Search result card component for flight search results
//

import SwiftUI

struct SearchResultCard: View {
    let flight: Flight
    let onSave: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @State private var isPressed = false
    
    var isAlreadySaved: Bool {
        flightStore.isFlightSaved(flight.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            VStack(spacing: 16) {
                // Header with flight number and status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.flightNumber)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        if let airline = flight.airline {
                            Text(airline)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    StatusBadgeView(status: flight.status, theme: themeManager)
                }
                
                // Route information
                HStack {
                    // Departure
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.departure.code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text(flight.departure.city)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.departure.displayTime)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    
                    // Flight path icon
                    VStack {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(themeManager.currentTheme.colors.primary)
                                .frame(width: 20, height: 2)
                            
                            Text("✈️")
                                .font(.system(size: 16))
                                .padding(.horizontal, 8)
                            
                            Rectangle()
                                .fill(themeManager.currentTheme.colors.primary)
                                .frame(width: 20, height: 2)
                        }
                        
                        if let progress = flight.progress, progress > 0 {
                            Text("\(Int(progress * 100))% complete")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Arrival
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(flight.arrival.code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text(flight.arrival.city)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(flight.arrival.displayTime)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                // Additional flight info (if available)
                if let aircraft = flight.aircraft, let type = aircraft.type, !type.isEmpty {
                    HStack {
                        Text("Aircraft: \(type)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        Spacer()
                        
                        if let date = flight.flightDate {
                            Text(formatFlightDate(date))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                    }
                    .padding(.top, 8)
                    .overlay(
                        Rectangle()
                            .fill(themeManager.currentTheme.colors.border)
                            .frame(height: 1),
                        alignment: .top
                    )
                }
                
                // Terminal and Gate info (if available)
                if let terminal = flight.departure.terminal, 
                   let gate = flight.departure.gate,
                   !terminal.isEmpty || !gate.isEmpty {
                    HStack {
                        if !terminal.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Terminal")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                Text(terminal)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                        }
                        
                        if !gate.isEmpty {
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Gate")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                Text(gate)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .overlay(
                        Rectangle()
                            .fill(themeManager.currentTheme.colors.border)
                            .frame(height: 1),
                        alignment: .top
                    )
                }
            }
            .padding(16)
            
            // Save button
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onSave()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isAlreadySaved ? "checkmark.circle.fill" : "bookmark")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    
                    Text(isAlreadySaved ? "SAVED" : "SAVE FLIGHT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isAlreadySaved ? 
                    themeManager.currentTheme.colors.success : 
                    themeManager.currentTheme.colors.primary
                )
                .cornerRadius(0) // Sharp corners for the bottom section
            }
            .disabled(isAlreadySaved)
        }
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .shadow(
            color: themeManager.currentTheme == .light ? .black.opacity(0.1) : .clear,
            radius: 2,
            x: 0,
            y: 1
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            // Optional: Handle tap on card itself (e.g., show details)
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            // Haptic feedback for press
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private func formatFlightDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview("Search Result Cards") {
    VStack(spacing: 16) {
        SearchResultCard(flight: .sample) {
            print("Save flight")
        }
        
        SearchResultCard(flight: .sampleInAir) {
            print("Save flight")
        }
        
        SearchResultCard(flight: .sampleFigmaDesign) {
            print("Save flight")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .environmentObject(ThemeManager())
    .environmentObject(FlightStore())
}