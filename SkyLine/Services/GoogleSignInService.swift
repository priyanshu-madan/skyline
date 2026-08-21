//
//  GoogleSignInService.swift
//  SkyLine
//
//  Sign in with Google, implemented directly against Google's OAuth 2.0
//  endpoints with PKCE. No GoogleSignIn SDK, no SPM dependency.
//
//  WHY NO SDK: the whole flow is one authorization URL, one ASWebAuthenticationSession,
//  one form-encoded POST and one base64url decode. The SDK would add a binary
//  dependency, its own keychain usage, its own presentation plumbing and its own
//  release cadence to buy roughly the 250 lines below.
//
//  THE FLOW (RFC 7636 "PKCE", OpenID Connect):
//    1. Generate a random `code_verifier`; its SHA-256, base64url encoded, is the
//       `code_challenge`. The challenge goes out over the (observable) authorization
//       URL; the verifier never leaves the device until the token POST.
//    2. Open accounts.google.com in ASWebAuthenticationSession. The session runs in
//       Safari's process, so SkyLine never sees the user's Google password — that is
//       the entire point of using it instead of an in-app WKWebView.
//    3. Google redirects to our reversed-client-ID scheme with `code` and `state`.
//    4. POST the code + verifier to oauth2.googleapis.com/token.
//
//  NO CLIENT SECRET. An iOS app is a "public client" (RFC 8252 §8.5): anything
//  shipped in the bundle is readable by anyone with the .ipa, so a secret embedded
//  here would be a published secret. PKCE is what replaces it. If a Google Cloud
//  console page ever offers you a secret for this client, you have created the
//  wrong client type — see SkyLine/GOOGLE_SIGNIN_SETUP.md.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

// MARK: - Configuration

/// The two pieces of per-project setup that cannot be checked into the repo,
/// both read from Info.plist at launch.
///
/// There is deliberately no fallback, no default and no baked-in client ID. A
/// missing client ID is a build-configuration fact, and the UI is expected to
/// present it as one rather than discovering it at the moment the user taps.
struct GoogleSignInConfiguration: Equatable {

    /// e.g. `123456789012-abcdefg.apps.googleusercontent.com`
    let clientID: String

    /// e.g. `com.googleusercontent.apps.123456789012-abcdefg`
    /// Google issues this as the "reversed client ID"; it is literally the client
    /// ID's dot-separated components in reverse order, and it is both the custom
    /// URL scheme and the prefix of the redirect URI.
    let reversedClientID: String

    /// RFC 8252 private-use URI scheme redirect. The path segment is arbitrary but
    /// must match byte-for-byte between the authorization request and the token
    /// request, so it lives here rather than being spelled out at two call sites.
    var redirectURI: String { "\(reversedClientID):/oauth2redirect" }

    /// What ASWebAuthenticationSession watches for to know the flow finished.
    var callbackURLScheme: String { reversedClientID }

    static let infoPlistKey = "GIDClientID"
    static let clientIDSuffix = ".apps.googleusercontent.com"

    // MARK: Problems

    /// Why Google sign-in is not available in this build. Each case carries copy
    /// the UI can show verbatim — the button must explain itself while disabled,
    /// not fail at tap time.
    enum Problem: Equatable {
        case keyMissing
        case placeholderValue(String)
        case malformedClientID(String)
        case urlSchemeNotRegistered(expected: String)

        var explanation: String {
            switch self {
            case .keyMissing:
                return "Google sign-in isn't set up in this build — Info.plist has no \(GoogleSignInConfiguration.infoPlistKey) key."
            case .placeholderValue:
                return "Google sign-in isn't set up in this build — \(GoogleSignInConfiguration.infoPlistKey) is still a placeholder."
            case .malformedClientID:
                return "Google sign-in isn't set up in this build — \(GoogleSignInConfiguration.infoPlistKey) doesn't look like a Google client ID."
            case .urlSchemeNotRegistered(let expected):
                return "Google sign-in isn't set up in this build — the URL scheme \(expected) is missing from Info.plist."
            }
        }

        /// The one-line pointer at the fix. Shown under the disabled button so a
        /// developer picking the build up knows where to go without reading source.
        var remedy: String {
            "See SkyLine/GOOGLE_SIGNIN_SETUP.md"
        }
    }

    // MARK: Loading

    /// Reads and validates the configuration. Never traps, never guesses.
    static func load(from bundle: Bundle = .main) -> Result<GoogleSignInConfiguration, Problem> {
        let raw = (bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !raw.isEmpty else { return .failure(.keyMissing) }
        guard !isPlaceholder(raw) else { return .failure(.placeholderValue(raw)) }

        guard raw.hasSuffix(clientIDSuffix), raw.count > clientIDSuffix.count else {
            return .failure(.malformedClientID(raw))
        }

        let reversed = raw.split(separator: ".").reversed().joined(separator: ".")

        guard registeredURLSchemes(in: bundle).contains(where: { $0.caseInsensitiveCompare(reversed) == .orderedSame }) else {
            // Without the scheme registered, ASWebAuthenticationSession would open
            // Google, take the user through a real sign-in, and then strand them:
            // iOS has nowhere to deliver the redirect. Catching it up front is the
            // difference between a disabled button and a dead end.
            return .failure(.urlSchemeNotRegistered(expected: reversed))
        }

        return .success(GoogleSignInConfiguration(clientID: raw, reversedClientID: reversed))
    }

    /// Recognises the values people leave behind in a checked-in Info.plist.
    /// The repo's own convention is `YOUR_..._HERE` (see MISTRAL_API_KEY).
    private static func isPlaceholder(_ value: String) -> Bool {
        let upper = value.uppercased()
        return upper.contains("YOUR_")
            || upper.contains("PLACEHOLDER")
            || upper.contains("REPLACE")
            || upper.contains("XXXX")
            || upper.contains("TODO")
    }

    private static func registeredURLSchemes(in bundle: Bundle) -> [String] {
        guard let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }
}

// MARK: - Errors

enum GoogleSignInError: LocalizedError {
    case notConfigured(GoogleSignInConfiguration.Problem)
    case cancelled
    case sessionFailedToStart
    case authorizationFailed(String)
    case invalidCallback
    case stateMismatch
    case randomGenerationFailed
    case tokenRequestFailed(String)
    case tokenResponseInvalid
    case idTokenMalformed
    case idTokenRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let problem):
            return problem.explanation
        case .cancelled:
            return "Sign-in was cancelled."
        case .sessionFailedToStart:
            return "Couldn't open the Google sign-in page."
        case .authorizationFailed(let detail):
            return "Google sign-in failed: \(detail)"
        case .invalidCallback:
            return "Google returned an unreadable response."
        case .stateMismatch:
            // Either a stale redirect or an injection attempt. Both mean: stop.
            return "Google sign-in failed a security check. Please try again."
        case .randomGenerationFailed:
            return "Couldn't start a secure sign-in on this device."
        case .tokenRequestFailed(let detail):
            return "Couldn't complete Google sign-in: \(detail)"
        case .tokenResponseInvalid:
            return "Google's response was missing sign-in details."
        case .idTokenMalformed:
            return "Google's identity token couldn't be read."
        case .idTokenRejected(let detail):
            return "Google's identity token was rejected: \(detail)"
        }
    }
}

// MARK: - Result

struct GoogleSignInResult {
    let user: User
    let idToken: String
    let accessToken: String
}

// MARK: - Service

@MainActor
final class GoogleSignInService: NSObject {

    static let shared = GoogleSignInService()

    /// Resolved once at launch. Info.plist cannot change while the app runs, so
    /// there is nothing to observe and no reason to re-read it per tap.
    let configuration: Result<GoogleSignInConfiguration, GoogleSignInConfiguration.Problem>

    /// Held only so the system doesn't deallocate the session mid-flow.
    private var activeSession: ASWebAuthenticationSession?

    init(bundle: Bundle = .main) {
        self.configuration = GoogleSignInConfiguration.load(from: bundle)
        super.init()

        if case .failure(let problem) = configuration {
            print("⚠️ GoogleSignIn: \(problem.explanation) \(problem.remedy)")
        }
    }

    var isConfigured: Bool {
        if case .success = configuration { return true }
        return false
    }

    /// Non-nil exactly when `isConfigured` is false. Drives the disabled button's
    /// explanatory copy.
    var unavailableReason: GoogleSignInConfiguration.Problem? {
        if case .failure(let problem) = configuration { return problem }
        return nil
    }

    // MARK: Sign In

    /// Runs the full authorization-code + PKCE flow and returns a `User`.
    /// Throws `GoogleSignInError.cancelled` when the user dismisses the sheet —
    /// callers should treat that as "nothing happened", not as an error to show.
    func signIn(prefersEphemeralSession: Bool = false) async throws -> GoogleSignInResult {
        guard case .success(let config) = configuration else {
            throw GoogleSignInError.notConfigured(unavailableReason ?? .keyMissing)
        }

        let verifier = try Self.randomURLSafeToken(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = try Self.randomURLSafeToken(byteCount: 16)
        let nonce = try Self.randomURLSafeToken(byteCount: 16)

        let authorizationURL = try Self.authorizationURL(
            config: config,
            codeChallenge: challenge,
            state: state,
            nonce: nonce
        )

        let callbackURL = try await presentAuthorization(
            url: authorizationURL,
            callbackScheme: config.callbackURLScheme,
            ephemeral: prefersEphemeralSession
        )

        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let tokens = try await Self.exchange(code: code, verifier: verifier, config: config)

        let claims = try Self.decodeIDTokenPayload(tokens.idToken)
        try Self.validate(claims: claims, clientID: config.clientID, expectedNonce: nonce)

        return GoogleSignInResult(
            user: claims.toUser(),
            idToken: tokens.idToken,
            accessToken: tokens.accessToken
        )
    }

    // MARK: Step 1 — PKCE

    /// 32 bytes of CSPRNG output, base64url encoded to 43 characters — inside
    /// RFC 7636's 43...128 character window with no padding to strip.
    private static func randomURLSafeToken(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw GoogleSignInError.randomGenerationFailed
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        // S256: BASE64URL(SHA256(ASCII(verifier))). The plain method exists in the
        // spec and must not be used — it makes the challenge and the verifier the
        // same value, which is no protection at all.
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    // MARK: Step 2 — Authorization request

    private static func authorizationURL(
        config: GoogleSignInConfiguration,
        codeChallenge: String,
        state: String,
        nonce: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            // Users who have several Google accounts otherwise get silently
            // dropped into whichever one Safari happens to hold.
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let url = components?.url else {
            throw GoogleSignInError.authorizationFailed("couldn't build the authorization URL")
        }
        return url
    }

    private func presentAuthorization(
        url: URL,
        callbackScheme: String,
        ephemeral: Bool
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let once = OneShot()

            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { callbackURL, error in
                guard once.claim() else { return }

                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: GoogleSignInError.cancelled)
                    } else {
                        continuation.resume(
                            throwing: GoogleSignInError.authorizationFailed(error.localizedDescription)
                        )
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            // Left false on purpose: an ephemeral session hides the user's existing
            // Google login, so everyone would have to type a password even when
            // Safari already knows them.
            session.prefersEphemeralWebBrowserSession = ephemeral

            activeSession = session

            if !session.start(), once.claim() {
                continuation.resume(throwing: GoogleSignInError.sessionFailedToStart)
            }
        }
    }

    // MARK: Step 3 — Read the redirect

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleSignInError.invalidCallback
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let oauthError = value("error") {
            if oauthError == "access_denied" { throw GoogleSignInError.cancelled }
            throw GoogleSignInError.authorizationFailed(value("error_description") ?? oauthError)
        }

        // Constant-time comparison is overkill here (state is not a secret that
        // leaks by timing), but the check itself is not optional: it is what stops
        // an attacker-supplied redirect being accepted as ours.
        guard let state = value("state"), state == expectedState else {
            throw GoogleSignInError.stateMismatch
        }

        guard let code = value("code"), !code.isEmpty else {
            throw GoogleSignInError.invalidCallback
        }
        return code
    }

    // MARK: Step 4 — Token exchange

    private struct TokenResponse: Decodable {
        let accessToken: String
        let idToken: String
        let expiresIn: Int?
        let tokenType: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }

    private struct TokenErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private static func exchange(
        code: String,
        verifier: String,
        config: GoogleSignInConfiguration
    ) async throws -> TokenResponse {
        guard let endpoint = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleSignInError.tokenRequestFailed("bad token endpoint")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
            // Deliberately no `client_secret` — see the file header.
        ]).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GoogleSignInError.tokenRequestFailed(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(TokenErrorResponse.self, from: data))
                .flatMap { $0.errorDescription ?? $0.error }
            throw GoogleSignInError.tokenRequestFailed(detail ?? "HTTP \(status)")
        }

        guard let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleSignInError.tokenResponseInvalid
        }
        return tokens
    }

    /// `application/x-www-form-urlencoded`: percent-encode everything outside the
    /// unreserved set. `URLComponents` is not used here because it leaves `+` and
    /// `&` alone, and an authorization code containing either would silently
    /// corrupt the body.
    private static func formEncode(_ parameters: [String: String]) -> String {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")

        return parameters
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    // MARK: Step 5 — Identity

    /// The claims SkyLine needs out of Google's `id_token`.
    struct IDTokenClaims {
        let subject: String
        let issuer: String
        let audience: String
        let expiresAt: Date
        let nonce: String?
        let email: String?
        let emailVerified: Bool
        let name: String?
        let givenName: String?
        let familyName: String?
    }

    /// Decodes the JWT payload WITHOUT verifying its signature.
    ///
    /// THIS IS SAFE **ONLY** IN THIS EXACT SITUATION, AND NOWHERE ELSE.
    /// The token was not handed to us by a client, read from a header, pulled from
    /// storage or passed between processes. We made a direct TLS request to
    /// `oauth2.googleapis.com` moments ago and this is the body that came back, so
    /// TLS has already authenticated the issuer — a signature check would be
    /// re-proving what the transport just proved.
    ///
    /// The moment a token arrives from ANY other direction — a server accepting an
    /// id_token from an app, a cached token being rehydrated, a token forwarded by
    /// another component — this function is the wrong tool. Verify the RS256
    /// signature against Google's JWKS (https://www.googleapis.com/oauth2/v3/certs)
    /// instead. Do not copy this pattern; copy the warning with it.
    private static func decodeIDTokenPayload(_ idToken: String) throws -> IDTokenClaims {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { throw GoogleSignInError.idTokenMalformed }

        guard let payloadData = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw GoogleSignInError.idTokenMalformed
        }

        guard let subject = json["sub"] as? String, !subject.isEmpty,
              let issuer = json["iss"] as? String,
              let audience = json["aud"] as? String,
              let exp = (json["exp"] as? NSNumber)?.doubleValue else {
            throw GoogleSignInError.idTokenMalformed
        }

        // `email_verified` has shipped as both a JSON bool and the strings
        // "true"/"false" across Google's endpoints over the years. Accept both
        // rather than silently treating a verified address as unverified.
        let emailVerified: Bool
        if let flag = json["email_verified"] as? Bool {
            emailVerified = flag
        } else if let text = json["email_verified"] as? String {
            emailVerified = (text as NSString).boolValue
        } else {
            emailVerified = false
        }

        return IDTokenClaims(
            subject: subject,
            issuer: issuer,
            audience: audience,
            expiresAt: Date(timeIntervalSince1970: exp),
            nonce: json["nonce"] as? String,
            email: json["email"] as? String,
            emailVerified: emailVerified,
            name: (json["name"] as? String)?.trimmingCharacters(in: .whitespaces),
            givenName: json["given_name"] as? String,
            familyName: json["family_name"] as? String
        )
    }

    /// Cheap sanity checks on claims we already trust via TLS. They cost nothing
    /// and they catch the configuration mistakes (wrong client ID, replayed
    /// response) that a signature check would not surface as clearly anyway.
    private static func validate(claims: IDTokenClaims, clientID: String, expectedNonce: String) throws {
        let acceptedIssuers: Set<String> = ["https://accounts.google.com", "accounts.google.com"]
        guard acceptedIssuers.contains(claims.issuer) else {
            throw GoogleSignInError.idTokenRejected("unexpected issuer")
        }
        guard claims.audience == clientID else {
            throw GoogleSignInError.idTokenRejected("token was issued for a different app")
        }
        // 60s of slack for device clock drift.
        guard claims.expiresAt.timeIntervalSinceNow > -60 else {
            throw GoogleSignInError.idTokenRejected("token already expired")
        }
        guard claims.nonce == expectedNonce else {
            throw GoogleSignInError.idTokenRejected("nonce mismatch")
        }
    }
}

// MARK: - Claims -> User

extension GoogleSignInService.IDTokenClaims {
    /// Maps Google's claims onto the app's existing `User`.
    ///
    /// `id` is Google's `sub`: stable for the lifetime of the account, and — unlike
    /// the email — never reassigned. Never key anything off the email address.
    ///
    /// `profileImagePath` stays nil even though Google supplies a `picture` URL.
    /// That field holds a CloudKit record name (see EditProfileView, which writes
    /// the result of `saveUserProfileImage`), not a remote URL; putting an https
    /// string in it would make the profile screen ask CloudKit for a record that
    /// does not exist.
    func toUser() -> User {
        User(
            id: subject,
            email: email,
            fullName: name?.isEmpty == false ? name : nil,
            firstName: givenName,
            lastName: familyName,
            isEmailVerified: emailVerified,
            createdAt: Date(),
            lastLoginAt: Date(),
            profileImagePath: nil
        )
    }
}

// MARK: - Presentation Anchor

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // Prefer the foreground-active scene: `connectedScenes.first` is unordered
        // and can hand back a background scene, which anchors the sheet to a window
        // the user cannot see.
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
            ?? scenes.first?.keyWindow

        return window ?? ASPresentationAnchor()
    }
}

// MARK: - Helpers

/// Guarantees a continuation is resumed exactly once.
///
/// `ASWebAuthenticationSession`'s completion handler and a failed `start()` are two
/// independent paths to the same continuation; resuming twice is a hard crash.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private extension Data {
    /// base64url (RFC 4648 §5): `+/` become `-_`, padding is dropped.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
