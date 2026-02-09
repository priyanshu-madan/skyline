//
//  EditProfileView.swift
//  SkyLine
//
//  View for editing user profile information
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingImageCropper = false
    @State private var imageForCropping: UIImage?
    @State private var isSaving = false

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
                    .disabled(isSaving)

                    Spacer()

                    Text("Edit Profile")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))

                    Spacer()

                    Button {
                        saveProfile()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        } else {
                            Text("Save")
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                    }
                    .frame(width: 60)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 20) {
                        // Profile Picture with Photo Picker
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let profileImage = profileImage {
                                    // Display uploaded image
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                } else {
                                    // Display initials
                                    Circle()
                                        .fill(themeManager.currentTheme.colors.primary)
                                        .frame(width: 96, height: 96)
                                        .overlay(
                                            Text(authService.authenticationState.user?.initials ?? "SU")
                                                .font(.system(size: 40, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white)
                                        )
                                }

                                // Camera icon badge
                                ZStack {
                                    Circle()
                                        .fill(themeManager.currentTheme.colors.primary)
                                        .frame(width: 32, height: 32)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 2, y: 2)
                            }
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    imageForCropping = image
                                    showingImageCropper = true
                                }
                            }
                        }

                        // Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                            TextField("Your name", text: $displayName)
                                .font(.system(size: 17, design: .monospaced))
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

                        // Email Field (Read-only)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                            Text(email.isEmpty ? "No email" : email)
                                .font(.system(size: 17, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(themeManager.currentTheme.colors.surface.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Loading overlay
            if isSaving {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text("Saving...")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(themeManager.currentTheme.colors.surface.opacity(0.95))
                )
            }
        }
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
