//
//  EditProfileView.swift
//  SkyLine
//
//  View for editing user profile information.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingImageCropper = false
    @State private var imageForCropping: UIImage?
    @State private var isSaving = false

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 104
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 34

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FormScreenHeader(
                    title: "Edit Profile",
                    trailingTitle: "Save",
                    isTrailingBusy: isSaving,
                    onBack: { dismiss() },
                    onTrailing: { saveProfile() }
                )
                .disabled(isSaving)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        avatarPicker
                        identitySection
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .skylineScrollEdges()
            }

            if isSaving {
                savingOverlay
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isSaving)
        .onAppear {
            if let user = authService.authenticationState.user {
                displayName = user.displayName
                email = user.email ?? ""

                // Load existing profile image from CloudKit if available
                Task {
                    do {
                        if let image = try await CloudKitService.shared.fetchUserProfileImage(userId: user.id) {
                            await MainActor.run {
                                profileImage = image
                            }
                        }
                    } catch {
                        print("❌ Failed to fetch profile image from CloudKit: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingImageCropper) {
            if let image = imageForCropping {
                CircularImageCropperView(image: image) { croppedImage in
                    profileImage = croppedImage
                }
                .environmentObject(themeManager)
            }
        }
    }

    // MARK: - Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                cameraBadge
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Profile photo"))
        .accessibilityHint(Text("Choose a new photo"))
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    imageForCropping = image
                    showingImageCropper = true
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let theme = themeManager.currentTheme

        if let profileImage = profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(theme.colors.border, lineWidth: 1))
        } else {
            // Initials used to be white on a `primary` disc. `primary` is a LIGHT
            // ink in the dark theme (0x4DA3FF), so that measured 2.62:1 — the worst
            // contrast in the app. Inverting it — `primary` ink on a `surface` disc
            // inside a `primary` ring — reads at 5.9:1 in light and 7.3:1 in dark,
            // and keeps the accent doing the identifying.
            Circle()
                .fill(theme.colors.surface)
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Text(authService.authenticationState.user?.initials ?? "SU")
                        .appFont(.title, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.primary)
                        .padding(AppSpacing.md)
                )
                .overlay(Circle().stroke(theme.colors.primary, lineWidth: 2))
        }
    }

    private var cameraBadge: some View {
        let theme = themeManager.currentTheme

        // Opaque, and ringed in the page colour so it cuts cleanly out of whatever
        // photo sits behind it — a photograph has no theme to borrow contrast from.
        return Image(systemName: "camera.fill")
            .font(AppTypography.mono(.caption, weight: .semibold))
            .foregroundStyle(theme.colors.primary)
            .frame(width: badgeSize, height: badgeSize)
            .background(Circle().fill(theme.colors.surface))
            .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
            .accessibilityHidden(true)
    }

    // MARK: - Fields

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Identity")

            FormField(
                title: "Name",
                text: $displayName,
                placeholder: "Your name",
                icon: "person"
            )

            // Read-only, and it says so structurally: a `background` fill instead of
            // a `surface` one, so the field recedes to the page rather than
            // pretending to be a slot you could type into.
            FormReadOnlyRow(
                title: "Email",
                value: email.isEmpty ? "No email" : email,
                icon: "envelope"
            )
        }
    }

    // MARK: - Saving Overlay

    private var savingOverlay: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            theme.colors.scrim
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.colors.primary)

                Text("Saving…")
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
            }
            .padding(AppSpacing.xl)
            .skylineGlassCard(theme: theme)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Saving your profile"))
    }

    private func saveProfile() {
        guard let user = authService.authenticationState.user else { return }

        isSaving = true

        Task {
            // Save profile image if one was selected
            var profileImagePath: String? = user.profileImagePath
            if let image = profileImage {
                do {
                    let recordName = try await CloudKitService.shared.saveUserProfileImage(image, userId: user.id)
                    profileImagePath = recordName
                    print("✅ Profile image saved to CloudKit: \(recordName)")
                } catch {
                    print("❌ Failed to save profile image to CloudKit: \(error)")
                    // Keep existing profileImagePath on error
                }
            }

            // Create updated user with new name and profile image
            let updatedUser = User(
                id: user.id,
                email: user.email,
                fullName: displayName,
                firstName: displayName.components(separatedBy: " ").first,
                lastName: displayName.components(separatedBy: " ").count > 1 ? displayName.components(separatedBy: " ").last : nil,
                isEmailVerified: user.isEmailVerified,
                createdAt: user.createdAt,
                lastLoginAt: Date(),
                profileImagePath: profileImagePath
            )

            await MainActor.run {
                authService.saveUser(updatedUser)
                authService.authenticationState = .authenticated(updatedUser)
                isSaving = false
                dismiss()
            }
        }
    }
}

#Preview {
    EditProfileView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthenticationService.shared)
}
