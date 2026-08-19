//
//  DebugFlags.swift
//  SkyLine
//
//  Build-time switches that only exist in DEBUG builds. Nothing in this file
//  is compiled into a Release build.
//

import Foundation

#if DEBUG

/// Development-only switches.
///
/// These are deliberately plain constants rather than launch arguments or
/// UserDefaults so that flipping one is a single visible edit in source, and
/// so a stale setting can never survive in a simulator's preferences and
/// quietly change behaviour weeks later.
enum DebugFlags {

    /// Skips Sign in with Apple and boots straight into the app as
    /// `User.debugUser`.
    ///
    /// Sign in with Apple cannot complete against a simulated Apple ID -
    /// `ASAuthorizationAppleIDProvider.getCredentialState` fails with
    /// `AKAuthenticationError -7084` - so every simulator relaunch otherwise
    /// costs a real sign-in on a real device. Set this to `false` to exercise
    /// the genuine sign-in flow.
    ///
    /// This has no effect on Release builds: the whole file is behind `#if DEBUG`.
    static let bypassAuthentication = true

    /// Prints a banner at launch when any flag above is active, so a bypassed
    /// build is never mistaken for a real one while reading the console.
    static func announceIfActive() {
        guard bypassAuthentication else { return }
        print("""

        ┌──────────────────────────────────────────────────────────┐
        │  DEBUG BUILD - AUTHENTICATION BYPASSED                    │
        │  Signed in as a synthetic user. Real Sign in with Apple   │
        │  is not being exercised. DebugFlags.bypassAuthentication  │
        └──────────────────────────────────────────────────────────┘

        """)
    }
}

extension User {
    /// Stable synthetic user for bypassed builds.
    ///
    /// The id is fixed so that CloudKit records created across runs belong to
    /// one consistent identity rather than accumulating a new orphan per launch.
    static let debugUser = User(
        id: "debug.user.skyline.local",
        email: "debug@skyline.local",
        fullName: "Debug User",
        firstName: "Debug",
        lastName: "User",
        isEmailVerified: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastLoginAt: Date(),
        profileImagePath: nil
    )
}

#endif
