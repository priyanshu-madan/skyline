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
//  Design notes:
//    • Rows are glass, not opaque `surface`. On this palette `surface` sits
//      within ~2% luminance of `background` in BOTH themes, so an opaque fill
//      cannot make a row read as a card — it just paints the page a second
//      time. Glass shifts relative to whatever is behind it, which is the only
//      treatment that produces a card in light and dark alike.
//    • Every row carries a leading verdict rail. A column of rails is the
//      fastest way to read a list as a column of judgements rather than a list
//      of names, and it survives greyscale because the trailing glyph differs
//      per verdict too.
//

import SwiftUI

struct TripPlacesSection: View {
    let trip: Trip
    var onFindPlaces: () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var placeStore: PlaceStore

    @ScaledMetric(relativeTo: .body) private var promptGlyph: CGFloat = AppTypography.Metrics.title

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
        Group {
            if summaries.isEmpty {
                prompt
            } else {
                logged
            }
        }
        // Glass, `.buttonStyle(.glass)` and every system-drawn control resolve
        // their appearance from the environment colour scheme, NOT from
        // `themeManager`. Publishing the app's theme here is what keeps a glass
        // card from rendering dark inside a light page when the device
        // appearance disagrees with the theme the user picked.
        .environment(\.colorScheme, themeManager.currentTheme.colorScheme)
    }

    // MARK: - Prompt

    /// Shown before any place has been logged. This is the discoverability
    /// path for the core loop - the menu item alone is too well hidden to be
    /// the only way in.
    private var prompt: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(AppTypography.mono(.title, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.primary)
                .frame(height: promptGlyph)

            Text("Log the places from this trip")
                .appFont(.bodyBold)
                .foregroundStyle(theme.colors.text)
                .multilineTextAlignment(.center)

            Text("SkyLine can group your photos from these dates into the spots you actually stopped at, then ask one question about each.")
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onFindPlaces) {
                Label("Find Places from Photos", systemImage: "sparkles")
                    .appFont(.bodyBold)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            // `.glassProminent` derives its own label colour from the tint, so
            // the "white on primary" contrast failure (2.6:1 in dark theme)
            // never arises here.
            .tint(theme.colors.primary)
            .padding(.top, AppSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .skylineGlassCard(theme: theme)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Logged

    private var logged: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("Places")
                    .appFont(.headline, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: AppSpacing.sm)

                Button(action: onFindPlaces) {
                    Label("Find more", systemImage: "sparkles")
                        .appFont(.verdictLabel)
                        .padding(.horizontal, AppSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }

            verdictTally(theme: theme)

            VStack(spacing: AppSpacing.sm) {
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
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.lg)
    }

    /// The trip's verdict split, in one line. Colour is doing real work here —
    /// this is the only place on the trip screen where a saturated hue means
    /// something — so it is always paired with the verdict's own silhouette.
    @ViewBuilder
    private func verdictTally(theme: AppTheme) -> some View {
        let present = Verdict.allCases.filter { (counts[$0] ?? 0) > 0 }

        if !present.isEmpty {
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(present) { verdict in
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: verdict.systemImage)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(verdict.color(for: theme))
                            Text("\(counts[verdict] ?? 0)")
                                .foregroundStyle(theme.colors.text)
                            Text(verdict.shortName)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        .appFont(.verdictLabel)
                        .padding(.horizontal, AppSpacing.sm + 2)
                        .padding(.vertical, AppSpacing.xs + 1)
                        .skylineGlassCapsule(
                            tint: verdict.color(for: theme).opacity(0.24),
                            theme: theme
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(counts[verdict] ?? 0) \(verdict.displayName)")
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, AppSpacing.xs)
        }
    }
}

// MARK: - Row

private struct TripPlaceRow: View {
    let summary: PlaceSummary
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(spacing: AppSpacing.md - 4) {
            // The shared rail, not a local capsule: the leading spine has to be
            // the same object here, on the place log and on the visit list, or
            // the ribbon breaks the moment the user moves between screens.
            VerdictRail(verdict: summary.verdict)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(summary.place.name)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .appFont(.placeMeta, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: AppSpacing.sm)

            VerdictPip(verdict: summary.verdict)
        }
        .padding(.vertical, AppSpacing.sm + 2)
        .padding(.horizontal, AppSpacing.md - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One elevation signal. Glass draws its own edge and its own shadow, so
        // there is no stroke and no `.shadow` here — and under Reduce
        // Transparency `skylineGlass` swaps in an opaque fill plus a hairline,
        // which is why the row never disappears.
        .skylineGlassCard(cornerRadius: AppRadius.lg, theme: theme)
    }

    private var subtitle: String {
        var parts: [String] = []
        if summary.visitCount > 1 { parts.append(summary.visitCountText) }
        if let city = summary.place.city, !city.isEmpty { parts.append(city) }
        if parts.isEmpty { parts.append(summary.lastVisitText) }
        return parts.joined(separator: " · ")
    }
}
