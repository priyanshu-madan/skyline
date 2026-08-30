//
//  AuthenticationView.swift
//  SkyLine
//
//  The sign-in gate: Sign in with Apple and Sign in with Google, given equal
//  weight on purpose.
//
//  WHY THEY LOOK THE SAME: App Review requires Sign in with Apple to be offered
//  wherever a third-party sign-in is (Guideline 4.8), and "offered" is a visual
//  claim as much as a functional one. Both buttons therefore share one component,
//  one height, one corner radius and one type token — the only difference is the
//  ground they sit on.
//
//  WHY THE GOOGLE BUTTON CAN BE DISABLED: the Google client ID lives in Info.plist
//  and is not in the repository. A build without it must SAY so on the button,
//  before the tap, rather than opening a browser that dead-ends.
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingError = false

    @ScaledMetric(relativeTo: .largeTitle) private var markGlyph: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var markWell: CGFloat = 120

    /// Whether the Google provider appears at all. Off while the app is scoped
    /// to boarding-pass scanning - see the call site for why.
    static let showsGoogleSignIn = false

    /// `GoogleSignInService` is main-actor isolated, so the properties that read it
    /// are annotated rather than being reached from a nonisolated context.
    @MainActor
    private var googleProblem: GoogleSignInConfiguration.Problem? {
        GoogleSignInService.shared.unavailableReason
    }

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                header
                features
                authenticationSection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            LinearGradient(
                colors: [
                    theme.colors.primary.opacity(0.12),
                    theme.colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            if let errorMessage = authService.authenticationState.errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(item: $authService.pendingSignIn) { pending in
            CloudStorageNoticeView(
                pending: pending,
                onContinue: { authService.acceptPendingSignIn() },
                onCancel: { authService.discardPendingSignIn() }
            )
            .environmentObject(themeManager)
            // A sheet is its own presentation. Without this it renders against the
            // DEVICE appearance, so the app's Light theme on a dark-mode phone
            // produces a dark sheet full of dark text.
            .preferredColorScheme(theme.colorScheme)
            .presentationBackground(theme.colors.background)
        }
        .onChange(of: authService.authenticationState) { _, state in
            if case .error = state {
                showingError = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(theme.colors.primary)
                    .frame(width: markWell, height: markWell)

                Image(systemName: "airplane")
                    .font(.system(size: markGlyph, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.onAccent)
            }
            .appElevation(.lg, theme: theme)
            .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text("Welcome to SkyLine")
                    .appFont(.titleLarge)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)

                Text("Log the places you've been, and whether they were worth it.")
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
    }

    // MARK: - Features

    private var features: some View {
        VStack(spacing: AppSpacing.sm) {
            FeatureRow(
                icon: "globe",
                title: "A globe of where you've been",
                description: "Every place you log lands on your own 3D map"
            )

            FeatureRow(
                icon: "photo.on.rectangle.angled",
                title: "Built from your camera roll",
                description: "SkyLine groups your photos into the places you actually stopped"
            )

            FeatureRow(
                icon: "hand.thumbsdown",
                title: "Room for Skip",
                description: "Record the places that weren't worth it, not just the ones that were"
            )
        }
    }

    // MARK: - Authentication

    private var authenticationSection: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            if authService.isLoading {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(theme.colors.primary)

                    Text("Signing in…")
                        .appFont(.bodyBold)
                        .foregroundStyle(theme.colors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .transition(reduceMotion ? .identity : .opacity)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    SignInProviderButton(
                        systemImage: "applelogo",
                        title: "Sign in with Apple",
                        ground: .ink
                    ) {
                        authService.signInWithApple()
                    }

                    // Google sign-in is hidden while the app is scoped to
                    // boarding-pass scanning. No OAuth client ID has ever been
                    // configured, so the button could only ever render disabled
                    // with an explanation of its own brokenness - and it buys no
                    // capability even when it works, because CloudKit's private
                    // database belongs to the DEVICE's iCloud account, not to
                    // whoever signed in. Flip this to true to bring it back;
                    // nothing else was removed.
                    if Self.showsGoogleSignIn {
                        SignInProviderButton(
                            systemImage: "g.circle",
                            title: "Sign in with Google",
                            ground: .surface,
                            isEnabled: googleProblem == nil
                        ) {
                            Task { await authService.signInWithGoogle() }
                        }

                        if let problem = googleProblem {
                            // The button explains itself while disabled. A tap
                            // that silently did nothing would read as broken.
                            VStack(spacing: AppSpacing.xs) {
                                Text(problem.explanation)
                                Text(problem.remedy)
                            }
                            .appFont(.footnote, lineLimit: .unlimited)
                            .foregroundStyle(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                            .padding(.top, AppSpacing.xs)
                        }
                    }
                }
                .frame(maxWidth: 360)
                .transition(reduceMotion ? .identity : .opacity)
            }

            VStack(spacing: AppSpacing.xs) {
                Text("By signing in, you agree to our privacy practices")
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)

                Text("Your places are stored in your own private iCloud, not on our servers")
                    .appFont(.caption, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .padding(.top, AppSpacing.xs)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authService.isLoading)
    }
}

// MARK: - Sign In Button

/// One shape for every provider, so no provider is visually demoted.
private struct SignInProviderButton: View {
    /// The ground the button sits on. Both are drawn from theme tokens: `ink`
    /// resolves to near-black on Light and near-white on Dark, which is exactly the
    /// Sign in with Apple convention, while `surface` is the neutral outlined
    /// treatment Google's guidelines describe.
    enum Ground {
        case ink
        case surface
    }

    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    let title: String
    let ground: Ground
    var isEnabled: Bool = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 50

    var body: some View {
        let theme = themeManager.currentTheme
        let colors = theme.colors

        let background: Color = ground == .ink ? colors.text : colors.surface
        let foreground: Color = ground == .ink ? colors.background : colors.text
        // Only the surface ground needs an edge; the ink ground already separates
        // itself from the page. Optional rather than a transparent stroke so no
        // colour in this file comes from anywhere but the palette.
        let stroke: Color? = ground == .ink ? nil : colors.border

        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(AppTypography.mono(.body, weight: .medium))

                Text(title)
                    .appFont(.bodyBold)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(background)
            )
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
        .appElevation(.sm, theme: theme)
        .accessibilityLabel(Text(title))
        .accessibilityHint(isEnabled ? Text("") : Text("Unavailable in this build"))
    }
}

// MARK: - Cloud Storage Notice

/// Shown after a successful third-party sign-in on a device with no iCloud account.
///
/// The honest problem: SkyLine writes everything to the CloudKit PRIVATE database,
/// which belongs to the device's iCloud account. A Google identity has no bearing
/// on that. Rather than admitting the user into an app that quietly drops every
/// place they log, this states plainly what will and will not work and lets them
/// choose.
private struct CloudStorageNoticeView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let pending: PendingSignIn
    let onContinue: () -> Void
    let onCancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 84

    var body: some View {
        let theme = themeManager.currentTheme
        let colors = theme.colors

        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(colors.warning)
                    .frame(width: glyphWell, height: glyphWell)
                    .skylineGlass(.card, in: Circle(), tint: colors.warning.opacity(0.22), theme: theme)
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text("This iPhone isn't signed in to iCloud")
                        .appFont(.headline, lineLimit: .unlimited)
                        .foregroundStyle(colors.text)
                        .multilineTextAlignment(.center)

                    Text("You're signed in with \(pending.provider.displayName), and that part worked. But SkyLine keeps your places in your own private iCloud database — which belongs to the iPhone's iCloud account, not to your \(pending.provider.displayName) account.")
                        .appFont(.bodySmall, lineLimit: .unlimited)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    NoticeLine(
                        symbol: "checkmark.circle.fill",
                        tint: colors.success,
                        text: "You can use the app and log places right now"
                    )
                    NoticeLine(
                        symbol: "xmark.circle.fill",
                        tint: colors.error,
                        text: "Nothing will sync to your other devices"
                    )
                    NoticeLine(
                        symbol: "xmark.circle.fill",
                        tint: colors.error,
                        text: "Nothing will be backed up — deleting the app deletes your log"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .stroke(colors.border, lineWidth: 1)
                )

                Text("To fix it: open Settings, tap your name at the top, sign in to iCloud, and make sure iCloud Drive is on.")
                    .appFont(.footnote, lineLimit: .unlimited)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    VStack(spacing: AppSpacing.sm) {
                        Button(action: onContinue) {
                            Text("Continue anyway")
                                .appFont(.bodyBold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(colors.primary)

                        Button(action: onCancel) {
                            Text("Not now")
                                .appFont(.caption)
                                .foregroundStyle(colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xl)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.colors.background)
        .presentationDetents([.large])
        .presentationCornerRadius(AppRadius.sheet)
        .interactiveDismissDisabled()
    }
}

private struct NoticeLine: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: symbol)
                .font(AppTypography.mono(.footnote, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .appFont(.bodySmall, lineLimit: .unlimited)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    @ScaledMetric(relativeTo: .title3) private var glyphWell: CGFloat = 40

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppTypography.mono(.title3, weight: .medium))
                .foregroundStyle(theme.colors.primary)
                .frame(width: glyphWell, height: glyphWell)
                .background(theme.colors.primary.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .appFont(.bodyBold)
                    .foregroundStyle(theme.colors.text)

                Text(description)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(theme.colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    let theme = ThemeManager()
    theme.currentTheme = .light
    return AuthenticationView()
        .environmentObject(theme)
        .environmentObject(AuthenticationService.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    let theme = ThemeManager()
    theme.currentTheme = .dark
    return AuthenticationView()
        .environmentObject(theme)
        .environmentObject(AuthenticationService.shared)
        .preferredColorScheme(.dark)
}
