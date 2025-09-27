//
//  AuthenticationView.swift
//  SkyLine
//
//  Apple Sign In authentication interface
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingError = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        themeManager.currentTheme.colors.primary.opacity(0.1),
                        themeManager.currentTheme.colors.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // App Logo and Welcome
                    VStack(spacing: 24) {
                        // App Icon
                        ZStack {
                            Circle()
                                .fill(themeManager.currentTheme.colors.primary)
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "airplane")
                                .font(.system(size: 60, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .shadow(color: themeManager.currentTheme.colors.primary.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 12) {
                            Text("Welcome to SkyLine")
                                .font(AppTypography.titleLarge)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            
                            Text("Track your flights around the world")
                                .font(AppTypography.headline)
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    // Features List
                    VStack(spacing: 16) {
                        FeatureRow(
                            icon: "globe",
                            title: "3D Globe Visualization",
                            description: "See your flights on an interactive 3D globe"
                        )
                        
                        FeatureRow(
                            icon: "camera.viewfinder",
                            title: "Boarding Pass Scanner",
                            description: "Scan boarding passes from Apple Wallet"
                        )
                        
                        FeatureRow(
                            icon: "icloud.fill",
                            title: "iCloud Sync",
                            description: "Your flights sync across all your devices"
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Authentication Section
                    VStack(spacing: 20) {
                        if authService.isLoading {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                
                                Text("Signing in...")
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                            .padding(.vertical, 16)
                        } else {
                            // Apple Sign In Button
                            SignInWithAppleButton(
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                },
                                onCompletion: { result in
                                    handleSignInResult(result)
                                }
                            )
                            .signInWithAppleButtonStyle(
                                themeManager.currentTheme == .light ? .black : .white
                            )
                            .frame(height: 50)
                            .cornerRadius(8)
                            .padding(.horizontal, 20)
                        }
                        
                        // Privacy Notice
                        VStack(spacing: 8) {
                            Text("By signing in, you agree to our privacy practices")
                                .font(AppTypography.bodySmall)
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Your data is stored securely in your private iCloud")
                                .font(AppTypography.caption)
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
            }
        } message: {
            if let errorMessage = authService.authenticationState.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: authService.authenticationState) { state in
            if case .error = state {
                showingError = true
            }
        }
    }
    
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        authService.isLoading = true
        
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let user = appleIDCredential.toUser()
                authService.authenticationState = .authenticated(user)
                // User is saved automatically in the AuthenticationService
            }
            
        case .failure(let error):
            authService.authenticationState = .error(error.localizedDescription)
        }
        
        authService.isLoading = false
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.primary)
                .frame(width: 40, height: 40)
                .background(themeManager.currentTheme.colors.primary.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyBold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text(description)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthenticationService.shared)
}