//
//  SupportingViews.swift
//  SkyLine
//
//  Supporting UI components used across the app
//

import SwiftUI

// MARK: - Skeleton Loading Card
struct SkeletonCardView: View {
    let theme: ThemeManager
    @State private var animationOffset: CGFloat = -1
    
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Header skeleton
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 80, height: 16)
                    
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 120, height: 12)
                }
                
                Spacer()
                
                RoundedRectangle(cornerRadius: AppRadius.full)
                    .fill(skeletonColor)
                    .frame(width: 60, height: 20)
            }
            
            // Route skeleton
            HStack {
                VStack(spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 32)
                }
                
                Spacer()
                
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .fill(skeletonColor)
                    .frame(width: 40, height: 16)
                
                Spacer()
                
                VStack(spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 32)
                }
            }
            
            // Details skeleton
            HStack {
                VStack(spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 50, height: 12)
                    
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 40, height: 14)
                }
                
                Spacer()
                
                VStack(spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 50, height: 12)
                    
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 40, height: 14)
                }
                
                Spacer()
                
                VStack(spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 30, height: 12)
                    
                    RoundedRectangle(cornerRadius: AppRadius.xs)
                        .fill(skeletonColor)
                        .frame(width: 20, height: 14)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
        .shadow(color: AppShadow.sm.color, radius: AppShadow.sm.radius, x: AppShadow.sm.x, y: AppShadow.sm.y)
        .overlay(
            // Shimmer effect
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: animationOffset * UIScreen.main.bounds.width)
                .mask(RoundedRectangle(cornerRadius: AppRadius.lg))
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                animationOffset = 1
            }
        }
    }
    
    private var skeletonColor: Color {
        theme.currentTheme.colors.border.opacity(0.3)
    }
}

// MARK: - Filter Chip View
struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    let theme: ThemeManager
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(AppTypography.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : theme.currentTheme.colors.text)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    isSelected ? theme.currentTheme.colors.primary : theme.currentTheme.colors.background
                )
                .cornerRadius(AppRadius.full)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.full)
                        .stroke(theme.currentTheme.colors.border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Toast Types
enum ToastType {
    case success
    case error
    case info
    case warning
}

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let type: ToastType
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .foregroundColor(.white)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundColor(.white)
                .fontWeight(.semibold)
            
            Spacer()
        }
        .padding(AppSpacing.md)
        .background(backgroundColor)
        .cornerRadius(AppRadius.md)
        .shadow(color: AppShadow.lg.color, radius: AppShadow.lg.radius, x: AppShadow.lg.x, y: AppShadow.lg.y)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
    }
    
    private var backgroundColor: Color {
        switch type {
        case .success: return theme.currentTheme.colors.success
        case .error: return theme.currentTheme.colors.error
        case .info: return theme.currentTheme.colors.primary
        case .warning: return .orange
        }
    }
    
    private var iconName: String {
        switch type {
        case .success: return "checkmark.circle"
        case .error: return "xmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Flight Detail View (Sheet)
struct FlightDetailView: View {
    let flight: Flight
    let theme: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Flight header
                    VStack(spacing: AppSpacing.sm) {
                        Text(flight.flightNumber)
                            .font(AppTypography.titleLarge)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        Text(flight.airline ?? "Unknown Airline")
                            .font(AppTypography.body)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        
                        StatusBadgeView(status: flight.status, theme: theme)
                            .scaleEffect(1.2)
                    }
                    
                    Divider()
                    
                    // Route details
                    VStack(spacing: AppSpacing.lg) {
                        // Departure
                        flightLocationSection(
                            title: "Departure",
                            airport: flight.departure
                        )
                        
                        // Flight path visualization
                        HStack {
                            Spacer()
                            Text(flight.departure.code)
                                .font(AppTypography.headline)
                                .foregroundColor(theme.currentTheme.colors.text)
                            
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(theme.currentTheme.colors.primary)
                                    .frame(height: 2)
                                
                                Text("✈️")
                                    .font(.system(.title2, design: .monospaced))
                                    .padding(.horizontal, AppSpacing.sm)
                                
                                Rectangle()
                                    .fill(theme.currentTheme.colors.primary)
                                    .frame(height: 2)
                            }
                            .frame(maxWidth: 120)
                            
                            Text(flight.arrival.code)
                                .font(AppTypography.headline)
                                .foregroundColor(theme.currentTheme.colors.text)
                            Spacer()
                        }
                        
                        // Arrival
                        flightLocationSection(
                            title: "Arrival",
                            airport: flight.arrival
                        )
                    }
                    
                    // Current position if available
                    if let position = flight.currentPosition {
                        Divider()
                        
                        currentPositionSection(position)
                    }
                    
                    // Aircraft details if available
                    if let aircraft = flight.aircraft {
                        Divider()
                        
                        aircraftSection(aircraft)
                    }
                    
                    Spacer()
                }
                .padding(AppSpacing.lg)
            }
            .background(theme.currentTheme.colors.background)
            .navigationTitle("Flight Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(theme.currentTheme.colors.primary)
                }
            }
        }
    }
    
    private func flightLocationSection(title: String, airport: Airport) -> some View {
        VStack(spacing: AppSpacing.md) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.sm) {
                Text(airport.code)
                    .font(.system(.largeTitle, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                Text(airport.airport)
                    .font(AppTypography.body)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                
                Text(airport.displayTime)
                    .font(AppTypography.headline)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                if let terminal = airport.terminal {
                    Text("Terminal \(terminal)")
                        .font(AppTypography.caption)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
                
                if let gate = airport.gate {
                    Text("Gate \(gate)")
                        .font(AppTypography.caption)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
                
                if airport.hasDelay {
                    Text("Delayed \(airport.delayText)")
                        .font(AppTypography.captionBold)
                        .foregroundColor(theme.currentTheme.colors.error)
                }
            }
            .padding(AppSpacing.md)
            .background(theme.currentTheme.colors.surface)
            .cornerRadius(AppRadius.md)
        }
    }
    
    private func currentPositionSection(_ position: FlightPosition) -> some View {
        VStack(spacing: AppSpacing.md) {
            Text("Current Position")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.sm) {
                HStack {
                    Text("Altitude:")
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                    Spacer()
                    Text(position.altitudeInFeet)
                        .foregroundColor(theme.currentTheme.colors.text)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Speed:")
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                    Spacer()
                    Text(position.speedInKnots)
                        .foregroundColor(theme.currentTheme.colors.text)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Coordinates:")
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                    Spacer()
                    Text("\(position.latitude, specifier: "%.4f"), \(position.longitude, specifier: "%.4f")")
                        .foregroundColor(theme.currentTheme.colors.text)
                        .fontWeight(.semibold)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(AppSpacing.md)
            .background(theme.currentTheme.colors.surface)
            .cornerRadius(AppRadius.md)
        }
    }
    
    private func aircraftSection(_ aircraft: Aircraft) -> some View {
        VStack(spacing: AppSpacing.md) {
            Text("Aircraft")
                .font(AppTypography.headline)
                .foregroundColor(theme.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.sm) {
                if let type = aircraft.type {
                    HStack {
                        Text("Type:")
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        Spacer()
                        Text(type)
                            .foregroundColor(theme.currentTheme.colors.text)
                            .fontWeight(.semibold)
                    }
                }
                
                if let registration = aircraft.registration {
                    HStack {
                        Text("Registration:")
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        Spacer()
                        Text(registration)
                            .foregroundColor(theme.currentTheme.colors.text)
                            .fontWeight(.semibold)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                if let icao24 = aircraft.icao24 {
                    HStack {
                        Text("ICAO24:")
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                        Spacer()
                        Text(icao24)
                            .foregroundColor(theme.currentTheme.colors.text)
                            .fontWeight(.semibold)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(theme.currentTheme.colors.surface)
            .cornerRadius(AppRadius.md)
        }
    }
}

#Preview("Skeleton Card") {
    VStack {
        SkeletonCardView(theme: ThemeManager())
        SkeletonCardView(theme: ThemeManager())
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Filter Chips") {
    VStack {
        HStack {
            FilterChipView(title: "All", isSelected: true, theme: ThemeManager()) { }
            FilterChipView(title: "United", isSelected: false, theme: ThemeManager()) { }
            FilterChipView(title: "American", isSelected: false, theme: ThemeManager()) { }
        }
        
        HStack {
            FilterChipView(title: "Time", isSelected: true, theme: ThemeManager()) { }
            FilterChipView(title: "Airline", isSelected: false, theme: ThemeManager()) { }
            FilterChipView(title: "Status", isSelected: false, theme: ThemeManager()) { }
        }
    }
    .padding()
}

// MARK: - Compact Flight Row View
struct CompactFlightRowView: View {
    let flight: Flight
    let onTap: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Route
                HStack(spacing: 8) {
                    Text(flight.departure.code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.arrival.code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                
                Spacer()
                
                // Flight Number
                Text(flight.flightNumber)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                
                // Status
                Text(flight.status.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: flight.status))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(themeManager.currentTheme.colors.background)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
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

#Preview("Toast") {
    VStack {
        ToastView(message: "Flight saved successfully!", type: .success, theme: ThemeManager())
        ToastView(message: "Search failed", type: .error, theme: ThemeManager())
        ToastView(message: "Processing photo...", type: .info, theme: ThemeManager())
    }
}