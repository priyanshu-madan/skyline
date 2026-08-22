//
//  PhotoAccessGateView.swift
//  SkyLine
//
//  The screen that stands between a trip and its swipe deck while SkyLine
//  cannot read the camera roll yet.
//
//  THE ONE-SHOT RULE: iOS shows the photo permission sheet exactly once per
//  install. Every later "no" is a trip to Settings. So the primer below explains
//  what SkyLine does with photos BEFORE `requestAccess()` is ever called, and
//  nothing in this file calls it as a side effect of appearing.
//
//  Note that `PhotoPlaceDetectionService.detectPlaces` also calls
//  `requestAccess()`. That call is harmless once this gate has run — the service
//  short-circuits on an already-resolved status — but it is exactly why a "not
//  now" here must NOT start detection: it would fire the system sheet the user
//  just declined to see.
//

import SwiftUI
import Photos

// MARK: - Action

/// One button in a gate or notice panel.
///
/// `primary` is the glass-prominent capsule, `secondary` a plain glass capsule,
/// `quiet` a bare text button — for the exit that has to exist but must not
/// compete with the thing we actually want the user to do.
struct PhotoGateAction: Identifiable {
    enum Emphasis {
        case primary
        case secondary
        case quiet
    }

    let id = UUID()
    let title: String
    /// Optional second line, for a consequence the title should not carry.
    /// Used where a primary action does less than its count implies - e.g.
    /// reviewing one trip out of several, with the rest kept for later.
    var subtitle: String? = nil
    var emphasis: Emphasis = .secondary
    let action: () -> Void
}

// MARK: - Notice Scaffold

/// Glyph + headline + body + action stack, in the same visual vocabulary as
/// `PlaceLogEmptyStateView`.
///
/// `PlaceLogEmptyStateView` owns the fixed, named empty states and is used
/// directly wherever its copy fits. This scaffold exists for the states whose
/// copy is only knowable at runtime — a photo count, a destination name, which
/// rung of the detection fallback ladder actually ran — and for the states that
/// need a third way out. Nothing outside the detection on-ramp should use it.
struct PhotoGateNoticeView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    let title: String
    let message: String
    var footnote: String? = nil
    var accent: Color? = nil
    var actions: [PhotoGateAction] = []

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 88

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = accent ?? theme.colors.textSecondary

        VStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)
                .frame(width: glyphWell, height: glyphWell)
                .skylineGlass(.card, in: Circle(), tint: ink.opacity(0.22), theme: theme)
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                if let footnote {
                    Text(footnote)
                        .appFont(.footnote, lineLimit: .unlimited)
                        .foregroundStyle(theme.colors.textSecondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }

            if !actions.isEmpty {
                PhotoGateActionStack(actions: actions)
                    .padding(.top, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Action Stack

/// The button column. One `GlassEffectContainer` for the run so adjacent capsules
/// sample a single backdrop instead of stacking blurs.
struct PhotoGateActionStack: View {
    @EnvironmentObject var themeManager: ThemeManager

    let actions: [PhotoGateAction]

    var body: some View {
        let theme = themeManager.currentTheme

        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm) {
                ForEach(actions) { action in
                    switch action.emphasis {
                    case .primary:
                        Button {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            action.action()
                        } label: {
                            VStack(spacing: 2) {
                                Text(action.title)
                                    .appFont(.bodyBold)
                                if let subtitle = action.subtitle {
                                    Text(subtitle)
                                        .appFont(.caption)
                                        .opacity(0.75)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.xs)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(theme.colors.primary)

                    case .secondary:
                        Button {
                            action.action()
                        } label: {
                            Text(action.title)
                                .appFont(.bodySmall)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)

                    case .quiet:
                        Button {
                            action.action()
                        } label: {
                            Text(action.title)
                                .appFont(.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 320)
        }
    }
}

// MARK: - Centered Scroll

/// Centres its content vertically but still scrolls once accessibility type sizes
/// push it past the screen. A plain `VStack` clips at AX5; a plain `ScrollView`
/// top-aligns and looks broken at default sizes.
struct PhotoGateCenteredScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Photo Access Gate

/// Renders the right thing for each `PhotoLibraryAccess` state and calls
/// `onProceed` only when the user has actually decided to go ahead.
///
/// Deliberately does NOT auto-proceed out of `.limited`. A limited library is a
/// silently degraded result — SkyLine will find the places in the twelve photos
/// that were shared and no others — so the user gets one clear chance to widen
/// the selection before the deck is built from a partial trip.
struct PhotoAccessGateView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var authorization = PhotoLibraryAuthorizationService.shared

    /// Trip destination, used to keep the copy concrete ("places in Lisbon").
    var destination: String? = nil
    /// Trip date range, so the primer can say exactly which photos get read.
    var dateRangeText: String? = nil
    /// The user is ready: run detection with whatever access is now granted.
    /// Called at most once per appearance.
    var onProceed: () -> Void
    /// Back out entirely. Omit to hide every "not now" affordance.
    var onCancel: (() -> Void)? = nil

    @State private var isRequesting = false
    @State private var didProceed = false

    // MARK: Body

    var body: some View {
        PhotoGateCenteredScroll {
            Group {
                switch authorization.access {
                case .notDetermined: primer
                case .limited:       limited
                case .denied:        denied
                case .full:          ready
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: authorization.access)
        }
        .task {
            authorization.refresh()
            proceedIfFullAccess()
        }
        .onChange(of: authorization.access) { _, _ in
            proceedIfFullAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings, or from the limited-library picker.
            if phase == .active { authorization.refresh() }
        }
    }

    // MARK: notDetermined — the primer

    /// The only screen in the app that gets one shot. Everything here is about
    /// making the system sheet that follows feel like a question the user
    /// already knows the answer to.
    private var primer: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.colors.primary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 88, height: 88)
                .skylineGlass(.card, in: Circle(), tint: theme.colors.primary.opacity(0.22), theme: theme)
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text("Your photos already know where you went")
                    .appFont(.headline)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)

                Text(primerMessage)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                PrimerPoint(
                    systemImage: "calendar",
                    text: dateRangeText.map { "Only photos taken \($0) are read." }
                        ?? "Only photos taken during this trip are read."
                )
                PrimerPoint(
                    systemImage: "lock.shield",
                    text: "Grouping happens on this iPhone. Your photos are never uploaded."
                )
                PrimerPoint(
                    systemImage: "exclamationmark.bubble",
                    text: "iOS only asks once. If you say no, you can still add places by hand — SkyLine just will not find them for you."
                )
            }
            .frame(maxWidth: 340, alignment: .leading)
            .padding(AppSpacing.md)
            .skylineGlassCard(theme: theme)

            PhotoGateActionStack(actions: primerActions)
                .padding(.top, AppSpacing.xs)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var primerMessage: String {
        if let destination, !destination.isEmpty {
            return "SkyLine reads when and where your \(destination) photos were taken, groups them into the spots you actually stopped at, and asks one question about each: worth it, fine, or skip."
        }
        return "SkyLine reads when and where your photos were taken, groups them into the spots you actually stopped at, and asks one question about each: worth it, fine, or skip."
    }

    private var primerActions: [PhotoGateAction] {
        var actions: [PhotoGateAction] = [
            PhotoGateAction(
                title: isRequesting ? "Waiting for iOS…" : "Choose what SkyLine can see",
                emphasis: .primary
            ) {
                request()
            }
        ]
        if let onCancel {
            actions.append(
                PhotoGateAction(title: "Not now", emphasis: .quiet) { onCancel() }
            )
        }
        return actions
    }

    // MARK: limited

    /// `PlaceLogEmptyStateView` already says this exactly right — primary
    /// "Manage access", secondary "Continue anyway" — so it is used as-is.
    private var limited: some View {
        PlaceLogEmptyStateView(
            state: .photoAccessLimited,
            onPrimaryAction: {
                authorization.presentLimitedPicker()
            },
            onSecondaryAction: {
                proceed()
            }
        )
    }

    // MARK: denied

    /// Denied is a dead end for photos but NOT for the trip: detection still
    /// falls back to suggesting places around the destination, so the second
    /// action here is a real one, not a consolation.
    private var denied: some View {
        VStack(spacing: AppSpacing.sm) {
            PlaceLogEmptyStateView(
                state: .photoAccessDenied,
                onPrimaryAction: {
                    authorization.openSettings()
                }
            )

            PhotoGateActionStack(actions: deniedFallbackActions)
                .padding(.bottom, AppSpacing.xl)
        }
    }

    private var deniedFallbackActions: [PhotoGateAction] {
        var actions: [PhotoGateAction] = [
            PhotoGateAction(title: suggestWithoutPhotosTitle, emphasis: .secondary) {
                proceed()
            }
        ]
        if let onCancel {
            actions.append(
                PhotoGateAction(title: "Not now", emphasis: .quiet) { onCancel() }
            )
        }
        return actions
    }

    private var suggestWithoutPhotosTitle: String {
        if let destination, !destination.isEmpty {
            return "Suggest places in \(destination) instead"
        }
        return "Suggest places instead"
    }

    // MARK: full

    /// Full access resolves straight through; this is only ever a single frame,
    /// but it must not be blank in case `onProceed` decides to stay put.
    private var ready: some View {
        PhotoGateNoticeView(
            systemImage: "checkmark.seal",
            title: "Photos are on",
            message: "SkyLine can read the photos from this trip.",
            accent: themeManager.currentTheme.colors.verdictWorthIt,
            actions: [
                PhotoGateAction(title: "Find my places", emphasis: .primary) { proceed() }
            ]
        )
    }

    // MARK: Actions

    private func request() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            let granted = await authorization.requestAccess()
            isRequesting = false
            // Full access needs no further decision. Limited and denied both
            // have something worth saying first, so they fall through to their
            // own state above rather than proceeding silently.
            if granted == .full { proceed() }
        }
    }

    private func proceedIfFullAccess() {
        guard authorization.access == .full else { return }
        proceed()
    }

    private func proceed() {
        guard !didProceed else { return }
        didProceed = true
        onProceed()
    }
}

// MARK: - Primer Row

private struct PrimerPoint: View {
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

#Preview("Gate") {
    PhotoAccessGateView(
        destination: "Lisbon",
        dateRangeText: "Mar 2 - Mar 9",
        onProceed: {},
        onCancel: {}
    )
    .environmentObject(ThemeManager())
}

#Preview("Notice") {
    PhotoGateNoticeView(
        systemImage: "mappin.and.ellipse",
        title: "13 places from this trip",
        message: "Swipe a verdict onto each one.",
        actions: [
            PhotoGateAction(title: "Review 13 places", emphasis: .primary) {},
            PhotoGateAction(title: "Look again", emphasis: .quiet) {}
        ]
    )
    .environmentObject(ThemeManager())
}
