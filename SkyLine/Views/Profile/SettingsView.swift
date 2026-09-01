//
//  SettingsView.swift
//  SkyLine
//
//  Settings view with preferences and account management.
//  A settings row is a form field that happens to hold a control, so it uses the
//  same recessed well, the same radius and the same glyph position as one.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    /// The deletion confirmation. Separate from `isDeleting` so a dismissed
    /// dialog can never leave the busy state stuck on.
    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    /// Set only when the account is still there. Presenting this is the ONLY
    /// path that tells the user anything about a failed deletion, so it names
    /// what survived rather than saying "something went wrong".
    @State private var deletionFailure: AccountDeletionFailure?

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FormScreenHeader(title: "Settings") { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        appearanceSection
                        accountSection
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .skylineScrollEdges()
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        // Named consequences, not "are you sure". The user is about to lose the
        // flights they scanned one boarding pass at a time.
        .confirmationDialog(
            "Delete your SkyLine account?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await runDeletion() }
            }
            Button("Keep My Account", role: .cancel) {}
        } message: {
            Text(deletionConsequences)
        }
        .alert(
            deletionFailure?.title ?? "Your account wasn't deleted",
            isPresented: isShowingFailure,
            presenting: deletionFailure
        ) { _ in
            Button("Try Again") {
                Task { await runDeletion() }
            }
            Button("Not Now", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        let theme = themeManager.currentTheme
        let isDark = themeManager.currentTheme == .dark

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Appearance")

            FormFieldRow(icon: isDark ? "moon.fill" : "sun.max.fill") {
                Toggle(isOn: themeBinding) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Dark Mode")
                            .appFont(.body, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.text)

                        Text(isDark ? "Deep navy, the globe's own night sky" : "Warm paper, high contrast ink")
                            .appFont(.placeMeta, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .tint(theme.colors.primary)
            }
        }
    }

    /// The theme write path is unchanged — this is the same assignment the toggle
    /// always made, only lifted out of the view builder.
    private var themeBinding: Binding<Bool> {
        Binding(
            get: { themeManager.currentTheme == .dark },
            set: { isDark in
                themeManager.currentTheme = isDark ? .dark : .light
            }
        )
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Account")

            // Both controls are destructive, so both carry `error` ink — but
            // never a filled `error` block. A 10%-tinted red panel reads as warm
            // mud on the dark palette and as a sticky note on the light one; the
            // ink alone, paired with the glyph, is the whole signal. The two
            // glyphs are what separate them: a door out versus a bin.
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                accountControls
            }

            deletionFootnote
        }
    }

    /// Flattened deliberately: a `SkyLineGlassPanel` wrapping an `if` wrapping
    /// two buttons is one more layer of concrete generic type than it needs, and
    /// deeply nested view builders are how this app has crashed in
    /// `swift_getTypeByMangledName` before.
    @ViewBuilder
    private var accountControls: some View {
        if isDeleting {
            deletionProgressRow
        } else {
            VStack(spacing: AppSpacing.sm) {
                FormSecondaryButton(
                    title: "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive
                ) {
                    Task {
                        await authService.signOut()
                    }
                }

                FormSecondaryButton(
                    title: "Delete Account",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    isConfirmingDeletion = true
                }
            }
        }
    }

    /// Replaces both buttons while the sweep runs. Deleting an account pages
    /// through every record type in CloudKit and can take real seconds, and a
    /// second tap would start a second sweep over the first.
    private var deletionProgressRow: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.error)

            Text("Deleting your account…")
                .appFont(.bodyBold, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.error)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm + 2)
        .accessibilityLabel("Deleting your account")
    }

    /// The one thing deletion cannot do for the user, said where they will read
    /// it rather than in a log.
    @ViewBuilder
    private var deletionFootnote: some View {
        if authService.signInProvider == .apple, !authService.canRevokeAppleCredential {
            Text(CredentialRevocation.notRevokedNote)
                .appFont(.footnote, lineLimit: .unlimited)
                .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Deletion

    /// What the user is agreeing to. Flights are named first because they are
    /// what someone has actually put work into: one scanned boarding pass each.
    private var deletionConsequences: String {
        var text = "Every flight you've logged is permanently deleted, along with your trips, "
            + "places, profile and search history — from iCloud and from this device. "
            + "This can't be undone, and signing in again won't bring any of it back."
        if authService.signInProvider == .apple, !authService.canRevokeAppleCredential {
            text += "\n\n" + CredentialRevocation.notRevokedNote
        }
        return text
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { deletionFailure != nil },
            set: { if !$0 { deletionFailure = nil } }
        )
    }

    /// Runs the deletion and does exactly one of two things with the result.
    ///
    /// On success the service has already signed the user out, so SkyLineApp
    /// swaps the whole root for the sign-in screen and this sheet goes with it —
    /// there is nothing left to dismiss. On failure the account still exists and
    /// the session is untouched, so the alert can offer a real retry.
    @MainActor
    private func runDeletion() async {
        guard !isDeleting else { return }
        isDeleting = true
        deletionFailure = nil

        let outcome = await AccountDeletionService.deleteAccount(using: authService)

        isDeleting = false
        if case .failed(let failure) = outcome {
            deletionFailure = failure
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthenticationService.shared)
}
