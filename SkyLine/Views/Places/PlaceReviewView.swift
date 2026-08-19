//
//  PlaceReviewView.swift
//  SkyLine
//
//  Step 3 of the loop, and the only screen where the user really *works*:
//  one detected place at a time, full bleed, until the trip is judged.
//
//  Interaction model:
//    • Three verdict chips at thumb height, equally weighted. Skip is an
//      answer, not a dismissal — it is the one thing a saved-places list can
//      never record, so it sits beside the other two, same size, same glass.
//    • The same three answers are also swipes: right = worth it, left = skip,
//      up = fine, down = decide later. The swipe is an accelerator for people
//      who have done this before; the chips are the discoverable path.
//    • Every swipe is undoable, from a persistent control in the top bar and
//      from a toast that survives four seconds after the card leaves. Losing a
//      judgement to a mis-swipe is infuriating and entirely avoidable.
//    • The name is editable in place. Reverse geocoding hands back street
//      addresses; the user is ground truth.
//

import SwiftUI

struct PlaceReviewView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel: PlaceReviewViewModel

    private let onFinish: ((PlaceReviewViewModel.Summary) -> Void)?
    private let onAddPlace: (() -> Void)?

    @Namespace private var glassNamespace

    @State private var drag: CGSize = .zero
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    @ScaledMetric(relativeTo: .body) private var cardCorner: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var controlSlot: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var summaryThumb: CGFloat = 52

    /// Distance at which the stamp starts to show.
    private let previewThreshold: CGFloat = 28
    /// Distance (projected, so a flick counts) at which the card commits.
    private let commitThreshold: CGFloat = 104

    @MainActor
    init(
        trip: Trip,
        detectedPlaces: [DetectedPlace],
        store: PlaceStore? = nil,
        onFinish: ((PlaceReviewViewModel.Summary) -> Void)? = nil,
        onAddPlace: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: PlaceReviewViewModel(trip: trip, places: detectedPlaces, store: store)
        )
        self.onFinish = onFinish
        self.onAddPlace = onAddPlace
    }

    /// Shorthand spelling of the same thing.
    @MainActor
    init(
        trip: Trip,
        places: [DetectedPlace],
        store: PlaceStore? = nil,
        onFinish: ((PlaceReviewViewModel.Summary) -> Void)? = nil,
        onAddPlace: (() -> Void)? = nil
    ) {
        self.init(
            trip: trip,
            detectedPlaces: places,
            store: store,
            onFinish: onFinish,
            onAddPlace: onAddPlace
        )
    }

    // MARK: - Body

    var body: some View {
        let theme = themeManager.currentTheme

        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Group {
                    if viewModel.isEmpty {
                        PlaceLogEmptyStateView(
                            state: .noPlacesDetected(destination: viewModel.trip.destination),
                            onPrimaryAction: onAddPlace
                        )
                        .frame(maxHeight: .infinity)
                    } else if viewModel.isFinished {
                        summaryScreen
                    } else {
                        deckScreen
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(transition, value: viewModel.isFinished)
        .animation(transition, value: viewModel.index)
        .overlay(alignment: .top) { syncNotice }
        .task { viewModel.prefetchImages() }
        .onChange(of: viewModel.index) { _, _ in
            viewModel.prefetchImages()
        }
        .onChange(of: viewModel.currentPlace?.id) { _, _ in
            // A fresh card must never inherit the previous card's edit session.
            isEditingName = false
            nameFieldFocused = false
            drag = .zero
        }
        .onChange(of: viewModel.isFinished) { _, finished in
            guard finished else { return }
            onFinish?(viewModel.summary)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            SkyLineGlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }

            Spacer(minLength: 0)

            if !viewModel.isEmpty && !viewModel.isFinished {
                // A counter, not a progress bar. It answers "how much is left?"
                // when the user looks, and says nothing when they do not.
                Text(viewModel.progressText)
                    .appFont(.verdictLabel)
                    .foregroundStyle(theme.colors.textSecondary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs + 2)
                    .skylineGlassCapsule(theme: theme)
                    .accessibilityLabel(Text("Place \(viewModel.position) of \(viewModel.total)"))
            }

            Spacer(minLength: 0)

            if viewModel.canUndo {
                SkyLineGlassIconButton(
                    systemImage: "arrow.uturn.backward",
                    accessibilityLabel: "Undo last decision"
                ) {
                    withAnimation(transition) { viewModel.undo() }
                }
            } else {
                // Holds the slot so the counter stays centred.
                Color.clear.frame(width: controlSlot, height: controlSlot)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Deck

    private var deckScreen: some View {
        VStack(spacing: AppSpacing.md) {
            cardStack
                .padding(.horizontal, AppSpacing.md)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) { undoToast }

            verdictControls
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
        }
    }

    private var cardStack: some View {
        let theme = themeManager.currentTheme
        let shape = RoundedRectangle(cornerRadius: cardCorner, style: .continuous)

        return ZStack {
            // Deck depth as a physical cue rather than a bar: you can see there
            // is more underneath.
            if viewModel.place(atQueueOffset: 2) != nil {
                shape
                    .fill(theme.colors.surface.opacity(0.45))
                    .overlay(shape.stroke(theme.colors.border, lineWidth: 0.5))
                    .scaleEffect(0.88)
                    .offset(y: 26)
                    .accessibilityHidden(true)
            }

            if let next = viewModel.place(atQueueOffset: 1) {
                cardFace(for: next, isTop: false)
                    .scaleEffect(0.94)
                    .offset(y: 13)
                    .opacity(0.65)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let current = viewModel.currentPlace {
                cardFace(for: current, isTop: true)
                    .overlay { stampOverlay }
                    .offset(drag)
                    .rotationEffect(.degrees(rotationDegrees), anchor: .bottom)
                    .gesture(dragGesture)
                    .id(current.id)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
                    .accessibilityActions { cardAccessibilityActions }
            }
        }
    }

    @ViewBuilder
    private func cardFace(for place: DetectedPlace, isTop: Bool) -> some View {
        let theme = themeManager.currentTheme
        let shape = RoundedRectangle(cornerRadius: cardCorner, style: .continuous)

        ZStack(alignment: .bottomLeading) {
            PHAssetImageView(
                localIdentifier: place.representativeAssetIdentifier,
                size: .card,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
            .overlay { legibilityGradient }

            if isTop {
                cardCaption(for: place)
            }
        }
        .padding(AppSpacing.xs)
        .skylineGlassCard(cornerRadius: cardCorner, theme: theme)
        .containerShape(shape)
    }

    /// Text over an arbitrary photo needs its own contrast floor — glass behind
    /// the photo cannot supply one.
    private var legibilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .black.opacity(0.30), location: 0.58),
                .init(color: .black.opacity(0.78), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private func cardCaption(for place: DetectedPlace) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            nameRow(for: place)

            HStack(spacing: AppSpacing.xs + 2) {
                Text(viewModel.subtitle(for: place))
                if let dwell = viewModel.dwellText(for: place) {
                    Text("·")
                    Text(dwell)
                }
            }
            .appFont(.placeMeta)
            .foregroundStyle(.white.opacity(0.88))

            if !viewModel.canBePinned(place) {
                Label("No location yet", systemImage: "mappin.slash")
                    .appFont(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(AppSpacing.md)
    }

    // MARK: - Inline Rename

    @ViewBuilder
    private func nameRow(for place: DetectedPlace) -> some View {
        let theme = themeManager.currentTheme

        if isEditingName {
            HStack(spacing: AppSpacing.sm) {
                TextField("Name this place", text: $draftName)
                    .appFont(.placeName, lineLimit: .exactly(1))
                    .foregroundStyle(.white)
                    .tint(theme.colors.primary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit { commitName(for: place) }

                Button {
                    commitName(for: place)
                } label: {
                    Text("Save")
                        .appFont(.verdictLabel)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        } else {
            Button {
                draftName = place.name
                isEditingName = true
                nameFieldFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(place.name)
                        .appFont(.placeName)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Image(systemName: "pencil.line")
                        .appFont(.placeMeta)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(place.name))
            .accessibilityHint(Text("Rename this place"))
        }
    }

    private func commitName(for place: DetectedPlace) {
        viewModel.rename(draftName, forPlaceWithId: place.id)
        isEditingName = false
        nameFieldFocused = false
    }

    // MARK: - Verdict Controls

    private var verdictControls: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Verdict.allCases) { verdict in
                        VerdictChip(
                            verdict: verdict,
                            isSelected: false,
                            showsLabel: true,
                            namespace: glassNamespace
                        ) {
                            commit(.verdict(verdict), from: .zero, animated: false)
                        }
                    }
                }
            }

            Button {
                commit(.later, from: .zero, animated: false)
            } label: {
                Label("Decide later", systemImage: "clock.arrow.circlepath")
                    .appFont(.bodySmall)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs + 2)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityHint(Text("Keeps this place unrated so you can come back to it"))

            if showsSwipeHint {
                Text("Or swipe: right worth it, left skip, up fine, down later")
                    .appFont(.footnote, lineLimit: .exactly(2))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The hint teaches once and then gets out of the way.
    private var showsSwipeHint: Bool {
        viewModel.index == 0 && !viewModel.canUndo
    }

    private var cardAccessibilityActions: some View {
        Group {
            ForEach(Verdict.allCases) { verdict in
                Button(verdict.displayName) {
                    commit(.verdict(verdict), from: .zero, animated: false)
                }
            }
            Button("Decide later") {
                commit(.later, from: .zero, animated: false)
            }
            if viewModel.canUndo {
                Button("Undo last decision") {
                    withAnimation(transition) { viewModel.undo() }
                }
            }
        }
    }

    // MARK: - Undo Toast

    @ViewBuilder
    private var undoToast: some View {
        let theme = themeManager.currentTheme

        if let step = viewModel.lastStep {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: step.decision.systemImage)
                    .foregroundStyle(step.decision.verdict?.color(for: theme) ?? theme.colors.textSecondary)
                    .symbolRenderingMode(.hierarchical)

                Text(step.decision.confirmationText)
                    .foregroundStyle(theme.colors.text)

                Button {
                    withAnimation(transition) { viewModel.undo() }
                } label: {
                    Text("Undo")
                        .foregroundStyle(theme.colors.primary)
                }
                .buttonStyle(.plain)
            }
            .appFont(.verdictLabel)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .skylineGlassCapsule(theme: theme)
            .padding(.bottom, AppSpacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: step.id) {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(transition) { viewModel.clearLastStep() }
                }
            }
        }
    }

    // MARK: - Sync Notice

    @ViewBuilder
    private var syncNotice: some View {
        let theme = themeManager.currentTheme

        if let message = viewModel.errorMessage {
            // Deliberately not an alert. The verdict is already saved locally;
            // interrupting a deck for a sync hiccup would cost more than it
            // explains.
            Button {
                viewModel.errorMessage = nil
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(theme.colors.warning)
                    Text(message)
                        .foregroundStyle(theme.colors.text)
                        .lineLimit(2)
                }
                .appFont(.footnote)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.plain)
            .skylineGlassCapsule(tint: theme.colors.warning.opacity(0.25), theme: theme)
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, controlSlot + AppSpacing.lg)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Summary

    private var summaryScreen: some View {
        let theme = themeManager.currentTheme
        let summary = viewModel.summary

        return ScrollView {
            VStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.xs) {
                    Text(summary.decidedCount > 0 ? "Logged" : "Nothing judged yet")
                        .appFont(.title)
                        .foregroundStyle(theme.colors.text)

                    Text("\(viewModel.trip.destination) · \(viewModel.trip.dateRangeText)")
                        .appFont(.placeMeta)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Verdict.allCases) { verdict in
                            countTile(verdict: verdict, count: summary.count(for: verdict))
                        }
                    }
                }

                if summary.laterCount > 0 {
                    laterCallout(count: summary.laterCount)
                }

                if summary.needsLocationCount > 0 {
                    Text("\(summary.needsLocationCount) of these still need a location before they can go on the map.")
                        .appFont(.footnote, lineLimit: .exactly(3))
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if !summary.highlights.isEmpty {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(Array(summary.highlights.prefix(8))) { highlight in
                            summaryRow(highlight)
                        }

                        if summary.highlights.count > 8 {
                            Text("and \(summary.highlights.count - 8) more")
                                .appFont(.footnote)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }

                Button {
                    onFinish?(summary)
                    dismiss()
                } label: {
                    Text("Done")
                        .appFont(.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.colors.primary)
                .frame(maxWidth: 320)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func countTile(verdict: Verdict, count: Int) -> some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.xs) {
            Text("\(count)")
                .appFont(.title)
                .foregroundStyle(verdict.color(for: theme))
                .contentTransition(.numericText())

            VerdictBadge(verdict: verdict, showsLabel: true, size: .compact)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .skylineGlassCard(cornerRadius: AppRadius.lg, theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) \(verdict.displayName)"))
    }

    private func laterCallout(count: Int) -> some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            Text(count == 1 ? "1 place left for later" : "\(count) places left for later")
                .appFont(.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(transition) { viewModel.reviewDeferred() }
            } label: {
                Text(count == 1 ? "Review it now" : "Review them now")
                    .appFont(.verdictLabel)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs + 2)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private func summaryRow(_ highlight: PlaceReviewViewModel.Summary.Highlight) -> some View {
        let theme = themeManager.currentTheme
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

        return HStack(spacing: AppSpacing.md - 4) {
            PHAssetImageView(
                localIdentifier: highlight.assetIdentifier,
                size: .thumbnail,
                contentMode: .fill
            )
            .frame(width: summaryThumb, height: summaryThumb)
            .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))

            Text(highlight.name)
                .appFont(.bodyBold, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            VerdictBadge(verdict: highlight.verdict, showsLabel: false, size: .compact)
        }
        .padding(AppSpacing.sm + 2)
        .skylineGlass(.card, in: shape, theme: theme)
        .containerShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(highlight.name), \(highlight.verdict.accessibilityLabel)"))
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isEditingName else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isEditingName else { return }

                // Projected, so a fast flick counts even when the finger did
                // not travel the full distance.
                if let decision = decision(for: value.predictedEndTranslation, threshold: commitThreshold) {
                    commit(decision, from: value.translation, animated: true)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        drag = .zero
                    }
                }
            }
    }

    /// Maps a drag to an answer. The dominant axis wins, so a sloppy diagonal
    /// still resolves to what the user clearly meant.
    private func decision(for translation: CGSize, threshold: CGFloat) -> ReviewDecision? {
        if abs(translation.width) >= abs(translation.height) {
            guard abs(translation.width) >= threshold else { return nil }
            return .verdict(translation.width > 0 ? .worthIt : .skip)
        }

        guard abs(translation.height) >= threshold else { return nil }
        return translation.height < 0 ? .verdict(.fine) : .later
    }

    private func commit(_ decision: ReviewDecision, from translation: CGSize, animated: Bool) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        guard animated && !reduceMotion else {
            drag = .zero
            withAnimation(transition) { viewModel.decide(decision) }
            return
        }

        withAnimation(.easeOut(duration: 0.22)) {
            drag = flyAway(for: decision, from: translation)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            viewModel.decide(decision)
            drag = .zero
        }
    }

    private func flyAway(for decision: ReviewDecision, from translation: CGSize) -> CGSize {
        switch decision {
        case .verdict(.worthIt): return CGSize(width: 900, height: translation.height)
        case .verdict(.skip):    return CGSize(width: -900, height: translation.height)
        case .verdict(.fine):    return CGSize(width: translation.width, height: -900)
        case .later:             return CGSize(width: translation.width, height: 900)
        }
    }

    // MARK: - Stamp

    @ViewBuilder
    private var stampOverlay: some View {
        if let pending = decision(for: drag, threshold: previewThreshold) {
            ReviewStamp(decision: pending)
                .opacity(stampOpacity)
                .scaleEffect(0.9 + 0.1 * stampOpacity)
                .allowsHitTesting(false)
        }
    }

    private var stampOpacity: Double {
        let magnitude = max(abs(drag.width), abs(drag.height))
        let span = max(commitThreshold - previewThreshold, 1)
        return min(1, max(0, Double((magnitude - previewThreshold) / span)))
    }

    private var rotationDegrees: Double {
        guard !reduceMotion else { return 0 }
        return min(10, max(-10, Double(drag.width / 22)))
    }

    private var transition: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.82)
    }
}

// MARK: - Stamp

/// The transient "this is what you are about to choose" mark. Verdicts reuse
/// `VerdictBadge` so the stamp and the eventual badge on the map are visibly
/// the same object; "later" gets a neutral twin because it is not a verdict.
private struct ReviewStamp: View {
    @EnvironmentObject var themeManager: ThemeManager

    let decision: ReviewDecision

    var body: some View {
        let theme = themeManager.currentTheme

        Group {
            switch decision {
            case .verdict(let verdict):
                VerdictBadge(verdict: verdict)
            case .later:
                HStack(spacing: AppSpacing.xs + 1) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(theme.colors.textSecondary)
                        .symbolRenderingMode(.hierarchical)
                    Text("LATER")
                        .foregroundStyle(theme.colors.text)
                }
                .appFont(.verdictLabel)
                .padding(.horizontal, AppSpacing.sm + 2)
                .padding(.vertical, 5)
                .skylineGlassCapsule(tint: theme.colors.textSecondary.opacity(0.30), theme: theme)
            }
        }
        .scaleEffect(1.8)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Deck") {
    PlaceReviewView(
        trip: .sample,
        places: [
            DetectedPlace(
                tripId: Trip.sample.id,
                name: "Kissa Sakaiki",
                latitude: 35.6595,
                longitude: 139.7005,
                category: "MKPOICategoryCafe",
                source: .photoGPS,
                significance: 0.9
            ),
            DetectedPlace(
                tripId: Trip.sample.id,
                name: "2-14 Udagawacho",
                latitude: 35.6612,
                longitude: 139.6982,
                source: .photoGPS,
                significance: 0.6
            )
        ]
    )
    .environmentObject(ThemeManager())
}

#Preview("Empty deck") {
    PlaceReviewView(trip: .sample, places: [])
        .environmentObject(ThemeManager())
}
