//
//  AskAIPlannerView.swift
//  SkyLine
//
//  AI-powered trip planning with user preferences
//

import SwiftUI

struct AskAIPlannerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @StateObject private var aiService = AIItineraryService.shared
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let onActivity: (ItineraryItem) -> Void

    // Preference States
    @State private var selectedBudget: ItineraryPreferences.BudgetLevel = .mid
    @State private var selectedStyle: ItineraryPreferences.TravelStyle = .cultural
    @State private var selectedInterests: Set<ItineraryPreferences.TravelInterest> = []
    @State private var selectedPace: ItineraryPreferences.TravelPace = .moderate
    @State private var specialRequests: String = ""


    var body: some View {
        NavigationView {
            ZStack {
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Trip Context Header
                        tripContextHeader

                        // Budget Section
                        budgetSection

                        // Travel Style Section
                        travelStyleSection

                        // Interests Section
                        interestsSection

                        // Pace Section
                        paceSection

                        // Special Requests Section
                        specialRequestsSection

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // Bottom Generate Button
                VStack {
                    Spacer()
                    generateButton
                }
            }
            .navigationTitle("Ask AI to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Trip Context Header

    private var tripContextHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 24))
                    .foregroundColor(themeManager.currentTheme.colors.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)

                    HStack(spacing: 8) {
                        Text(trip.dateRangeText)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text("•")
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text(trip.durationText)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BUDGET")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

            Picker("Budget", selection: $selectedBudget) {
                ForEach(ItineraryPreferences.BudgetLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Travel Style Section

    private var travelStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAVEL STYLE")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ItineraryPreferences.TravelStyle.allCases, id: \.self) { style in
                    Button {
                        selectedStyle = style
                    } label: {
                        HStack {
                            Image(systemName: selectedStyle == style ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(
                                    selectedStyle == style
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.textSecondary
                                )

                            Text(style.displayName)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    selectedStyle == style
                                    ? themeManager.currentTheme.colors.primary.opacity(0.1)
                                    : themeManager.currentTheme.colors.surface.opacity(0.6)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedStyle == style
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.border.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Interests Section

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTERESTS (Select multiple)")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ItineraryPreferences.TravelInterest.allCases, id: \.self) { interest in
                    Button {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedInterests.contains(interest) ? "checkmark.square.fill" : "square")
                                .foregroundColor(
                                    selectedInterests.contains(interest)
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.textSecondary
                                )

                            Text(interest.displayName)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    selectedInterests.contains(interest)
                                    ? themeManager.currentTheme.colors.primary.opacity(0.1)
                                    : themeManager.currentTheme.colors.surface.opacity(0.6)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedInterests.contains(interest)
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.border.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Pace Section

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PACE")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

            HStack(spacing: 12) {
                ForEach(ItineraryPreferences.TravelPace.allCases, id: \.self) { pace in
                    Button {
                        selectedPace = pace
                    } label: {
                        HStack {
                            Image(systemName: selectedPace == pace ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(
                                    selectedPace == pace
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.textSecondary
                                )

                            Text(pace.displayName)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    selectedPace == pace
                                    ? themeManager.currentTheme.colors.primary.opacity(0.1)
                                    : themeManager.currentTheme.colors.surface.opacity(0.6)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedPace == pace
                                    ? themeManager.currentTheme.colors.primary
                                    : themeManager.currentTheme.colors.border.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Special Requests Section

    private var specialRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPECIAL REQUESTS (Optional)")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

            TextField("e.g., Include vegetarian restaurants, avoid crowds, must-see landmarks", text: $specialRequests, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .foregroundColor(themeManager.currentTheme.colors.text)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                )
                .lineLimit(3...6)
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(12)

                Button {
                    generateItinerary()
                } label: {
                    HStack {
                        Text("Generate Itinerary")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(themeManager.currentTheme.colors.background)
    }

    // MARK: - Generate Itinerary

    private func generateItinerary() {
        // Build preferences
        let preferences = ItineraryPreferences(
            budget: selectedBudget,
            travelStyle: selectedStyle,
            interests: Array(selectedInterests),
            pace: selectedPace,
            specialRequests: specialRequests
        )

        // Calculate trip duration in days
        let duration = Int(trip.duration / 86400) // Convert seconds to days

        // Dismiss immediately - user doesn't need to wait here
        dismiss()

        // Start streaming generation in background
        Task {
            let result = await aiService.generateCustomItineraryStreaming(
                destination: trip.destination,
                duration: duration,
                startDate: trip.startDate,
                endDate: trip.endDate,
                preferences: preferences,
                onActivity: { activity in
                    // Call callback for each activity as it arrives
                    self.onActivity(activity)
                }
            )

            await MainActor.run {
                switch result {
                case .success:
                    print("✅ Streaming generation complete")

                case .failure(let error):
                    print("❌ AI generation failed: \(error.localizedDescription)")
                    // TODO: Show error on trip page instead
                }
            }
        }
    }
}

#Preview {
    AskAIPlannerView(
        trip: Trip(
            title: "Paris Adventure",
            destination: "Paris, France",
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        ),
        onActivity: { _ in }
    )
    .environmentObject(ThemeManager())
    .environmentObject(TripStore.shared)
}
