//
//  SettingsView.swift
//  SkyLine
//
//  Settings view with preferences and account management
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            themeManager.currentTheme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(themeManager.currentTheme.colors.surface.opacity(0.8))
                                    .overlay(
                                        Circle()
                                            .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))

                    Spacer()

                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 20) {
                        // Preferences Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PREFERENCES")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                            // Dark Mode Toggle
                            HStack {
                                Image(systemName: themeManager.currentTheme == .dark ? "moon.fill" : "sun.max.fill")
                                    .font(.system(size: 20, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                                    .frame(width: 30)

                                Text("Dark Mode")
                                    .font(.system(.body, design: .monospaced, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme.colors.text)

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { themeManager.currentTheme == .dark },
                                    set: { isDark in
                                        themeManager.currentTheme = isDark ? .dark : .light
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                            )
                        }

                        // Account Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ACCOUNT")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                            // Sign Out Button
                            Button {
                                Task {
                                    await authService.signOut()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 20, design: .monospaced))
                                        .foregroundColor(.red)
                                        .frame(width: 30)

                                    Text("Sign Out")
                                        .font(.system(.body, design: .monospaced, weight: .medium))
                                        .foregroundColor(.red)

                                    Spacer()
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
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
