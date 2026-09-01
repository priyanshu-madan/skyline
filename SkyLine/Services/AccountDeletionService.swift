//
//  AccountDeletionService.swift
//  SkyLine
//
//  In-app account deletion, required by App Store Review Guideline 5.1.1(v):
//  an app that supports account creation must let the user START deletion from
//  inside the app. SkyLine gates every screen behind Sign in with Apple, so
//  there is no version of this app that does not need it.
//
//  It is four steps in a fixed order, and the order is the whole design:
//
//   1. Delete the CloudKit records, via `AccountDataEraser` — the same engine
//      `DebugDataWipe` runs, so the honesty rules it learned the hard way apply
//      here too.
//   2. STOP if that did not come back clean. Nothing else happens: the local
//      caches are left alone (they include `authenticated_user`, so clearing
//      them would half sign the user out of an account that still exists), the
//      credential is not revoked, and the user is not signed out. They are told
//      what is still there and can try again.
//   3. Revoke the Sign in with Apple credential. Forgetting it is not revoking
//      it — see `AppleTokenRevoking`.
//   4. Sign out, which returns the app to the sign-in wall.
//
//  WHAT "SUCCESS" IS ALLOWED TO MEAN. `AccountDataEraser.EraseReport` models
//  partial failure on purpose, and this file's one job is not to flatten it.
//  A user told their account is gone who then signs back in and finds their
//  flights has been lied to, and the engine's own history is two clean summaries
//  printed over runs that left records behind.
//

import Foundation
import SwiftUI

/// Why a deletion did not happen, in the words the user reads.
struct AccountDeletionFailure: Identifiable, Equatable {
    let id = UUID()
    /// Short enough for an alert title. Never "Error".
    let title: String
    /// Names what is still there and what was left untouched.
    let message: String
}

enum AccountDeletionOutcome: Equatable {
    /// Every record type came back confirmed empty and the user is signed out.
    /// `credential` may still carry a note — the data is gone either way.
    case deleted(credential: CredentialRevocation)
    case failed(AccountDeletionFailure)
}

enum AccountDeletionService {

    /// Deletes the signed-in user's account. Never throws; the outcome is the
    /// whole story.
    @MainActor
    static func deleteAccount(using authService: AuthenticationService) async -> AccountDeletionOutcome {
        print("🗑️ AccountDeletion: starting - CloudKit records first")

        // `.onlyWhenCloudIsClean`: the local keys include the stored session, so
        // a failed sweep must leave them in place or the user has nothing left
        // to retry from.
        let report = await AccountDataEraser.eraseEverything(
            localState: .onlyWhenCloudIsClean,
            log: { print($0) })
        print(report.summary(label: "AccountDeletion"))

        if let problem = report.userFacingProblem {
            return .failed(AccountDeletionFailure(
                title: report.blockedReason == nil
                    ? "Your account wasn't deleted"
                    : "SkyLine couldn't reach iCloud",
                message: problem))
        }

        // Past this line the account really is empty, so everything that follows
        // is cleanup that must not be allowed to fail the deletion.
        resetInMemoryStores()

        let credential = await authService.revokeCredential()
        print("🗑️ AccountDeletion: credential \(credential.logDescription)")

        authService.signOut()
        print("🗑️ AccountDeletion: complete - \(report.deleted) CloudKit records deleted")

        return .deleted(credential: credential)
    }

    /// Empties the stores that are still holding the deleted data in memory.
    ///
    /// The engine clears the UserDefaults caches, but a live store that still
    /// holds the old rows writes them straight back — `DebugDataWipe`'s header
    /// says "run it on a fresh install" for exactly this reason, and an in-app
    /// deletion has no reinstall to hide behind.
    ///
    /// INCOMPLETE, KNOWINGLY. `PlaceStore` and `TripStore` are `@MainActor`
    /// singletons and reachable from here. `FlightStore` is neither: it is a
    /// `@StateObject` created in `SkyLineApp` and handed down the environment,
    /// and it is not injected into the settings sheet. So its in-memory flights
    /// survive this, and `CloudKitService.handleConflictResolution` starts from
    /// the LOCAL array — meaning a user who deletes and then signs in again
    /// within the same app launch can see their flights come back from memory.
    /// Closing this needs a reset entry point on `FlightStore` itself.
    @MainActor
    private static func resetInMemoryStores() {
        PlaceStore.shared.places = []
        PlaceStore.shared.visits = []
        TripStore.shared.trips = []
        TripStore.shared.tripEntries = [:]
    }
}
