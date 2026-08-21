//
//  OnboardingView.swift
//  SkyLine
//
//  First run. Three beats: what this is, what a verdict is, and then a map that
//  is not empty.
//
//  THE TWO THINGS THIS SCREEN IS ACTUALLY FOR:
//
//  1. TEACH THE VERDICT BY DOING IT. Page two is not a legend. It is a real
//     `PlaceCard` and three real `VerdictChip`s, and the flow does not move on
//     until the user has put one on the card. The lesson that follows is keyed
//     to the verdict they chose and always lands on Skip — the answer a
//     saved-places list can never hold, and the reason this app exists.
//
//  2. PUT THE PHOTO ASK IN THE RIGHT PLACE, THEN GET OUT OF THE WAY. iOS shows
//     the photo prompt exactly once per install, so it comes last, after the
//     verdict lesson: by then "SkyLine groups your photos into places for you to
//     judge" refers to something the user has already done with their thumb.
//     Nothing in this file calls `requestAccess()`. `FirstRunDetectionView` owns
//     the primer, the prompt and the scan, because it is the only screen that
//     knows what it is about to read — it can promise that days near home are
//     ignored and that the pass covers the user's whole history, which no
//     general-purpose copy here could truthfully say. `PhotoAccessGateView` is
//     the model both of those primers are built from; its own copy is
//     trip-scoped ("only photos taken during this trip are read") and so is not
//     used at first run, where there is no trip.
//
//  PRESENTATION. This is an overlay inside `SkyLineApp`'s root ZStack, not a
//  `.sheet`. A sheet is a separate presentation that does not inherit
//  `preferredColorScheme`, and the app's theme toggle is independent of the
//  device appearance — a mismatch this codebase has already had to fix once. As
//  a child of the root stack it inherits the theme for free.
//

import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel: OnboardingViewModel
    @Namespace private var verdictGlass

    /// What the library scan found, held only long enough to feed the deck.
    @State private var detectionResult: LibraryDetectionResult?
    /// The trip currently being judged. Drives the push onto the verdict deck.
    @State private var reviewEpisode: LibraryEpisode?

    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 84

    init(startingAt page: OnboardingPage = .premise, onFinish: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(startingAt: page, onFinish: onFinish)
        )
    }

    // MARK: Body

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                if viewModel.page.showsChrome {
                    chrome
                }

                pageBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsFooter {
                    footer
                }
            }
        }
        .animation(pageAnimation, value: viewModel.page)
        .animation(pageAnimation, value: viewModel.practiceVerdict)
        .accessibilityElement(children: .contain)
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    // MARK: Backdrop

    /// Opaque on purpose. `SkyLineApp` keeps `ContentView` mounted underneath so
    /// the WebKit globe can boot while the user reads, and an opaque ground is
    /// what stops a half-drawn globe flickering through the copy.
    private var backdrop: some View {
        let colors = themeManager.currentTheme.colors

        return ZStack {
            colors.background

            LinearGradient(
                stops: [
                    .init(color: colors.primary.opacity(0.16), location: 0.0),
                    .init(color: .clear, location: 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Chrome

    private var chrome: some View {
        let theme = themeManager.currentTheme

        return HStack {
            if viewModel.canGoBack {
                SkyLineGlassIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back"
                ) {
                    viewModel.goBack()
                }
            }

            Spacer(minLength: 0)

            if viewModel.isSkippable {
                Button {
                    viewModel.skip()
                } label: {
                    Text("Skip")
                        .appFont(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Skip setup"))
                .accessibilityHint(Text("You can find your places later from the place log."))
            }
        }
        .overlay { stepIndicator }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }

    /// Fixed sizes, not scaled: these are hairlines of chrome, and a dot that
    /// grew with Dynamic Type would stop reading as a position marker and start
    /// reading as a block. Same reasoning as `VerdictRail`'s 3pt spine.
    private var stepIndicator: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.xs + 2) {
            ForEach(OnboardingPage.indicated) { page in
                Capsule(style: .continuous)
                    .fill(page == viewModel.page ? theme.colors.primary : theme.colors.border)
                    .frame(width: page == viewModel.page ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(viewModel.page.accessibilityProgressLabel))
    }

    // MARK: Pages

    @ViewBuilder
    private var pageBody: some View {
        Group {
            switch viewModel.page {
            case .premise:
                PhotoGateCenteredScroll { premisePage }

            case .verdict:
                PhotoGateCenteredScroll { verdictPage }

            case .detect:
                detectPage
            }
        }
        .id(viewModel.page)
        .transition(.opacity)
    }

    // MARK: 3 — Detection, and the deck it feeds

    /// The photo primer, the one system prompt and the library scan are all
    /// owned by `FirstRunDetectionView` — the only screen that knows what it is
    /// about to read.
    ///
    /// Its summary button says "Review 12 places", so the result has to go
    /// somewhere. It does NOT persist anything; a `DetectedPlace` becomes a real
    /// `Place` only when a verdict is put on it in `PlaceReviewView`. Ending
    /// onboarding on the summary screen would therefore leave the user on the
    /// empty globe the whole flow exists to prevent, so the most recent trip is
    /// pushed straight onto the deck.
    ///
    /// ONE trip, not all of them. A heavy library can produce twenty episodes,
    /// and twenty decks back to back is not an onboarding. The newest is the one
    /// the user remembers, and judging it is what puts pins on the map; the rest
    /// stay in the library and a later scan picks them up with verdicts carried
    /// forward (`FirstRunDetectionView(existingPlaces:)`).
    private var detectPage: some View {
        NavigationStack {
            FirstRunDetectionView(
                onFinish: { result in beginReview(of: result) },
                // The same exit, drawn by the screen the user is looking at
                // rather than by a second Skip button in our chrome. It
                // deliberately does not mark detection complete, so the place
                // log can offer it again.
                onSkip: { viewModel.skip() }
            )
            .navigationDestination(item: $reviewEpisode) { episode in
                PlaceReviewView(
                    trip: episode.asTrip(),
                    detectedPlaces: detectionResult?.places(in: episode) ?? [],
                    // Fires when the deck runs out AND again from its Done
                    // button. `complete()` guards against the second call.
                    onFinish: { _ in viewModel.finishDetection() }
                )
            }
        }
        .tint(themeManager.currentTheme.colors.primary)
    }

    /// Routes the scan's result to the deck, or ends the flow when there is
    /// nothing to judge. An empty result is an ordinary outcome — an empty
    /// library, a camera that never wrote GPS — never an error.
    private func beginReview(of result: LibraryDetectionResult) {
        detectionResult = result
        // `episodes` arrives newest-first.
        guard let episode = result.episodes.first(where: { !result.places(in: $0).isEmpty }) else {
            viewModel.finishDetection()
            return
        }
        reviewEpisode = episode
    }

    // MARK: 1 — Premise

    private var premisePage: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.lg) {
            heroGlyph(for: .premise, tint: theme.colors.primary)

            copyBlock(for: .premise)

            // The vocabulary, planted before page two teaches it. Three peers:
            // Skip is the same size and the same weight as Worth it, because in
            // this app it is worth exactly as much.
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Verdict.allCases) { verdict in
                        VerdictBadge(verdict: verdict, size: .compact)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("The three verdicts: worth it, fine, skip"))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: 2 — The verdict, performed

    private var verdictPage: some View {
        VStack(spacing: AppSpacing.lg) {
            copyBlock(for: .verdict)

            // A real card, not an illustration. Whatever they tap lands on it.
            // Nothing here touches PlaceStore — the card is local sample data.
            PlaceCard(
                name: "Times Square",
                date: Self.practiceDate,
                subtitle: "New York · you stopped for 40 minutes",
                verdict: viewModel.practiceVerdict,
                photoCount: 12,
                style: .row,
                placeholderSystemImage: "building.2"
            )
            .frame(maxWidth: 360)
            .allowsHitTesting(false)

            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Verdict.allCases) { verdict in
                        VerdictChip(
                            verdict: verdict,
                            isSelected: viewModel.practiceVerdict == verdict,
                            namespace: verdictGlass
                        ) {
                            viewModel.selectPractice(verdict)
                        }
                    }
                }
            }
            .frame(maxWidth: 360)

            if let chosen = viewModel.practiceVerdict {
                lesson(for: chosen)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityValue(
            Text(viewModel.practiceVerdict.map { "You chose \($0.displayName)" } ?? "No verdict chosen yet")
        )
    }

    private func lesson(for verdict: Verdict) -> some View {
        let theme = themeManager.currentTheme
        // Inked with the verdict the lesson is ABOUT, which is always Skip.
        let ink = theme.colors.verdictSkip

        return HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: Verdict.skip.systemImage)
                .font(AppTypography.mono(.footnote, weight: .semibold))
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(OnboardingPage.verdictLesson(for: verdict))
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: 360)
        .skylineGlassCard(tint: ink.opacity(0.20), theme: theme)
    }

    // MARK: Shared page parts

    /// The glyph well, same as `FirstRunDetectionView`'s: a typography token for
    /// the symbol so it scales with Dynamic Type, and a `@ScaledMetric` for the
    /// circle around it so the well grows in step with the glyph inside it.
    private func heroGlyph(for page: OnboardingPage, tint: Color) -> some View {
        let theme = themeManager.currentTheme

        return Image(systemName: page.systemImage)
            .font(AppTypography.mono(.largeTitle, weight: .regular))
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .frame(width: glyphWell, height: glyphWell)
            .skylineGlass(.card, in: Circle(), tint: tint.opacity(0.22), theme: theme)
            .accessibilityHidden(true)
    }

    private func copyBlock(for page: OnboardingPage) -> some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            Text(page.title)
                // `.title` rather than `.titleLarge`: monospaced advance width is
                // ~0.6em, so a 34pt display line of this length cannot fit a
                // 375pt screen without shrinking towards illegibility.
                .appFont(.title, lineLimit: .exactly(3))
                .foregroundStyle(theme.colors.text)
                .multilineTextAlignment(.center)

            Text(page.message)
                .appFont(.bodySmall, lineLimit: .unlimited)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    /// `.detect` brings its own actions.
    private var showsFooter: Bool { viewModel.page.showsChrome }

    @ViewBuilder
    private var footer: some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 0) {
            if let hint = viewModel.page.interactionHint, !viewModel.canAdvance {
                // A disabled button teaches nothing. A nudge does — and the tap
                // it is asking for IS the lesson.
                Text(hint)
                    .appFont(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .accessibilityHint(Text("Choose worth it, fine or skip to continue."))
            } else {
                PhotoGateActionStack(actions: footerActions)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }

    private var footerActions: [PhotoGateAction] {
        guard let title = viewModel.page.primaryActionTitle else { return [] }
        return [
            PhotoGateAction(title: title, emphasis: .primary) { viewModel.advance() }
        ]
    }

    // MARK: Sample data

    /// A date a season back, so the practice card carries a plausible "Jun 14"
    /// rather than today.
    private static let practiceDate: Date = {
        Calendar.current.date(byAdding: .day, value: -96, to: Date()) ?? Date()
    }()
}

// MARK: - Previews

#Preview("Onboarding - Dark") {
    OnboardingView(onFinish: {})
        .environmentObject(ThemeManager())
        .preferredColorScheme(.dark)
}

#Preview("Onboarding - Light") {
    let manager = ThemeManager()
    manager.currentTheme = .light
    return OnboardingView(onFinish: {})
        .environmentObject(manager)
        .preferredColorScheme(.light)
}
