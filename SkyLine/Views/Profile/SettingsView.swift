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

            // Sign Out is destructive, so it carries `error` ink — but never a
            // filled `error` block. A 10%-tinted red panel reads as warm mud on the
            // dark palette and as a sticky note on the light one; the ink alone,
            // paired with a directional glyph, is the whole signal.
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                FormSecondaryButton(
                    title: "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive
                ) {
                    Task {
                        await authService.signOut()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthenticationService.shared)
}
