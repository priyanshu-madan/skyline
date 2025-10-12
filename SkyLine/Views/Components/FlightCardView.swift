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
    
    @State private var isPressed = false
    @State private var showingFullDetails = false
    
    init(
        flight: Flight,
        showSaveButton: Bool = true,
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
        VStack(spacing: 0) {
            // Main card content
            cardContent
            
            // Action buttons
            if showSaveButton || showDeleteButton {
                actionButtons
            }
        }
        .background(theme.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
        .shadow(color: AppShadow.md.color, radius: AppShadow.md.radius, x: AppShadow.md.x, y: AppShadow.md.y)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .sheet(isPresented: $showingFullDetails) {
            FlightDetailView(flight: flight, theme: theme)
        }
    }
    
    private var cardContent: some View {
        VStack(spacing: AppSpacing.md) {
            // Header with flight number and status
            headerSection
            
            // Route section (boarding pass style)
            routeSection
            
            // Flight details section
            detailsSection
            
            // Aircraft info if available
            if let aircraft = flight.aircraft {
                aircraftSection(aircraft)
            }
        }
        .padding(AppSpacing.md)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                Text(flight.flightNumber)
                    .font(AppTypography.headline)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                Text(flight.airline ?? "Unknown Airline")
                    .font(AppTypography.caption)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
            
            Spacer()
            
            StatusBadgeView(status: flight.status, theme: theme)
        }
    }
    
    private var routeSection: some View {
        VStack(spacing: AppSpacing.md) {
            routeAirportsView
        }
    }
    
    private var routeAirportsView: some View {
        HStack {
            departureAirportView
            flightPathView
            arrivalAirportView
        }
        .padding(AppSpacing.md)
        .background(theme.currentTheme.colors.background)
        .cornerRadius(AppRadius.md)
    }
    
    private var departureAirportView: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(flight.departure.airport)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            Text(flight.departure.code)
                .font(.custom("GeistMono-Bold", size: 32))
                .foregroundColor(theme.currentTheme.colors.text)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var flightPathView: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.currentTheme.colors.primary)
                    .frame(height: 2)
                
                Text("✈️")
                    .font(AppTypography.body)
                    .padding(.horizontal, AppSpacing.xs)
                
                Rectangle()
                    .fill(theme.currentTheme.colors.primary)
                    .frame(height: 2)
            }
        }
        .frame(width: 60)
    }
    
    private var arrivalAirportView: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(flight.arrival.airport)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            Text(flight.arrival.code)
                .font(.custom("GeistMono-Bold", size: 32))
                .foregroundColor(theme.currentTheme.colors.text)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var detailsSection: some View {
        HStack {
            departureDetailsView
            Spacer()
            arrivalDetailsView
            Spacer()
            gateTerminalInfoView
        }
        .padding(.top, AppSpacing.sm)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.colors.border)
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private var departureDetailsView: some View {
        VStack(alignment: .center, spacing: AppSpacing.xs / 2) {
            Text("DEPARTS")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .fontWeight(.medium)
            
            Text(flight.departure.displayTime)
                .font(AppTypography.bodyBold)
                .foregroundColor(theme.currentTheme.colors.text)
            
            if let date = flight.flightDate {
                Text(formatFlightDate(date))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
            
            if flight.departure.hasDelay {
                Text(flight.departure.delayText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(theme.currentTheme.colors.error)
                    .fontWeight(.semibold)
            }
        }
    }
    
    private var arrivalDetailsView: some View {
        VStack(alignment: .center, spacing: AppSpacing.xs / 2) {
            Text("ARRIVES")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .fontWeight(.medium)
            
            Text(flight.arrival.displayTime)
                .font(AppTypography.bodyBold)
                .foregroundColor(theme.currentTheme.colors.text)
            
            if let date = flight.flightDate {
                Text(formatFlightDate(date))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
        }
    }
    
    private var gateTerminalInfoView: some View {
        HStack {
            if let gate = flight.departure.gate {
                VStack(alignment: .center, spacing: AppSpacing.xs / 2) {
                    Text("GATE")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .fontWeight(.medium)
                    
                    Text(gate)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(theme.currentTheme.colors.text)
                }
            }
            
            if let terminal = flight.departure.terminal {
                if flight.departure.gate != nil {
                    Spacer()
                }
                
                VStack(alignment: .center, spacing: AppSpacing.xs / 2) {
                    Text("TERMINAL")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                        .fontWeight(.medium)
                    
                    Text(terminal)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(theme.currentTheme.colors.text)
                }
            }
        }
    }
    
    private func aircraftSection(_ aircraft: Aircraft) -> some View {
        VStack(spacing: AppSpacing.xs / 2) {
            Text(aircraft.displayName)
                .font(AppTypography.caption)
                .foregroundColor(theme.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }
    
    private var actionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            if showSaveButton, let onSave = onSave {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onSave()
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "bookmark")
                        Text("SAVE FLIGHT")
                            .fontWeight(.semibold)
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(theme.currentTheme.colors.primary)
                    .cornerRadius(AppRadius.sm)
                }
            }
            
            if showDeleteButton, let onDelete = onDelete {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onDelete()
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "trash")
                        Text("DELETE")
                            .fontWeight(.semibold)
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(theme.currentTheme.colors.error)
                    .cornerRadius(AppRadius.sm)
                }
            }
        }
        .padding([.horizontal, .bottom], AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .background(
            Rectangle()
                .fill(theme.currentTheme.colors.border)
                .frame(height: 1),
            alignment: .top
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
}

// MARK: - Status Badge View
struct StatusBadgeView: View {
    let status: FlightStatus
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: AppSpacing.xs / 2) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(status.displayName)
                .font(AppTypography.captionBold)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(theme.currentTheme.colors.background)
        .cornerRadius(AppRadius.full)
    }
    
    private var statusColor: Color {
        switch status {
        case .boarding: return theme.currentTheme.colors.statusBoarding
        case .departed: return theme.currentTheme.colors.statusDeparted
        case .inAir: return theme.currentTheme.colors.statusInAir
        case .landed: return theme.currentTheme.colors.statusLanded
        case .delayed: return theme.currentTheme.colors.statusDelayed
        case .cancelled: return theme.currentTheme.colors.statusCancelled
        }
    }
}

#Preview("Flight Card - Boarding") {
    VStack(spacing: AppSpacing.md) {
        FlightCardView(
            flight: .sample,
            showSaveButton: true,
            showDeleteButton: false,
            theme: ThemeManager()
        ) {
            print("Flight tapped")
        } onSave: {
            print("Save tapped")
        }
        
        FlightCardView(
            flight: .sampleInAir,
            showSaveButton: false,
            showDeleteButton: true,
            theme: ThemeManager()
        ) {
            print("Flight tapped")
        } onDelete: {
            print("Delete tapped")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}