//
//  ProfileView.swift
//  SkyLine
//
//  User profile and app settings screen
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var showingClearDataAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Profile header
                        profileHeader
                        
                        // Flight statistics
                        flightStatsSection
                        
                        // Settings sections
                        appearanceSection
                        
                        dataSection
                        
                        aboutSection
                        
                        Spacer(minLength: AppSpacing.xxl)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAbout) {
                AboutView(theme: themeManager)
            }
            .alert("Clear All Data", isPresented: $showingClearDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will remove all saved flights and search history. This action cannot be undone.")
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: AppSpacing.md) {
            // App icon/logo
            ZStack {
                Circle()
                    .fill(themeManager.currentTheme.colors.primary)
                    .frame(width: 80, height: 80)
                
                Text("✈️")
                    .font(AppTypography.titleLarge)
            }
            
            VStack(spacing: AppSpacing.xs) {
                Text("Skyline")
                    .font(AppTypography.titleLarge)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Flight Tracking Made Simple")
                    .font(AppTypography.body)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.md)
    }
    
    private var flightStatsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Your Flight Activity")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            HStack(spacing: AppSpacing.md) {
                StatCardView(
                    title: "Saved Flights",
                    value: "\(flightStore.flightCount)",
                    icon: "airplane",
                    theme: themeManager
                )
                
                StatCardView(
                    title: "Active Flights",
                    value: "\(flightStore.activeFlights.count)",
                    icon: "airplane.circle",
                    theme: themeManager
                )
            }
            
            HStack(spacing: AppSpacing.md) {
                StatCardView(
                    title: "Searches",
                    value: "\(flightStore.searchHistory.count)",
                    icon: "magnifyingglass",
                    theme: themeManager
                )
                
                StatCardView(
                    title: "Upcoming",
                    value: "\(flightStore.upcomingFlights.count)",
                    icon: "clock",
                    theme: themeManager
                )
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Appearance")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.xs) {
                SettingsRowView(
                    icon: "paintbrush",
                    title: "Theme",
                    subtitle: themeManager.currentTheme.displayName,
                    theme: themeManager
                ) {
                    themeManager.toggleTheme()
                }
                
                SettingsRowView(
                    icon: "textformat",
                    title: "Typography",
                    subtitle: "Monospace Font",
                    theme: themeManager
                ) {
                    // Typography settings would go here
                }
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Data & Storage")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.xs) {
                SettingsRowView(
                    icon: "arrow.clockwise",
                    title: "Refresh Flight Data",
                    subtitle: "Update all saved flights",
                    theme: themeManager
                ) {
                    Task {
                        await flightStore.refreshFlightData()
                    }
                }
                
                SettingsRowView(
                    icon: "trash",
                    title: "Clear Search History",
                    subtitle: "\(flightStore.searchHistory.count) searches",
                    theme: themeManager
                ) {
                    flightStore.clearSearchHistory()
                }
                
                SettingsRowView(
                    icon: "exclamationmark.triangle",
                    title: "Clear All Data",
                    subtitle: "Remove all flights and data",
                    theme: themeManager,
                    isDestructive: true
                ) {
                    showingClearDataAlert = true
                }
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("About")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            VStack(spacing: AppSpacing.xs) {
                SettingsRowView(
                    icon: "info.circle",
                    title: "About Skyline",
                    subtitle: "Version 1.0.0",
                    theme: themeManager
                ) {
                    showingAbout = true
                }
                
                SettingsRowView(
                    icon: "heart",
                    title: "Support Development",
                    subtitle: "Rate & Review",
                    theme: themeManager
                ) {
                    openAppStore()
                }
                
                SettingsRowView(
                    icon: "envelope",
                    title: "Contact Support",
                    subtitle: "Get help with issues",
                    theme: themeManager
                ) {
                    openEmail()
                }
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.lg)
    }
    
    private func clearAllData() {
        flightStore.clearAllFlights()
        flightStore.clearSearchHistory()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    private func openAppStore() {
        // Open App Store rating page
        if let url = URL(string: "https://apps.apple.com/app/id123456789") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openEmail() {
        // Open email compose
        if let url = URL(string: "mailto:support@skylineapp.com?subject=Skyline%20Support") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Stat Card View
struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let theme: ThemeManager
    
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.currentTheme.colors.primary)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                Text(value)
                    .font(AppTypography.title)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .background(theme.currentTheme.colors.background)
        .cornerRadius(AppRadius.md)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings Row View
struct SettingsRowView: View {
    let icon: String
    let title: String
    let subtitle: String
    let theme: ThemeManager
    let isDestructive: Bool
    let action: () -> Void
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        theme: ThemeManager,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isDestructive ? theme.currentTheme.colors.error : theme.currentTheme.colors.primary)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundColor(isDestructive ? theme.currentTheme.colors.error : theme.currentTheme.colors.text)
                    
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(theme.currentTheme.colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - About View
struct AboutView: View {
    let theme: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // App info
                    VStack(spacing: AppSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(theme.currentTheme.colors.primary)
                                .frame(width: 100, height: 100)
                            
                            Text("✈️")
                                .font(AppTypography.titleLarge)
                        }
                        
                        Text("Skyline")
                            .font(AppTypography.titleLarge)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        Text("Version 1.0.0")
                            .font(AppTypography.body)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    // Description
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("About Skyline")
                            .font(AppTypography.headline)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        Text("Skyline is a modern flight tracking application that helps you monitor flights, visualize routes on a 3D globe, and manage your travel itinerary with ease.")
                            .font(AppTypography.body)
                            .foregroundColor(theme.currentTheme.colors.textSecondary)
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Features")
                            .font(AppTypography.headline)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            FeatureRowView(
                                icon: "magnifyingglass",
                                title: "Flight Search",
                                description: "Search flights by number or route",
                                theme: theme
                            )
                            
                            FeatureRowView(
                                icon: "globe",
                                title: "3D Globe Visualization",
                                description: "View live flights on an interactive globe",
                                theme: theme
                            )
                            
                            FeatureRowView(
                                icon: "camera",
                                title: "OCR Boarding Pass Import",
                                description: "Import flights from photos",
                                theme: theme
                            )
                            
                            FeatureRowView(
                                icon: "paintbrush",
                                title: "Dark & Light Themes",
                                description: "Customizable appearance",
                                theme: theme
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Credits
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Credits")
                            .font(AppTypography.headline)
                            .foregroundColor(theme.currentTheme.colors.text)
                        
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("• Flight data provided by AviationStack and OpenSky Network")
                                .font(AppTypography.caption)
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                            
                            Text("• Built with SwiftUI and MapKit")
                                .font(AppTypography.caption)
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                            
                            Text("• Icons from SF Symbols")
                                .font(AppTypography.caption)
                                .foregroundColor(theme.currentTheme.colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(AppSpacing.lg)
            }
            .background(theme.currentTheme.colors.background)
            .navigationTitle("About")
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
}

// MARK: - Feature Row View
struct FeatureRowView: View {
    let icon: String
    let title: String
    let description: String
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.currentTheme.colors.primary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                Text(title)
                    .font(AppTypography.bodyBold)
                    .foregroundColor(theme.currentTheme.colors.text)
                
                Text(description)
                    .font(AppTypography.caption)
                    .foregroundColor(theme.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
}

#Preview("About View") {
    AboutView(theme: ThemeManager())
}