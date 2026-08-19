//
//  TripPlacesSection.swift
//  SkyLine
//
//  The places logged for one trip, shown on that trip's own screen.
//
//  Without this the app told the user nothing after they finished the verdict
//  deck: they would log thirteen places for a trip and the trip screen would
//  still read "Start Your Timeline", because places live in the Place/Visit
//  model and the trip timeline renders TripEntry rows.
//

import SwiftUI

struct TripPlacesSection: View {
    let trip: Trip
    var onFindPlaces: () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var placeStore: PlaceStore

    private var summaries: [PlaceSummary] {
        placeStore.places(forTrip: trip.id)
            .sorted { lhs, rhs in
                // Recommendable first, then most recent - the order someone
                // would want if they were about to tell a friend about it.
                if lhs.verdict?.sortRank != rhs.verdict?.sortRank {
                    return (lhs.verdict?.sortRank ?? Int.max) < (rhs.verdict?.sortRank ?? Int.max)
                }
                return (lhs.lastVisitDate ?? .distantPast) > (rhs.lastVisitDate ?? .distantPast)
            }
    }

    private var counts: [Verdict: Int] {
        summaries.reduce(into: [:]) { totals, summary in
            guard let verdict = summary.verdict else { return }
            totals[verdict, default: 0] += 1
        }
    }

    var body: some View {
        if summaries.isEmpty {
            prompt
        } else {
            logged
        }
    }

    // MARK: - Prompt

    /// Shown before any place has been logged. This is the discoverability
    /// path for the core loop - the menu item alone is too well hidden to be
    /// the only way in.
    private var prompt: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(themeManager.currentTheme.colors.primary)

            Text("Log the places from this trip")
                .appFont(.bodyBold)
                .foregroundStyle(themeManager.currentTheme.colors.text)

            Text("SkyLine can group your photos from these dates into the spots you actually stopped at, then ask one question about each.")
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onFindPlaces) {
                Label("Find Places from Photos", systemImage: "sparkles")
                    .appFont(.bodyBold)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .padding(.top, AppSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(
            ConcentricRectangle(corners: .concentric)
                .fill(themeManager.currentTheme.colors.surface)
        )
        .containerShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Logged

    private var logged: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Places")
                    .appFont(.headline)
                    .foregroundStyle(themeManager.currentTheme.colors.text)

                Spacer()

                Button(action: onFindPlaces) {
                    Label("Find more", systemImage: "sparkles")
                        .appFont(.caption)
                }
                .buttonStyle(.glass)
            }

            HStack(spacing: AppSpacing.md) {
                ForEach(Verdict.allCases) { verdict in
                    if let count = counts[verdict], count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: verdict.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(count)")
                                .appFont(.caption)
                        }
                        .foregroundStyle(verdict.color(for: themeManager.currentTheme))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(count) \(verdict.displayName)")
                    }
                }
                Spacer()
            }
            .padding(.bottom, AppSpacing.xs)

            ForEach(summaries) { summary in
                NavigationLink {
                    PlaceDetailView(place: summary.place)
                        .environmentObject(themeManager)
                        .environmentObject(placeStore)
                } label: {
                    TripPlaceRow(summary: summary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

// MARK: - Row

private struct TripPlaceRow: View {
    let summary: PlaceSummary
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.place.name)
                    .appFont(.bodyBold)
                    .foregroundStyle(themeManager.currentTheme.colors.text)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
            }

            Spacer(minLength: AppSpacing.sm)

            if let verdict = summary.verdict {
                Image(systemName: verdict.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(verdict.color(for: themeManager.currentTheme))
                    .accessibilityLabel(verdict.accessibilityLabel)
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
                    .accessibilityLabel("Not rated yet")
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(
            ConcentricRectangle(corners: .concentric)
                .fill(themeManager.currentTheme.colors.surface)
        )
        .containerShape(RoundedRectangle(cornerRadius: 16))
    }

    private var subtitle: String {
        var parts: [String] = []
        if summary.visitCount > 1 { parts.append(summary.visitCountText) }
        if let city = summary.place.city, !city.isEmpty { parts.append(city) }
        if parts.isEmpty { parts.append(summary.lastVisitText) }
        return parts.joined(separator: " · ")
    }
}
