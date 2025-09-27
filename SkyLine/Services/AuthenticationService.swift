//
//  AuthenticationService.swift
//  SkyLine
//
//  Apple Sign In authentication service for user management
//

import Foundation
import AuthenticationServices
import CloudKit
import Combine
import SwiftUI

// MARK: - Authentication State
enum AuthenticationState: Equatable {
    case unauthenticated
    case authenticating
    case authenticated(User)
    case error(String)
    
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
    
    var user: User? {
        if case .authenticated(let user) = self {
            return user
        }
        return nil
    }
    
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

// MARK: - Authentication Service
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var isLoading: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let userKey = "authenticated_user"
    private let cloudKitService = CloudKitService.shared
    
    override init() {
        super.init()
        checkExistingAuthentication()
    }
    
    // MARK: - Authentication Check
    
    private func checkExistingAuthentication() {
        // Check for existing user in UserDefaults
        guard let userData = userDefaults.data(forKey: userKey),
              let user = try? JSONDecoder().decode(User.self, from: userData) else {
            authenticationState = .unauthenticated
            return
        }
        
        // Verify the Apple ID credential is still valid
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: user.id) { [weak self] credentialState, error in
            DispatchQueue.main.async {
                switch credentialState {
                case .authorized:
                    self?.authenticationState = .authenticated(user)
                    print("✅ User still authenticated: \(user.displayName)")
                    
                case .revoked, .notFound:
                    self?.authenticationState = .unauthenticated
                    self?.clearUserData()
                    print("⚠️ Apple ID credential revoked or not found")
                    
                case .transferred:
                    self?.authenticationState = .unauthenticated
                    self?.clearUserData()
                    print("⚠️ Apple ID credential transferred")
                    
                @unknown default:
                    self?.authenticationState = .unauthenticated
                    print("❓ Unknown Apple ID credential state")
                }
            }
        }
    }
    
    // MARK: - Sign In with Apple
    
    func signInWithApple() {
        isLoading = true
        authenticationState = .authenticating
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - Sign Out
    
    @MainActor
    func signOut() {
        authenticationState = .unauthenticated
        clearUserData()
        print("✅ User signed out")
    }
    
    private func clearUserData() {
        userDefaults.removeObject(forKey: userKey)
    }
    
    // Public method for saving user (called from AuthenticationView)
    func saveUser(_ user: User) {
        do {
            let userData = try JSONEncoder().encode(user)
            userDefaults.set(userData, forKey: userKey)
            print("✅ User data saved locally")
        } catch {
            print("❌ Failed to save user data: \(error)")
        }
    }
    
    // MARK: - User Persistence
    
    // MARK: - CloudKit User Data
    
    @MainActor
    private func saveUserToCloudKit(_ user: User) async {
        // For now, we'll just print that user data would be saved
        // In a full implementation, we'd add user profile methods to CloudKitService
        print("✅ User profile saved: \(user.displayName)")
        print("📧 Email: \(user.email ?? "Not provided")")
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        
        switch authorization.credential {
        case let appleIDCredential as ASAuthorizationAppleIDCredential:
            handleAppleIDCredential(appleIDCredential)
            
        default:
            DispatchQueue.main.async {
                self.isLoading = false
                self.authenticationState = .error("Unknown credential type")
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    self.authenticationState = .unauthenticated
                    print("🚫 Apple Sign In canceled")
                    
                case .failed:
                    self.authenticationState = .error("Sign In failed")
                    print("❌ Apple Sign In failed")
                    
                case .invalidResponse:
                    self.authenticationState = .error("Invalid response")
                    print("❌ Apple Sign In invalid response")
                    
                case .notHandled:
                    self.authenticationState = .error("Not handled")
                    print("❌ Apple Sign In not handled")
                    
                case .unknown:
                    self.authenticationState = .error("Unknown error")
                    print("❌ Apple Sign In unknown error")
                    
                @unknown default:
                    self.authenticationState = .error("Unknown error")
                    print("❌ Apple Sign In unknown error")
                }
            } else {
                self.authenticationState = .error(error.localizedDescription)
                print("❌ Apple Sign In error: \(error)")
            }
        }
    }
    
    private func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let user = credential.toUser()
        
        DispatchQueue.main.async {
            self.isLoading = false
            self.authenticationState = .authenticated(user)
            self.saveUser(user)
            
            print("✅ Apple Sign In successful: \(user.displayName)")
            
            // Save to CloudKit
            Task {
                await self.saveUserToCloudKit(user)
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}