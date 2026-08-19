//
//  TripPlaceDetectionView.swift
//  SkyLine
//
//  The on-ramp to the core loop: a finished trip goes in, a deck of places to
//  swipe a verdict onto comes out.
//
//  TWO RULES THIS SCREEN LIVES BY:
//
//  1. NARRATE, DON'T SPIN. Clustering a camera roll takes real seconds — reverse
//     geocoding alone is one network round trip per cluster. A bare spinner for
//     that long reads as a hang, so the three real phases published by
//     `PhotoPlaceDetectionService` are shown as they happen, with the photo count
//     the user can verify against their own library.
//
//  2. NO OUTCOME IS A FAILURE. `detectPlaces` never reports "nothing found": it
//     walks a fallback ladder and reports which rung it landed on via
//     `PlaceDetectionSource`. Photos with no GPS still produce a usable deck —
//     one grouped by time, where the user supplies the location. So the source is
//     rendered as a different explanation and a different call to action, never
//     as an error. The only genuinely empty case (no photos AND no coordinate for
//     the destination) hands off to manual entry, which counts exactly the same.
//

import SwiftUI
import Photos

// MARK: - Handoff

/// The pushed value. Wrapped rather than pushing `[DetectedPlace]` directly so an
/// empty deck — the manual-entry path — is still a distinct navigation value.
private struct PlaceReviewHandoff: Identifiable, Hashable {
    let id = UUID()
    let places: [DetectedPlace]
}

// MARK: - Detection Steps

/// The phases worth narrating. `requestingAccess` is deliberately not a step: it
/// is instantaneous once permission is resolved, and a checklist row that is
/// already ticked before the screen draws is noise.
private enum DetectionStep: Int, CaseIterable, Identifiable {
    case fetching
    case grouping
    case naming

    var id: Int { rawValue }
}

private enum DetectionStepStatus {
    case pending
    case active
    case done
}

// MARK: - View

struct TripPlaceDetectionView: View {
    let trip: Trip

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var detection = PhotoPlaceDetectionService.shared
    @StateObject private var authorization = PhotoLibraryAuthorizationService.shared

    @State private var isDetecting = false
    @State private var outcome: PlaceDetectionResult?
    @State private var failure: PhotoPlaceDetectionError?
    @State private var handoff: PlaceReviewHandoff?
    @State private var photoCount: Int?
    @State private var detectionTask: Task<Void, Never>?
    @State private var hasBegun = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()

                content
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        stopDetection()
                        dismiss()
                    } label: {
                        Text("Close").appFont(.bodySmall)
                    }
                }
            }
            .navigationDestination(item: $handoff) { handoff in
                PlaceReviewView(trip: trip, detectedPlaces: handoff.places)
            }
        }
        .task { await begin() }
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            failureView(failure)
        } else if let outcome {
            outcomeView(outcome)
        } else if isDetecting {
            detectingView
        } else {
            PhotoAccessGateView(
                destination: trip.destination,
                dateRangeText: trip.dateRangeText,
                onProceed: { startDetection() },
                onCancel: { dismiss() }
            )
        }
    }

    // MARK: - Header

    private var tripHeader: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.xs) {
            Text(headerTitle)
                .appFont(.title)
                .foregroundStyle(theme.colors.text)
                .multilineTextAlignment(.center)

            Text(trip.dateRangeText)
                .appFont(.placeMeta)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var headerTitle: String {
        trip.destination.isEmpty ? trip.title : trip.destination
    }

    // MARK: - Detecting

    private var detectingView: some View {
        let theme = themeManager.currentTheme

        return PhotoGateCenteredScroll {
            VStack(spacing: AppSpacing.lg) {
                tripHeader

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(narratedSteps, id: \.step) { narrated in
                        DetectionStepRow(
                            title: narrated.title,
                            status: status(of: narrated.step)
                        )
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(AppSpacing.md)
                .skylineGlassCard(theme: theme)

                progressBar

                PhotoGateActionStack(
                    actions: [
                        PhotoGateAction(title: "Stop", emphasis: .quiet) { stopDetection() }
                    ]
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xl)
        }
    }

    /// With photos off there is no library pass and no clustering — the service
    /// goes straight to suggesting POIs around the destination. Narrating three
    /// photo steps that never run would be a lie, so that path gets one honest
    /// line instead.
    private var narratedSteps: [(step: DetectionStep, title: String)] {
        if authorization.access == .denied {
            return [(.grouping, "Looking for well-known places \(destinationPhrase)")]
        }
        return DetectionStep.allCases.map { ($0, title(for: $0)) }
    }

    /// The one number that makes this screen believable. It is counted with the
    /// same padded window `PhotoAssetFetcher` uses, so "looking through 340
    /// photos" matches what actually gets read rather than being a guess.
    private func title(for step: DetectionStep) -> String {
        switch step {
        case .fetching:
            if let photoCount {
                return photoCount == 1
                    ? "Looking through 1 photo"
                    : "Looking through \(photoCount) photos"
            }
            return "Looking through your photos"
        case .grouping:
            return "Grouping them into places"
        case .naming:
            return "Naming them"
        }
    }

    private func status(of step: DetectionStep) -> DetectionStepStatus {
        if authorization.access == .denied {
            return detection.phase == .finished ? .done : .active
        }
        switch detection.phase {
        case .idle, .requestingAccess:
            return .pending
        case .fetchingPhotos:
            return step == .fetching ? .active : .pending
        case .clustering:
            if step == .fetching { return .done }
            return step == .grouping ? .active : .pending
        case .namingPlaces:
            return step == .naming ? .active : .done
        case .finished:
            return .done
        }
    }

    private var progressBar: some View {
        let theme = themeManager.currentTheme
        let value = min(max(detection.progress, 0), 1)
        let percent = Int((value * 100).rounded())

        return VStack(spacing: AppSpacing.xs) {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(theme.colors.primary)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: detection.progress)

            HStack(spacing: AppSpacing.sm) {
                Text(phaseCaption)
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer(minLength: AppSpacing.sm)

                Text("\(percent)%")
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(phaseCaption))
        .accessibilityValue(Text("\(percent) percent"))
    }

    private var phaseCaption: String {
        switch detection.phase {
        case .idle:             return "Getting ready"
        case .requestingAccess: return "Checking photo access"
        case .fetchingPhotos:   return "Reading dates and locations"
        case .clustering:       return "Working out where you stopped"
        case .namingPlaces:     return "Looking up names"
        case .finished:         return "Done"
        }
    }

    // MARK: - Outcome

    private func outcomeView(_ result: PlaceDetectionResult) -> some View {
        let copy = outcomeCopy(result)
        let previews = previewIdentifiers(result)

        return PhotoGateCenteredScroll {
            VStack(spacing: AppSpacing.md) {
                tripHeader
                    .padding(.top, AppSpacing.lg)

                if !previews.isEmpty {
                    photoStrip(previews)
                }

                PhotoGateNoticeView(
                    systemImage: copy.systemImage,
                    title: copy.title,
                    message: copy.message,
                    footnote: copy.footnote,
                    accent: copy.accent,
                    actions: outcomeActions(result)
                )
            }
        }
    }

    private struct OutcomeCopy {
        let systemImage: String
        let title: String
        let message: String
        var footnote: String? = nil
        var accent: Color? = nil
    }

    private func outcomeCopy(_ result: PlaceDetectionResult) -> OutcomeCopy {
        let theme = themeManager.currentTheme
        let count = result.places.count
        let diagnostics = result.diagnostics
        let place = destinationPhrase

        guard count > 0 else {
            return emptyOutcomeCopy(diagnostics)
        }

        switch result.source {
        case .photoGPS, .manual:
            return OutcomeCopy(
                systemImage: "mappin.and.ellipse",
                title: count == 1 ? "1 place from this trip" : "\(count) places from this trip",
                message: "These are the spots your photos say you actually spent time at. Give each one a verdict — worth it, fine, or skip. Skip is the one nothing else records.",
                footnote: diagnostics.userFacingExplanation,
                accent: theme.colors.primary
            )

        case .photoTimeOnly:
            // NOT a degraded result — a different question. The photos still
            // carry when and what it looked like, so the deck asks the user to
            // recognise a place rather than recall one.
            return OutcomeCopy(
                systemImage: "clock.badge.questionmark",
                title: count == 1 ? "1 stop, waiting on a place" : "\(count) stops, waiting on a place",
                message: "Your camera did not save where these photos were taken, so SkyLine grouped them by time instead. Each card shows a photo and when you took it — say where it was, then give it a verdict.",
                footnote: [
                    diagnostics.userFacingExplanation,
                    "Settings › Privacy & Security › Location Services › Camera saves locations on future trips."
                ].compactMap { $0 }.joined(separator: " "),
                accent: theme.colors.warning
            )

        case .destinationSuggestion:
            let lead = authorization.access == .denied
                ? "Photos are off, so nothing was read from your library."
                : "SkyLine could not find places in your photos for these dates."
            return OutcomeCopy(
                systemImage: "sparkles",
                title: count == 1 ? "1 place to check" : "\(count) places to check",
                message: "\(lead) These are well-known spots \(place) — mark the ones you actually went to, and skip the rest.",
                footnote: diagnostics.userFacingExplanation,
                accent: theme.colors.info
            )
        }
    }

    private func emptyOutcomeCopy(_ diagnostics: PlaceDetectionDiagnostics) -> OutcomeCopy {
        let theme = themeManager.currentTheme
        let tail = "You can still add the places you remember — a place you typed counts exactly the same as one SkyLine found."

        let message: String
        if authorization.access == .denied {
            message = "Photos are off, and SkyLine has no coordinates for this trip to suggest from. \(tail)"
        } else if diagnostics.assetsInDateRange == 0 {
            message = "There are no photos on this iPhone taken \(trip.dateRangeText). \(tail)"
        } else {
            let seen = diagnostics.assetsInDateRange
            message = "SkyLine could not work out where your \(seen) photos from these dates were taken, and it has no coordinates for this trip to suggest from. \(tail)"
        }

        return OutcomeCopy(
            systemImage: "mappin.slash",
            title: "Nothing to go on yet",
            message: message,
            accent: theme.colors.textSecondary
        )
    }

    private func outcomeActions(_ result: PlaceDetectionResult) -> [PhotoGateAction] {
        var actions: [PhotoGateAction] = []
        let count = result.places.count

        if count > 0 {
            actions.append(
                PhotoGateAction(title: reviewActionTitle(result), emphasis: .primary) {
                    push(result.places)
                }
            )
        } else {
            actions.append(
                PhotoGateAction(title: "Add places by hand", emphasis: .primary) {
                    push([])
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

        actions.append(
            PhotoGateAction(title: "Look again", emphasis: .quiet) {
                startDetection()
            }
        )
        return actions
    }

    private func reviewActionTitle(_ result: PlaceDetectionResult) -> String {
        let count = result.places.count
        switch result.source {
        case .photoGPS, .manual:
            return count == 1 ? "Review 1 place" : "Review \(count) places"
        case .photoTimeOnly:
            return count == 1 ? "Place this stop" : "Place these \(count) stops"
        case .destinationSuggestion:
            return "Show me"
        }
    }

    /// Up to five hero shots, so "13 places" is something the user can recognise
    /// rather than a number they have to trust.
    private func previewIdentifiers(_ result: PlaceDetectionResult) -> [String] {
        Array(result.places.compactMap(\.representativeAssetIdentifier).prefix(5))
    }

    private func photoStrip(_ identifiers: [String]) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(identifiers, id: \.self) { identifier in
                PHAssetImageView(localIdentifier: identifier, size: .thumbnail, contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityHidden(true)
    }

    private var destinationPhrase: String {
        trip.destination.isEmpty ? "near where you stayed" : "around \(trip.destination)"
    }

    // MARK: - Failure

    /// Every case of `PhotoPlaceDetectionError`, each with something to actually
    /// do next. None of them is the end of the trip.
    @ViewBuilder
    private func failureView(_ error: PhotoPlaceDetectionError) -> some View {
        let theme = themeManager.currentTheme

        switch error {
        case .accessDenied:
            PhotoGateNoticeView(
                systemImage: "photo.badge.exclamationmark",
                title: "Photos are off",
                message: "SkyLine builds this deck from where your photos were taken, and it cannot read your library. Turn photos on in Settings, or let it suggest well-known spots \(destinationPhrase) instead.",
                footnote: error.errorDescription,
                accent: theme.colors.verdictSkip,
                actions: [
                    PhotoGateAction(title: "Open Settings", emphasis: .primary) {
                        authorization.openSettings()
                    },
                    PhotoGateAction(title: "Suggest places instead", emphasis: .secondary) {
                        startDetection()
                    },
                    PhotoGateAction(title: "Not now", emphasis: .quiet) { dismiss() }
                ]
            )

        case .accessNotDetermined:
            PhotoGateNoticeView(
                systemImage: "photo.on.rectangle.angled",
                title: "SkyLine has not asked yet",
                message: "Nothing has been read from your library. Choose what SkyLine can see and it will find the places from this trip.",
                accent: theme.colors.primary,
                actions: [
                    PhotoGateAction(title: "Choose what SkyLine can see", emphasis: .primary) {
                        // Back to the gate, which shows the primer before the
                        // one system prompt this install ever gets.
                        failure = nil
                    },
                    PhotoGateAction(title: "Not now", emphasis: .quiet) { dismiss() }
                ]
            )

        case .cancelled:
            PhotoGateNoticeView(
                systemImage: "stop.circle",
                title: "Stopped",
                message: "Detection stopped before it finished, so no places were worked out. Nothing was changed and nothing was saved — starting again picks up from scratch.",
                accent: theme.colors.textSecondary,
                actions: [
                    PhotoGateAction(title: "Start again", emphasis: .primary) { startDetection() },
                    PhotoGateAction(title: "Back", emphasis: .quiet) { dismiss() }
                ]
            )
        }
    }

    // MARK: - Flow

    private func begin() async {
        guard !hasBegun else { return }
        hasBegun = true
        authorization.refresh()

        // Full access has nothing left to decide — go straight to work.
        // Limited, denied and notDetermined each have something worth saying
        // first, so they fall through to the gate.
        if authorization.access == .full {
            startDetection()
        }
    }

    private func startDetection() {
        guard !isDetecting else { return }
        detectionTask?.cancel()
        failure = nil
        outcome = nil
        isDetecting = true

        loadPhotoCount()

        detectionTask = Task {
            let result = await detection.detectPlaces(for: trip)
            // `detectPlaces` only samples `Task.isCancelled` at two points, so a
            // stop that lands after the last check still returns `.success`.
            // `stopDetection` owns the UI state in that case; overwriting it here
            // would flash a deck the user just asked to stop building.
            guard !Task.isCancelled else { return }
            isDetecting = false

            switch result {
            case .success(let value):
                outcome = value
                if shouldPushImmediately(value) {
                    push(value.places)
                }
            case .failure(let error):
                failure = error
            }
        }
    }

    private func stopDetection() {
        guard isDetecting else { return }
        detectionTask?.cancel()
        detectionTask = nil
        isDetecting = false
        failure = .cancelled
    }

    /// A clean GPS run with nothing to explain goes straight to the deck — the
    /// swipe is the payoff and an interstitial "we found places!" screen would
    /// only be a tap in the way. Every other outcome earns its explanation,
    /// including a good run on a limited library where the count is a floor
    /// rather than the truth.
    private func shouldPushImmediately(_ result: PlaceDetectionResult) -> Bool {
        guard !result.places.isEmpty else { return false }
        guard result.source == .photoGPS || result.source == .manual else { return false }
        return result.diagnostics.userFacingExplanation == nil
    }

    private func push(_ places: [DetectedPlace]) {
        handoff = PlaceReviewHandoff(places: places)
    }

    // MARK: - Photo Count

    /// Counts the assets the fetcher will see, using its own padded window so the
    /// narrated number and the read number are the same number. Cheap enough to
    /// run beside detection (`PHFetchResult` counts without materialising assets)
    /// and entirely best-effort: a nil count just narrates "your photos".
    private func loadPhotoCount() {
        guard authorization.access == .full || authorization.access == .limited else {
            photoCount = nil
            return
        }

        let configuration = PhotoAssetFetcher.Configuration.default
        let windowStart = trip.startDate.addingTimeInterval(-configuration.paddingBefore)
        let windowEnd = trip.endDate.addingTimeInterval(configuration.paddingAfter)

        Task {
            let count = await Task.detached(priority: .userInitiated) { () -> Int in
                let options = PHFetchOptions()
                options.predicate = NSPredicate(
                    format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                    PHAssetMediaType.image.rawValue,
                    windowStart as NSDate,
                    windowEnd as NSDate
                )
                options.includeHiddenAssets = false
                options.includeAllBurstAssets = false
                options.includeAssetSourceTypes = [.typeUserLibrary]
                options.wantsIncrementalChangeDetails = false
                return PHAsset.fetchAssets(with: options).count
            }.value

            photoCount = count
        }
    }
}

// MARK: - Step Row

private struct DetectionStepRow: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let status: DetectionStepStatus

    @ScaledMetric(relativeTo: .body) private var well: CGFloat = 24

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(alignment: .center, spacing: AppSpacing.sm) {
            ZStack {
                switch status {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTypography.mono(.footnote, weight: .semibold))
                        .foregroundStyle(theme.colors.verdictWorthIt)
                case .active:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(theme.colors.primary)
                case .pending:
                    Image(systemName: "circle.dotted")
                        .font(AppTypography.mono(.footnote, weight: .regular))
                        .foregroundStyle(theme.colors.textSecondary.opacity(0.6))
                }
            }
            .frame(width: well, height: well)

            Text(title)
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(status == .pending ? theme.colors.textSecondary : theme.colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityStatus))
    }

    private var accessibilityStatus: String {
        switch status {
        case .done:    return "done"
        case .active:  return "in progress"
        case .pending: return "waiting"
        }
    }
}

// MARK: - Previews

#Preview("Detection") {
    TripPlaceDetectionView(
        trip: Trip(
            title: "Lisbon",
            destination: "Lisbon",
            startDate: Date().addingTimeInterval(-14 * 86_400),
            endDate: Date().addingTimeInterval(-7 * 86_400)
        )
    )
    .environmentObject(ThemeManager())
}
