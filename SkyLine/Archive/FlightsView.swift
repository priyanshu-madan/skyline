//
//  FlightsView.swift
//  SkyLine
//
//  User's saved flights screen matching React Native structure
//

import SwiftUI

struct FlightsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @State private var showingDeleteAlert = false
    @State private var flightToDelete: Flight?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()
                
                if flightStore.flights.isEmpty {
                    emptyStateView
                } else {
                    flightListView
                }
                
                // Loading overlay
                if flightStore.isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Skyline")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh Flights", systemImage: "arrow.clockwise") {
                            Task {
                                await flightStore.refreshFlightData()
                            }
                        }
                        
                        Button("Clear All", systemImage: "trash", role: .destructive) {
                            flightStore.clearAllFlights()
                        }
                        .disabled(flightStore.flights.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                    }
                }
            }
        }
        .alert("Delete Flight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let flight = flightToDelete {
                    Task {
                        await flightStore.removeFlight(flight.id)
                    }
                }
            }
        } message: {
            if let flight = flightToDelete {
                Text("Are you sure you want to remove \(flight.flightNumber) from your saved flights?")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {
                Text("✈️")
                    .font(AppTypography.titleLarge)
                
                Text("No saved flights")
                    .font(AppTypography.headline)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Search for flights and save them to see them here")
                    .font(AppTypography.body)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }
            
            VStack(spacing: AppSpacing.md) {
                Text("Getting Started")
                    .font(AppTypography.headline)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                VStack(spacing: AppSpacing.sm) {
                    TipRowView(
                        icon: "🔍",
                        text: "Search for flights by number or route",
                        theme: themeManager
                    )
                    
                    TipRowView(
                        icon: "📌",
                        text: "Save flights to track them",
                        theme: themeManager
                    )
                    
                    TipRowView(
                        icon: "🌍",
                        text: "View live flights on the globe",
                        theme: themeManager
                    )
                }
            }
            .padding(AppSpacing.md)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(AppRadius.lg)
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.xl)
    }
    
    private var flightListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Your Flights")
                    .font(AppTypography.title)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("\(flightStore.flightCount) saved flight\(flightStore.flightCount != 1 ? "s" : "")")
                    .font(AppTypography.caption)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            
            // Flight List
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(flightStore.flights) { flight in
                        FlightCardView(
                            flight: flight,
                            showSaveButton: false,
                            showDeleteButton: true,
                            theme: themeManager
                        ) {
                            // On tap - show flight details
                            flightStore.setSelectedFlight(flight)
                        } onDelete: {
                            // On delete
                            flightToDelete = flight
                            showingDeleteAlert = true
                        }
                        .transition(.slide.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
        }
    }
    
    private var loadingOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(themeManager.currentTheme.colors.primary)
                    
                    Text("Updating flights...")
                        .font(AppTypography.body)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                .padding(AppSpacing.xl)
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(AppRadius.lg)
                .shadow(color: AppShadow.lg.color, radius: AppShadow.lg.radius, x: AppShadow.lg.x, y: AppShadow.lg.y)
            )
    }
}

// MARK: - Tip Row View
struct TipRowView: View {
    let icon: String
    let text: String
    let theme: ThemeManager
    
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(icon)
                .font(.title2)
            
            Text(text)
                .font(AppTypography.body)
                .foregroundColor(theme.currentTheme.colors.textSecondary)
            
            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

#Preview("With Flights") {
    FlightsView()
        .environmentObject(ThemeManager())
        .environmentObject({
            let store = FlightStore()
            return store
        }())
}

#Preview("Empty State") {
    FlightsView()
        .environmentObject(ThemeManager())
        .environmentObject({
            let store = FlightStore()
            store.flights.removeAll()
            return store
        }())
}