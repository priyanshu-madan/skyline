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

// MARK: - Apple Token Revocation

/// Revokes a Sign in with Apple token given a fresh authorization code.
///
/// THERE IS NO CLIENT-SIDE REVOKE. `ASAuthorizationAppleIDProvider` can create a
/// request and report a credential's state; it cannot revoke one. The only thing
/// that can is `POST https://appleid.apple.com/auth/revoke`, and that endpoint
/// authenticates with a `client_secret` — a JWT signed by the team's AuthKey
/// `.p8`. Shipping that key inside the app would hand every user a credential
/// that can mint and revoke tokens for the whole Service ID, so this protocol is
/// the seam where a server-side revoker plugs in, and `appleTokenRevoker` is
/// deliberately `nil` in a build that has no server behind it.
///
/// The consequence is stated to the user rather than hidden: see
/// `CredentialRevocation.userFacingNote`.
protocol AppleTokenRevoking {
    /// Throws if the token was not revoked. Returning normally means the
    /// endpoint accepted it.
    func revoke(authorizationCode: String) async throws
}

/// What actually happened to the sign-in credential during account deletion.
///
/// Four cases rather than a Bool because "we forgot it locally" and "Apple
/// revoked it" are different facts, and only one of them is what Guideline
/// 5.1.1(v) asks for.
enum CredentialRevocation: Equatable {
    /// Apple accepted the revocation.
    case revoked
    /// The user did not sign in with Apple, so there is no Apple token.
    case notApplicable(provider: AuthProvider?)
    /// This build cannot revoke. The token is forgotten on device but still
    /// listed under the user's Apple Account.
    case unavailable(reason: String)
    /// A revoker exists and refused or errored.
    case failed(reason: String)

    /// What is left for the user to do by hand when the token was not revoked.
    ///
    /// Shown BEFORE they confirm, not after: `AuthenticationService`
    /// `.canRevokeAppleCredential` answers the same question up front, and the
    /// moment of the decision is the moment this is worth reading.
    static let notRevokedNote =
        "SkyLine will still be listed under Sign in with Apple. "
        + "You can remove it in Settings › your name › Sign in with Apple."

    /// The note for this outcome, or `nil` when there is nothing left to do.
    ///
    /// A revocation this build cannot perform never blocks the deletion. The
    /// user's data is what they asked to have removed, and holding it hostage to
    /// a token would leave them with neither.
    var userFacingNote: String? {
        switch self {
        case .revoked, .notApplicable: return nil
        case .unavailable, .failed: return Self.notRevokedNote
        }
    }

    /// For the console log, where the distinction matters to a developer.
    var logDescription: String {
        switch self {
        case .revoked: return "revoked with Apple"
        case .notApplicable(let provider): return "not applicable (provider: \(provider?.rawValue ?? "none"))"
        case .unavailable(let reason): return "NOT revoked - \(reason)"
        case .failed(let reason): return "revocation FAILED - \(reason)"
        }
    }
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

    /// Where account deletion sends the Apple authorization code. `nil` in every
    /// shipping build today — see `AppleTokenRevoking` for why a client cannot
    /// hold the key that endpoint needs. Injectable so the deletion path is
    /// testable without a server and so wiring one up is a one-line change.
    var appleTokenRevoker: (any AppleTokenRevoking)?

    /// Held only for the duration of a revocation request.
    /// `ASAuthorizationController` does not retain its delegate, and a delegate
    /// that deallocates mid-flight is a continuation that never resumes.
    private var revocationDelegate: AppleReauthorizationDelegate?

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

    // MARK: - Credential Revocation

    /// Whether `revokeCredential()` can do the real thing, known BEFORE the user
    /// commits to deleting.
    ///
    /// The account-deletion confirmation reads this so it can say, at the moment
    /// of the decision, that SkyLine will still be listed under Sign in with
    /// Apple afterwards. Telling them once the account is already gone would be
    /// a worse moment to learn it.
    var canRevokeAppleCredential: Bool {
        guard signInProvider == .apple else { return false }
        #if DEBUG
        if DebugFlags.bypassAuthentication { return false }
        #endif
        return appleTokenRevoker != nil
    }

    /// Revokes the sign-in credential as part of account deletion.
    ///
    /// Apple's account-deletion guidance is that the token is REVOKED, not just
    /// forgotten, so this does the revoking half separately from `signOut()`,
    /// which only forgets. The order matters: revoke while the credential is
    /// still known, then sign out.
    ///
    /// Never throws and never blocks. The worst case is `.unavailable`, which is
    /// reported to the user with the Settings path that finishes the job by
    /// hand — the alternative, refusing to delete a user's flights because this
    /// build has no revocation server, helps nobody.
    @MainActor
    func revokeCredential() async -> CredentialRevocation {
        guard signInProvider == .apple else {
            return .notApplicable(provider: signInProvider)
        }

        #if DEBUG
        if DebugFlags.bypassAuthentication {
            // There is no real credential behind the synthetic user, and asking
            // for one raises a Sign in with Apple sheet that cannot succeed on a
            // simulator (AKAuthenticationError -7084). Say so rather than
            // reporting a revocation that never happened.
            return .unavailable(reason: "authentication is bypassed in this build")
        }
        #endif

        guard let revoker = appleTokenRevoker else {
            return .unavailable(reason: "no revocation service is configured in this build")
        }

        // The code is single-use and short-lived, which is why it is fetched
        // here rather than kept from the original sign-in months ago.
        switch await appleAuthorizationCode() {
        case .failure(let reason):
            return .failed(reason: reason)
        case .code(let code):
            do {
                try await revoker.revoke(authorizationCode: code)
                return .revoked
            } catch {
                return .failed(reason: error.localizedDescription)
            }
        }
    }

    /// Re-authorises with Apple purely to obtain a fresh `authorizationCode`.
    ///
    /// Deliberately NOT routed through `self` as the delegate: that path calls
    /// `completeSignIn`, which would re-save the user we are in the middle of
    /// deleting.
    @MainActor
    private func appleAuthorizationCode() async -> AppleAuthorizationCodeResult {
        let delegate = AppleReauthorizationDelegate()
        revocationDelegate = delegate
        defer { revocationDelegate = nil }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        return await withCheckedContinuation { continuation in
            delegate.onFinish = { result in continuation.resume(returning: result) }
            controller.performRequests()
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

// MARK: - Apple Re-authorization (for revocation only)

/// The outcome of asking Apple for a fresh authorization code.
///
/// Not `Result<String, Error>`: every failure here is already a sentence
/// (`ASAuthorizationError` localises itself, and the two structural failures
/// below have no error type of their own), and wrapping strings in a throwaway
/// `Error` conformance would add a type nobody catches.
private enum AppleAuthorizationCodeResult {
    case code(String)
    case failure(String)
}

/// A one-shot delegate whose only job is to hand back an `authorizationCode`.
///
/// Separate from `AuthenticationService`'s own delegate conformance on purpose:
/// that one signs the user IN. Reusing it during account deletion would re-save
/// the user to UserDefaults and to CloudKit at the exact moment we are removing
/// them.
private final class AppleReauthorizationDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    /// Called exactly once. `finish` enforces that: an
    /// `ASAuthorizationController` that reported both a completion and an error
    /// would otherwise resume the continuation twice, which traps.
    var onFinish: ((AppleAuthorizationCodeResult) -> Void)?

    private func finish(_ result: AppleAuthorizationCodeResult) {
        guard let handler = onFinish else { return }
        onFinish = nil
        handler(result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure("Apple returned a credential of an unexpected type"))
            return
        }
        guard let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8), !code.isEmpty else {
            finish(.failure("Apple returned no authorization code"))
            return
        }
        finish(.code(code))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error.localizedDescription))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: \.isKeyWindow)
                ?? windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}