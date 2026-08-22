//
//  FirstRunDetectionView.swift
//  SkyLine
//
//  The cold-start screen: SkyLine reads the whole camera roll once, works out
//  which runs of days were trips, and hands the result to the verdict deck.
//
//  THREE RULES THIS SCREEN LIVES BY:
//
//  1. HONEST NUMBERS, NOT A SPINNER. A full-library pass plus one throttled
//     geocode per place is minutes of work, not seconds. A bare spinner for that
//     long reads as a hang and gets force-quit. So the screen states the size of
//     the job in the user's own terms — "looking through 12,431 photos" — and
//     shows the count climbing against it. Every number here is one the user can
//     check against their own Photos app.
//
//  2. STOPPING IS NOT LOSING. `LibraryPlaceDetectionService` publishes places as
//     it names them, newest trip first, so the stop button says exactly what it
//     does: keep what has been found. Anyone who taps it lands on the same
//     summary with a smaller number, never on an error and never back at zero.
//
//  3. NO OUTCOME IS A FAILURE. An empty library, a library where the camera
//     never saved a location, a library with no trips in it — these are ordinary
//     states, not errors, and each gets its own explanation and its own way
//     forward. A user whose camera had location services switched off has done
//     nothing wrong, and putting a red error in front of them on their first
//     screen would be the end of the product for them.
//
//  HANDOFF: `onFinish` receives the whole `LibraryDetectionResult`. Each episode
//  converts to a `Trip`, so the existing deck takes it unchanged:
//      PlaceReviewView(trip: episode.asTrip(),
//                      detectedPlaces: result.places(in: episode))
//  A no-argument `onFinish` is also accepted, for a caller that only needs to
//  know the step is done.
//

import SwiftUI
import Photos

// MARK: - View

struct FirstRunDetectionView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var detection = LibraryPlaceDetectionService.shared
    @StateObject private var authorization = PhotoLibraryAuthorizationService.shared

    /// Called when the user is done with this screen. Always carries whatever
    /// was found — including nothing, which is still a decision the caller has
    /// to route.
    private let onFinish: (LibraryDetectionResult) -> Void
    /// Optional escape hatch shown alongside the primer. Omit to hide it.
    private let onSkip: (() -> Void)?

    /// Places already recorded, so a rescan carries verdicts forward instead of
    /// duplicating them. Default empty — the true first run.
    private let existingPlaces: [DetectedPlace]

    @State private var hasBegun = false

    // MARK: Init

    init(
        existingPlaces: [DetectedPlace] = [],
        onFinish: @escaping (LibraryDetectionResult) -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.existingPlaces = existingPlaces
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    // MARK: Body

    var body: some View {
        ZStack {
            themeManager.currentTheme.colors.background
                .ignoresSafeArea()

            content
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25),
                    value: stateKey
                )
        }
        .task { await begin() }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings, or from the limited-library picker. Without
            // this, a user who turns photos on lands back on "Photos are off".
            if phase == .active { authorization.refresh() }
        }
    }

    /// One value that changes exactly when the screen changes, so the crossfade
    /// does not re-trigger on every progress tick.
    private var stateKey: String {
        if let result = detection.lastResult { return "result-\(result.outcome.rawValue)" }
        if detection.isRunning { return "running" }
        return "gate-\(authorization.access.rawValue)"
    }

    @ViewBuilder
    private var content: some View {
        if let result = detection.lastResult {
            summary(result)
        } else if detection.isRunning {
            scanning
        } else {
            gate
        }
    }

    // MARK: - Gate

    /// The primer is written for THIS scan, not the trip one.
    ///
    /// `PhotoAccessGateView` promises "only photos taken during this trip are
    /// read", which is true there and false here — this pass reads the dates and
    /// locations of the entire library. iOS asks for photo access exactly once
    /// per install, so the sentence that precedes that prompt has to be the true
    /// one.
    @ViewBuilder
    private var gate: some View {
        switch authorization.access {
        case .notDetermined:
            primer
        case .limited:
            PhotoGateNoticeView(
                systemImage: "photo.stack",
                title: "Only some photos",
                message: "SkyLine can see just the photos you picked, so it can only find trips inside those. Choosing your whole library lets it find the rest — nothing is uploaded either way.",
                accent: themeManager.currentTheme.colors.warning,
                actions: [
                    PhotoGateAction(title: "Choose more photos", emphasis: .primary) {
                        authorization.presentLimitedPicker()
                    },
                    PhotoGateAction(title: "Look through these anyway", emphasis: .secondary) {
                        detection.start(existingPlaces: existingPlaces)
                    }
                ] + skipAction
            )
        case .denied:
            PhotoGateNoticeView(
                systemImage: "photo.badge.exclamationmark",
                title: "Photos are off",
                message: "SkyLine builds your map from where your photos were taken, and it cannot read your library. You can turn photos on in Settings, or start your log by hand — a place you type counts exactly the same as one SkyLine found.",
                accent: themeManager.currentTheme.colors.verdictSkip,
                actions: [
                    PhotoGateAction(title: "Open Settings", emphasis: .primary) {
                        authorization.openSettings()
                    },
                    PhotoGateAction(title: "Add places by hand", emphasis: .secondary) {
                        finishEmpty(.accessDenied)
                    }
                ]
            )
        case .full:
            PhotoGateNoticeView(
                systemImage: "checkmark.seal",
                title: "Photos are on",
                message: "SkyLine can read your library and find the trips already in it.",
                accent: themeManager.currentTheme.colors.verdictWorthIt,
                actions: [
                    PhotoGateAction(title: "Find my trips", emphasis: .primary) {
                        detection.start(existingPlaces: existingPlaces)
                    }
                ] + skipAction
            )
        }
    }

    private var primer: some View {
        let theme = themeManager.currentTheme

        return PhotoGateCenteredScroll {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(AppTypography.mono(.largeTitle, weight: .regular))
                    .foregroundStyle(theme.colors.primary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: glyphWell, height: glyphWell)
                    .skylineGlass(.card, in: Circle(), tint: theme.colors.primary.opacity(0.22), theme: theme)
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text("You have already been places")
                        .appFont(.headline)
                        .foregroundStyle(theme.colors.text)
                        .multilineTextAlignment(.center)

                    Text("Your camera roll knows where you went and when. SkyLine reads that once, works out which runs of days were trips, and gives you a deck to judge — worth it, fine, or skip.")
                        .appFont(.bodySmall, lineLimit: .unlimited)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    FirstRunPrimerPoint(
                        systemImage: "clock.arrow.circlepath",
                        text: "It reads the date and location of every photo on this iPhone — your whole history, not just this week."
                    )
                    FirstRunPrimerPoint(
                        systemImage: "house",
                        text: "Days near where you live are ignored. Only the days you spent somewhere else become trips."
                    )
                    FirstRunPrimerPoint(
                        systemImage: "lock.shield",
                        text: "All of it happens on this iPhone. Your photos are never uploaded."
                    )
                    FirstRunPrimerPoint(
                        systemImage: "exclamationmark.bubble",
                        text: "iOS only asks once. If you say no, you can still add places by hand — SkyLine just will not find them for you."
                    )
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(AppSpacing.md)
                .skylineGlassCard(theme: theme)

                PhotoGateActionStack(
                    actions: [
                        PhotoGateAction(title: "Look through my photos", emphasis: .primary) {
                            detection.start(existingPlaces: existingPlaces)
                        }
                    ] + skipAction
                )
                .padding(.top, AppSpacing.xs)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xl)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    private var skipAction: [PhotoGateAction] {
        guard let onSkip else { return [] }
        return [PhotoGateAction(title: "Not now", emphasis: .quiet) { onSkip() }]
    }

    // MARK: - Scanning

    private var scanning: some View {
        let theme = themeManager.currentTheme

        return PhotoGateCenteredScroll {
            VStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.xs) {
                    Text(scanHeadline)
                        .appFont(.title)
                        .foregroundStyle(theme.colors.text)
                        .multilineTextAlignment(.center)

                    Text(phaseCaption)
                        .appFont(.placeMeta)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)
                .accessibilityElement(children: .combine)

                // The live tally. This is the reason the wait is tolerable: the
                // number climbing is proof of work, and it is the same number
                // the summary will open with.
                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        FirstRunTally(
                            value: detection.tripsDetected,
                            singular: "trip",
                            plural: "trips",
                            systemImage: "suitcase"
                        )
                        FirstRunTally(
                            value: detection.places.count,
                            singular: "place",
                            plural: "places",
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                }
                .frame(maxWidth: 340)

                progressBar

                if let latest = detection.episodes.first {
                    Text("Latest: \(latest.title) · \(latest.dateRangeText)")
                        .appFont(.footnote, lineLimit: .exactly(2))
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .transition(.opacity)
                }

                PhotoGateActionStack(
                    actions: [
                        PhotoGateAction(title: stopTitle, emphasis: .quiet) {
                            detection.cancel()
                        }
                    ]
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xl)
        }
    }

    /// The size of the job, said plainly. Falls back to a shape of a sentence
    /// that is still true before the fetch has resolved a count.
    private var scanHeadline: String {
        let total = detection.photosTotal
        guard total > 0 else { return "Counting your photos" }
        return total == 1
            ? "Looking through 1 photo"
            : "Looking through \(total.formatted()) photos"
    }

    private var stopTitle: String {
        detection.places.isEmpty ? "Stop looking" : "Stop and keep these"
    }

    private var progressBar: some View {
        let theme = themeManager.currentTheme
        let value = min(max(detection.progress, 0), 1)

        return VStack(spacing: AppSpacing.xs) {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(theme.colors.primary)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: detection.progress)

            HStack(spacing: AppSpacing.sm) {
                Text(scannedCaption)
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .monospacedDigit()

                Spacer(minLength: AppSpacing.sm)

                Text("\(Int((value * 100).rounded()))%")
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(phaseCaption))
        .accessibilityValue(Text("\(Int((value * 100).rounded())) percent. \(detection.places.count) places found so far."))
    }

    private var scannedCaption: String {
        switch detection.phase {
        case .scanningLibrary:
            guard detection.photosTotal > 0 else { return "Reading your library" }
            return "\(detection.photosScanned.formatted()) of \(detection.photosTotal.formatted())"
        default:
            return "\(detection.photosLocated.formatted()) photos with a location"
        }
    }

    private var phaseCaption: String {
        switch detection.phase {
        case .idle:              return "Getting ready"
        case .requestingAccess:  return "Checking photo access"
        case .scanningLibrary:   return "Reading dates and locations"
        case .findingTrips:      return "Working out which days you were away"
        case .groupingPlaces:    return "Grouping each trip into places"
        case .namingPlaces:      return "Looking up names — this is the slow part"
        case .finished:          return "Done"
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ result: LibraryDetectionResult) -> some View {
        let copy = summaryCopy(result)
        let previews = Array(result.places.compactMap(\.representativeAssetIdentifier).prefix(5))

        PhotoGateCenteredScroll {
            VStack(spacing: AppSpacing.md) {
                if !previews.isEmpty {
                    photoStrip(previews)
                        .padding(.top, AppSpacing.lg)
                }

                PhotoGateNoticeView(
                    systemImage: copy.systemImage,
                    title: copy.title,
                    message: copy.message,
                    footnote: copy.footnote,
                    accent: copy.accent,
                    actions: summaryActions(result)
                )
            }
        }
    }

    private struct SummaryCopy {
        let systemImage: String
        let title: String
        let message: String
        var footnote: String?
        var accent: Color?
    }

    private func summaryCopy(_ result: LibraryDetectionResult) -> SummaryCopy {
        let theme = themeManager.currentTheme
        let diagnostics = result.diagnostics
        let places = result.places.count
        let trips = result.episodes.count

        switch result.outcome {
        case .places:
            let placeText = places == 1 ? "1 place" : "\(places) places"
            let tripText = trips == 1 ? "1 trip" : "\(trips) trips"
            return SummaryCopy(
                systemImage: "mappin.and.ellipse",
                title: diagnostics.wasCancelled
                    ? "\(placeText) so far"
                    : "\(placeText) across \(tripText)",
                message: diagnostics.wasCancelled
                    ? "Stopped where you asked, and nothing found so far was thrown away. These are the spots your photos say you spent time at — give each one a verdict."
                    : "These are the spots your photos say you actually spent time at, going back as far as your library does. Give each one a verdict: worth it, fine, or skip. Skip is the one nothing else records.",
                footnote: diagnostics.userFacingExplanation,
                accent: theme.colors.primary
            )

        case .noPhotos:
            return SummaryCopy(
                systemImage: "photo.on.rectangle",
                title: "No photos to read",
                message: "There are no photos in this library yet, so there is nothing for SkyLine to work from. That is fine — start your log by hand, and once you travel with this iPhone it will find the rest on its own.",
                accent: theme.colors.textSecondary
            )

        case .noLocations:
            // The single most important non-error state. A large share of
            // cameras never wrote GPS, and telling those users "we found
            // nothing" would read as SkyLine being broken rather than as their
            // camera never having saved the thing SkyLine needs.
            let seen = diagnostics.assetsWithoutLocation
            return SummaryCopy(
                systemImage: "location.slash",
                title: "Your photos have no locations",
                message: seen > 0
                    ? "SkyLine read \(seen.formatted()) photos and not one of them has a location saved — your camera was never asked to record where you were. Nothing is wrong with your library; SkyLine just cannot place these on a map."
                    : "None of the photos SkyLine can see have a location saved, so it cannot place them on a map.",
                footnote: "Settings › Privacy & Security › Location Services › Camera turns it on for future photos. In the meantime you can add the places you remember — a place you type counts exactly the same.",
                accent: theme.colors.warning
            )

        case .noTripsFound:
            return SummaryCopy(
                systemImage: "house",
                title: "Nothing that looks like a trip",
                message: "SkyLine read \(diagnostics.assetsWithLocation.formatted()) located photos and they all sit around one place — the place you live. It only turns days spent somewhere else into trips, so there is nothing to judge yet.",
                footnote: "Add the places you remember now, and the next time you travel with this iPhone SkyLine will pick the trip up by itself.",
                accent: theme.colors.textSecondary
            )

        case .noPlacesInTrips:
            let tripsSeen = diagnostics.episodesFound
            return SummaryCopy(
                systemImage: "mappin.slash",
                title: "Trips found, but nothing stood out",
                message: tripsSeen == 1
                    ? "SkyLine found one run of days away from home, but there were not enough photos in one spot to call it a place you stopped at."
                    : "SkyLine found \(tripsSeen) runs of days away from home, but none of them had enough photos in one spot to call it a place you stopped at.",
                footnote: "Add the places you remember — a place you type counts exactly the same as one SkyLine found.",
                accent: theme.colors.textSecondary
            )

        case .accessDenied:
            return SummaryCopy(
                systemImage: "photo.badge.exclamationmark",
                title: "Photos are off",
                message: "Nothing was read from your library. You can turn photos on in Settings and look again, or start your log by hand.",
                accent: theme.colors.verdictSkip
            )
        }
    }

    /// "Review 6 places in Shibuya" beats "Review 120 places" when the button
    /// only starts one trip.
    private func reviewTitle(tripTitle: String?, count: Int) -> String {
        let noun = count == 1 ? "1 place" : "\(count) places"
        guard let tripTitle, !tripTitle.isEmpty else { return "Review \(noun)" }
        return "Review \(noun) in \(tripTitle)"
    }

    private func summaryActions(_ result: LibraryDetectionResult) -> [PhotoGateAction] {
        var actions: [PhotoGateAction] = []
        let places = result.places.count

        if places > 0 {
            // Name what the button ACTUALLY does. It starts the newest trip, not
            // all of them - handing someone a 120-card deck is not a review, it
            // is a chore - but the label used to promise the full count and then
            // deliver six, which reads as the app losing the rest. The remainder
            // is kept and offered again from the place log.
            let newest = result.episodes.first { !result.places(in: $0).isEmpty }
            let firstCount = newest.map { result.places(in: $0).count } ?? places
            let remaining = places - firstCount

            actions.append(
                PhotoGateAction(
                    title: reviewTitle(tripTitle: newest?.title, count: firstCount),
                    subtitle: remaining > 0
                        ? "\(remaining) more kept for later"
                        : nil,
                    emphasis: .primary
                ) {
                    onFinish(result)
                }
            )
            if result.diagnostics.wasCancelled {
                actions.append(
                    PhotoGateAction(title: "Keep looking", emphasis: .secondary) { restart() }
                )
            }
        } else {
            // Every dead end still leaves by the same door.
            actions.append(
                PhotoGateAction(title: "Add places by hand", emphasis: .primary) {
                    onFinish(result)
                }
            )
        }

        switch authorization.access {
        case .limited:
            actions.append(
                PhotoGateAction(title: "Choose more photos", emphasis: .secondary) {
                    authorization.presentLimitedPicker()
                }
            )
        case .denied:
            actions.append(
                PhotoGateAction(title: "Turn photos on", emphasis: .secondary) {
                    authorization.openSettings()
                }
            )
        case .notDetermined, .full:
            break
        }

        if !(places > 0 && result.diagnostics.wasCancelled) {
            actions.append(
                PhotoGateAction(title: "Look again", emphasis: .quiet) { restart() }
            )
        }
        return actions
    }

    /// Up to five hero shots, so a count is something the user recognises rather
    /// than a number they have to take on trust.
    private func photoStrip(_ identifiers: [String]) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(identifiers, id: \.self) { identifier in
                PHAssetImageView(localIdentifier: identifier, size: .thumbnail, contentMode: .fill)
                    .frame(width: thumbnail, height: thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityHidden(true)
    }

    // MARK: - Metrics

    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 54

    // MARK: - Flow

    private func begin() async {
        guard !hasBegun else { return }
        hasBegun = true
        authorization.refresh()
        // Deliberately does NOT auto-start. A whole-library read is a big,
        // slow, battery-visible thing and the user should press the button that
        // starts it — even on full access, where the trip flow would just go.
    }

    private func restart() {
        detection.reset()
        detection.start(existingPlaces: existingPlaces)
    }

    /// Leaves by the same door as a successful run, with an empty result, so the
    /// caller has exactly one exit to handle.
    private func finishEmpty(_ outcome: LibraryDetectionOutcome) {
        var diagnostics = LibraryDetectionDiagnostics()
        diagnostics.isLimitedLibraryAccess = (authorization.access == .limited)
        onFinish(
            LibraryDetectionResult(
                outcome: outcome,
                episodes: [],
                places: [],
                diagnostics: diagnostics
            )
        )
    }
}

// MARK: - Tally

/// One live count. Monospaced digits so the number does not shuffle its own
/// layout every time it ticks.
private struct FirstRunTally: View {
    @EnvironmentObject var themeManager: ThemeManager

    let value: Int
    let singular: String
    let plural: String
    let systemImage: String

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(AppTypography.mono(.footnote, weight: .semibold))
                .foregroundStyle(theme.colors.primary)
                .accessibilityHidden(true)

            Text("\(value)")
                .appFont(.title)
                .foregroundStyle(theme.colors.text)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(value == 1 ? singular : plural)
                .appFont(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .skylineGlassCard(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value) \(value == 1 ? singular : plural)"))
    }
}

// MARK: - Primer Row

private struct FirstRunPrimerPoint: View {
    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    let text: String

    @ScaledMetric(relativeTo: .body) private var well: CGFloat = 24

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .font(AppTypography.mono(.footnote, weight: .semibold))
                .foregroundStyle(theme.colors.primary)
                .frame(width: well, height: well)
                .accessibilityHidden(true)

            Text(text)
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Previews

#Preview("First run") {
    FirstRunDetectionView(onFinish: { _ in })
        .environmentObject(ThemeManager())
}
