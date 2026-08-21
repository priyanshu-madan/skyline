//
//  AuthenticationService.swift
//  SkyLine
//
//  Sign-in for SkyLine: Sign in with Apple (native, delegate-driven) and Sign in
//  with Google (OAuth 2.0 + PKCE, see GoogleSignInService).
//
//  THE THING THAT IS NOT OBVIOUS: signing in here does NOT decide where the user's
//  data lives. Every place, visit and trip is written to the CloudKit PRIVATE
//  database, which is keyed to the DEVICE's iCloud account. Whoever this service
//  says is signed in is a display identity — a name, an avatar, an email on the
//  profile screen — and nothing more.
//
//  For Sign in with Apple the two happen to line up in practice: a device signed
//  in to an Apple ID normally has iCloud. For Sign in with Google they can come
//  apart completely, so `signInWithGoogle()` checks iCloud before letting anyone
//  in and hands the decision back to the user rather than accepting places it
//  cannot store. See `PendingSignIn`.
//

import Foundation
import AuthenticationServices
import CloudKit
import Combine
import SwiftUI

// MARK: - Auth Provider

/// Which sign-in produced the cached user.
///
/// This is persisted separately from `User` so that `User` — which is encoded into
/// UserDefaults and mirrored into CloudKit — keeps the exact shape it already has
/// on every device in the field.
enum AuthProvider: String, Codable {
    case apple
    case google

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }
}

// MARK: - Pending Sign In

/// A completed sign-in that is being held at the door because this device has no
/// iCloud account to store anything in.
///
/// Nothing is written and `authenticationState` stays `.unauthenticated` until the
/// user either accepts the limitation (`acceptPendingSignIn`) or backs out
/// (`discardPendingSignIn`). Letting them straight through would mean logging
/// places into a database that does not exist.
struct PendingSignIn: Identifiable, Equatable {
    let id = UUID()
    let user: User
    let provider: AuthProvider
}

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
    
    /// Set when a sign-in succeeded but the device has no iCloud account.
    /// The UI is expected to explain the consequences and call one of
    /// `acceptPendingSignIn()` / `discardPendingSignIn()`.
    @Published var pendingSignIn: PendingSignIn?

    /// Which provider the current (or cached) user signed in with.
    @Published private(set) var signInProvider: AuthProvider?

    private let userDefaults = UserDefaults.standard
    private let userKey = "authenticated_user"
    private let providerKey = "authenticated_user_provider"
    private let cloudKitService = CloudKitService.shared
    
    override init() {
        super.init()
        print("🔄 AuthService: Initializing AuthenticationService...")
        
        // Start with authenticating state while we check existing credentials
        authenticationState = .authenticating
        print("🔄 AuthService: Set initial state to .authenticating")
        
        checkExistingAuthentication()
    }
    
    // MARK: - Authentication Check
    
    private func checkExistingAuthentication() {
        #if DEBUG
        if DebugFlags.bypassAuthentication {
            DebugFlags.announceIfActive()
            let user = User.debugUser
            DispatchQueue.main.async {
                self.signInProvider = .apple
                self.authenticationState = .authenticated(user)
            }
            return
        }
        #endif

        print("🔍 AuthService: Checking existing authentication...")
        print("🔍 AuthService: UserDefaults key being checked: '\(userKey)'")
        
        // Debug: List all UserDefaults keys to see what's there
        let allKeys = userDefaults.dictionaryRepresentation().keys
        print("🔍 AuthService: All UserDefaults keys: \(Array(allKeys))")
        
        // Check for existing user in UserDefaults
        guard let userData = userDefaults.data(forKey: userKey) else {
            print("❌ AuthService: No user data found in UserDefaults for key '\(userKey)'")
            DispatchQueue.main.async {
                self.authenticationState = .unauthenticated
            }
            return
        }
        
        guard let user = try? JSONDecoder().decode(User.self, from: userData) else {
            print("❌ AuthService: Failed to decode user data")
            DispatchQueue.main.async {
                self.authenticationState = .unauthenticated
            }
            return
        }
        
        // Default to `.apple` when the key is absent: every user cached before
        // Google sign-in existed signed in with Apple, and treating them as Google
        // would skip the credential check they should still get.
        let storedProvider = userDefaults.string(forKey: providerKey)
            .flatMap(AuthProvider.init(rawValue:)) ?? .apple

        print("📱 AuthService: Found cached user: \(user.displayName) (ID: \(user.id)) via \(storedProvider.rawValue)")

        guard storedProvider == .apple else {
            // A Google user's id is Google's `sub`, which means nothing to
            // `ASAuthorizationAppleIDProvider` — it would answer `.notFound` and
            // this method would helpfully sign the user out on every launch.
            //
            // There is no equivalent silent check for Google: revalidating would
            // need a refresh token, and this app deliberately does not keep one
            // (it has no server, and a refresh token in UserDefaults is a
            // long-lived credential sitting in plaintext). The cached identity is
            // a display name and an avatar, not an authorisation to anything, so
            // trusting it until the user signs out is the proportionate call.
            DispatchQueue.main.async {
                self.signInProvider = storedProvider
                self.authenticationState = .authenticated(user)
            }
            return
        }

        // Verify the Apple ID credential is still valid
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: user.id) { [weak self] credentialState, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ AuthService: Error checking credential state: \(error)")
                    self.authenticationState = .unauthenticated
                    return
                }
                
                switch credentialState {
                case .authorized:
                    print("✅ AuthService: Apple ID credential still valid - auto-login successful")
                    self.signInProvider = .apple
                    self.authenticationState = .authenticated(user)
                    
                case .revoked:
                    print("⚠️ AuthService: Apple ID credential revoked")
                    self.authenticationState = .unauthenticated
                    self.clearUserData()
                    
                case .notFound:
                    print("⚠️ AuthService: Apple ID credential not found")
                    self.authenticationState = .unauthenticated
                    self.clearUserData()
                    
                case .transferred:
                    print("⚠️ AuthService: Apple ID credential transferred")
                    self.authenticationState = .unauthenticated
                    self.clearUserData()
                    
                @unknown default:
                    print("❓ AuthService: Unknown Apple ID credential state")
                    self.authenticationState = .unauthenticated
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
    
    // MARK: - Sign In with Google

    /// Runs the OAuth flow in `GoogleSignInService`, then checks whether this
    /// device can actually store anything before admitting the user.
    ///
    /// Cancellation is not an error: dismissing Google's sheet returns the UI to
    /// exactly where it was, with no alert.
    @MainActor
    func signInWithGoogle() async {
        guard GoogleSignInService.shared.isConfigured else {
            // Should be unreachable — the button is disabled when unconfigured —
            // but a silent no-op here would be the worst possible outcome.
            let problem = GoogleSignInService.shared.unavailableReason
            authenticationState = .error(problem?.explanation ?? "Google sign-in isn't available in this build.")
            return
        }

        // Deliberately NOT `.authenticating`: SkyLineApp swaps AuthenticationView
        // out for AppLoadingView in that state, which would tear down the view
        // that owns the iCloud-storage sheet while Google's browser sheet is up.
        // `isLoading` drives the in-place spinner instead. Resetting to
        // `.unauthenticated` also means a repeated identical failure still lands
        // as a state CHANGE, so the error alert fires on the second attempt too.
        isLoading = true
        authenticationState = .unauthenticated

        do {
            let result = try await GoogleSignInService.shared.signIn()

            // THE CAVEAT, ENFORCED. SkyLine persists to the CloudKit private
            // database, which belongs to the device's iCloud account. Signing in
            // with Google says nothing about whether that account exists, so ask
            // before we let anyone start logging places into nothing.
            let canStore = await cloudKitService.checkAccountStatus()
            isLoading = false

            if canStore {
                completeSignIn(user: result.user, provider: .google)
            } else {
                print("⚠️ AuthService: Google sign-in succeeded but iCloud is unavailable - holding at the storage gate")
                pendingSignIn = PendingSignIn(user: result.user, provider: .google)
                authenticationState = .unauthenticated
            }
        } catch GoogleSignInError.cancelled {
            isLoading = false
            authenticationState = .unauthenticated
            print("🚫 Google Sign In cancelled")
        } catch {
            isLoading = false
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            authenticationState = .error(message)
            print("❌ Google Sign In error: \(error)")
        }
    }

    // MARK: - Pending Sign In (no iCloud on this device)

    /// The user has read what will and will not work, and wants in anyway.
    @MainActor
    func acceptPendingSignIn() {
        guard let pending = pendingSignIn else { return }
        pendingSignIn = nil
        completeSignIn(user: pending.user, provider: pending.provider)
    }

    /// The user would rather go and set up iCloud first.
    @MainActor
    func discardPendingSignIn() {
        pendingSignIn = nil
        authenticationState = .unauthenticated
    }

    // MARK: - Completion

    @MainActor
    private func completeSignIn(user: User, provider: AuthProvider) {
        signInProvider = provider
        authenticationState = .authenticated(user)
        saveUser(user, provider: provider)

        print("✅ \(provider.displayName) Sign In successful: \(user.displayName)")

        Task {
            await saveUserToCloudKit(user)
        }
    }

    // MARK: - Sign Out
    
    @MainActor
    func signOut() {
        authenticationState = .unauthenticated
        pendingSignIn = nil
        signInProvider = nil
        clearUserData()
        print("✅ User signed out")
    }
    
    private func clearUserData() {
        userDefaults.removeObject(forKey: userKey)
        userDefaults.removeObject(forKey: providerKey)
        userDefaults.synchronize()
        print("🗑️ AuthService: User data cleared from UserDefaults")
    }
    
    /// Persists the user locally.
    ///
    /// `provider` is optional so existing callers that only edit the profile
    /// (EditProfileView) cannot accidentally erase how the user signed in.
    func saveUser(_ user: User, provider: AuthProvider? = nil) {
        if let provider {
            userDefaults.set(provider.rawValue, forKey: providerKey)
        }
        do {
            let userData = try JSONEncoder().encode(user)
            userDefaults.set(userData, forKey: userKey)
            userDefaults.synchronize() // Force immediate save
            print("✅ AuthService: User data saved locally - \(user.displayName) (ID: \(user.id))")
            print("💾 AuthService: UserDefaults key '\(userKey)' size: \(userData.count) bytes")
            
            // Verify the save worked by immediately trying to read it back
            if let verifyData = userDefaults.data(forKey: userKey),
               let verifyUser = try? JSONDecoder().decode(User.self, from: verifyData) {
                print("✅ AuthService: Verification successful - can read back user: \(verifyUser.displayName)")
            } else {
                print("❌ AuthService: Verification failed - cannot read back saved user data")
            }
        } catch {
            print("❌ AuthService: Failed to save user data: \(error)")
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

        Task { @MainActor in
            self.isLoading = false
            self.completeSignIn(user: user, provider: .apple)
        }

        // NOTE: the iCloud availability gate that `signInWithGoogle()` applies is
        // deliberately NOT applied here. The hazard is identical — a device with
        // no iCloud account cannot persist anything regardless of who signed in —
        // but adding the gate to the Apple path would newly block users who are
        // signing in successfully today, which is a behaviour change that belongs
        // in its own change with its own testing, not smuggled in beside a new
        // provider.
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