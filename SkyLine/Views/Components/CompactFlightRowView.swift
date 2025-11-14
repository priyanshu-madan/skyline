//
//  CompactFlightRowView.swift
//  SkyLine
//
//  Compact flight row view for bottom sheet display
//

import SwiftUI

struct CompactFlightRowView: View {
    let flight: Flight
    let onTap: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @State private var showingDeleteAlert = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Flight info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(flight.flightNumber)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    if let airline = flight.airline {
                        Text("•")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        Text(airline)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text(flight.status.displayName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                        .textCase(.uppercase)
                }
                
                HStack(spacing: 8) {
                    // Route
                    Text("\(flight.departure.code) → \(flight.arrival.code)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Spacer()
                    
                    // Time info
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(flight.departure.displayTime)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        if let date = flight.flightDate {
                            Text(formatFlightDate(date))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                    }
                }
                
                // Progress bar (if in progress)
                if let progress = flight.progress, progress > 0 && progress < 1.0 {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                            .frame(height: 4)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding(.top, 4)
                }
                
                // Delay indicator (if any)
                if flight.departure.hasDelay || flight.arrival.hasDelay {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.error)
                        
                        Text("Delayed")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.error)
                        
                        if flight.departure.hasDelay {
                            Text(flight.departure.delayText)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.error)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            
            // Actions
            VStack(spacing: 8) {
                Button(action: onTap) {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .frame(width: 32, height: 32)
                        .background(themeManager.currentTheme.colors.primary.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.error)
                        .frame(width: 32, height: 32)
                        .background(themeManager.currentTheme.colors.error.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .alert("Delete Flight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await flightStore.removeFlightSync(flight.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this flight from your saved flights?")
        }
    }
    
    private var statusColor: Color {
        switch flight.status {
        case .boarding: return themeManager.currentTheme.colors.statusBoarding
        case .departed: return themeManager.currentTheme.colors.statusDeparted
        case .inAir: return themeManager.currentTheme.colors.statusInAir
        case .landed: return themeManager.currentTheme.colors.statusLanded
        case .delayed: return themeManager.currentTheme.colors.statusDelayed
        case .cancelled: return themeManager.currentTheme.colors.statusCancelled
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

#Preview("Compact Flight Rows") {
    VStack(spacing: 12) {
        CompactFlightRowView(flight: .sample) {
            print("Flight tapped")
        }
        
        CompactFlightRowView(flight: .sampleInAir) {
            print("Flight tapped")
        }
        
        CompactFlightRowView(flight: .sampleFigmaDesign) {
            print("Flight tapped")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .environmentObject(ThemeManager())
    .environmentObject(FlightStore())
}