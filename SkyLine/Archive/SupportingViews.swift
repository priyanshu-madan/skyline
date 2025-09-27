//
//  SupportingViews.swift
//  SkyLine
//
//  Supporting UI components used across the app
//

import SwiftUI

// MARK: - App Design System Constants

struct AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

struct AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 999
}

// AppTypography moved to Models/Theme.swift for consistency

// MARK: - Toast Notification

struct ToastView: View {
    let message: String
    let type: ToastType
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(AppTypography.bodyBold)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundColor(theme.currentTheme.colors.text)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(theme.currentTheme.colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(borderColor, lineWidth: 2)
        )
        .cornerRadius(AppRadius.md)
        .shadow(
            color: theme.currentTheme.colors.shadow.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )
        .padding(.horizontal, AppSpacing.md)
    }
    
    private var iconName: String {
        switch type {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .success: return theme.currentTheme.colors.success
        case .error: return theme.currentTheme.colors.error
        case .info: return theme.currentTheme.colors.primary
        }
    }
    
    private var borderColor: Color {
        switch type {
        case .success: return theme.currentTheme.colors.success.opacity(0.3)
        case .error: return theme.currentTheme.colors.error.opacity(0.3)
        case .info: return theme.currentTheme.colors.primary.opacity(0.3)
        }
    }
}

// MARK: - Filter Chip

struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    let theme: ThemeManager
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(AppTypography.captionBold)
                .foregroundColor(isSelected ? .white : theme.currentTheme.colors.primary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(isSelected ? theme.currentTheme.colors.primary : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.full)
                        .stroke(theme.currentTheme.colors.primary, lineWidth: 1)
                )
                .cornerRadius(AppRadius.full)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Skeleton Loading Card

struct SkeletonCardView: View {
    let theme: ThemeManager
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main section skeleton
            HStack(spacing: 16) {
                // Left section
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 24)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 80, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 50, height: 16)
                }
                
                Spacer()
                
                // Center section
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 14)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 100, height: 8)
                }
                
                Spacer()
                
                // Right section
                VStack(alignment: .trailing, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 24)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 80, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 50, height: 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(theme.currentTheme.colors.surface)
            
            // Bottom section skeleton
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 80, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 60, height: 10)
                }
                
                Spacer()
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
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var skeletonColor: Color {
        let baseColor = theme.currentTheme.colors.textSecondary.opacity(0.3)
        return isAnimating ? baseColor.opacity(0.6) : baseColor.opacity(0.3)
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    let status: FlightStatus
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(status.displayName)
                .font(AppTypography.captionBold)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(statusColor.opacity(0.15))
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

// MARK: - Empty State View

struct EmptyStateView: View {
    let emoji: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let theme: ThemeManager
    let onAction: (() -> Void)?
    
    init(
        emoji: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        theme: ThemeManager,
        onAction: (() -> Void)? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.theme = theme
        self.onAction = onAction
    }
    
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text(emoji)
                .font(.system(size: 64))
            
            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let onAction = onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(theme.currentTheme.colors.primary)
                        .cornerRadius(AppRadius.md)
                }
            }
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - Theme Toggle Button

struct ThemeToggleButton: View {
    let theme: ThemeManager
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: theme.currentTheme == .light ? "moon.fill" : "sun.max.fill")
                    .font(AppTypography.bodyBold)
                
                Text(theme.currentTheme == .light ? "Dark" : "Light")
                    .font(AppTypography.captionBold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(theme.currentTheme.colors.primary)
            .cornerRadius(AppRadius.full)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let title: String?
    let theme: ThemeManager
    let onTap: () -> Void
    
    init(
        icon: String,
        title: String? = nil,
        theme: ThemeManager,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.theme = theme
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(AppTypography.flightNumber)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(theme.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(
                        color: theme.currentTheme.colors.shadow.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                if let title = title {
                    Text(title)
                        .font(AppTypography.footnote)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    let themeManager = ThemeManager()
    
    ScrollView {
        VStack(spacing: 20) {
            ToastView(message: "Flight saved successfully!", type: .success, theme: themeManager)
            
            HStack {
                FilterChipView(title: "All", isSelected: true, theme: themeManager) {}
                FilterChipView(title: "United", isSelected: false, theme: themeManager) {}
            }
            
            SkeletonCardView(theme: themeManager)
            
            StatusBadgeView(status: .inAir, theme: themeManager)
            
            EmptyStateView(
                emoji: "✈️",
                title: "No flights found",
                subtitle: "Try a different search term",
                actionTitle: "Search Again",
                theme: themeManager
            ) {}
            
            ThemeToggleButton(theme: themeManager) {}
            
            ControlButton(icon: "plus", title: "Add", theme: themeManager) {}
        }
        .padding()
    }
    .background(themeManager.currentTheme.colors.background)
    .environmentObject(themeManager)
}