//
//  DebugDataWipe.swift
//  SkyLine
//
//  The DEBUG-only front door to `AccountDataEraser`: the same sweep the user's
//  own "Delete Account" runs, armed from a launch argument instead of a tap, and
//  narrated to the console.
//
//  WHY THIS EXISTS. Testing first-run behaviour needs a genuinely empty account,
//  and there is no other way to get one. A developer cannot reach a user's
//  private database - CloudKit Dashboard shows the public database only - and
//  the Settings > iCloud > Manage Account Storage entry that would do it does
//  not reliably appear. The only process that can delete these records is the
//  app itself, running as the user.
//
//  WHAT LIVES HERE versus in the engine. Everything about HOW to delete records
//  honestly - paging, per-record delete results, the predicate ladder, the
//  confirmed/unconfirmed distinction, the local key and file lists - moved to
//  `AccountDataEraser` when account deletion needed the same behaviour, because
//  two copies of a wipe drift and only one of them gets the next fix. What stays
//  here is everything that is only true of a developer running this from a
//  scheme: the identity banner, the launch-argument arming, the dry run, and the
//  console output.
//
//  RUN IT ON A FRESH INSTALL. The stores are `@StateObject`s built during app
//  init, so on an install with a warm cache they already hold the old places and
//  flights in memory before this runs - and their CloudKit sync writes every one
//  of them straight back up. Deleting the records is not enough while something
//  is still holding them. Uninstall first, then wipe on the first launch.
//
//  WHOSE ACCOUNT IS THIS? CloudKit's private database is keyed to the DEVICE's
//  iCloud account, not to app-level sign-in, so this deletes from whichever
//  account the device happens to be signed into - which on a simulator is
//  routinely the developer's own. `PhotoLibrarySeeder` gained a
//  `ubiquityIdentityToken` guard after 108 synthetic photos synced into a real
//  library; that was a write, this is an irreversible delete.
//
//  Note the inversion: the seeder refuses when a token EXISTS. This tool cannot,
//  because a private database only exists when an account is signed in. So the
//  guard is not "is anyone signed in" but "do you know who, and did you say so
//  twice". It prints the container's `userRecordID` before touching anything,
//  and it will not delete unless the process was launched with
//  `-SkyLineConfirmWipe`. A launch argument was chosen over a second source
//  constant precisely because it cannot be left armed in a commit: it lives in
//  the scheme on one machine. Without it the run is a DRY RUN that counts what
//  it would delete and deletes nothing.
//

#if DEBUG

import Foundation
import CloudKit

enum DebugDataWipe {

    // MARK: - Shared Engine
    //
    // Aliases, not re-declarations. The reporting types below are the engine's,
    // so a change to what a sweep is allowed to claim reaches this tool and the
    // user-facing deletion at the same time.

    typealias AccountIdentity = AccountDataEraser.AccountIdentity
    typealias TypeStatus = AccountDataEraser.TypeStatus
    typealias TypeReport = AccountDataEraser.TypeReport
    typealias LocalReport = AccountDataEraser.LocalReport
    typealias WipeReport = AccountDataEraser.EraseReport
    typealias ErrorReaction = AccountDataEraser.ErrorReaction

    static func reaction(to error: CKError) -> ErrorReaction {
        AccountDataEraser.reaction(to: error)
    }

    static func keysToClear(in defaults: UserDefaults) -> [String] {
        AccountDataEraser.keysToClear(in: defaults)
    }

    static func localFileURLs() -> [(label: String, url: URL)] {
        AccountDataEraser.localFileURLs()
    }

    // MARK: - Arming

    /// The second signal, beyond `DebugFlags.wipeAllDataOnLaunch`, that arms the
    /// delete. Add it under Product > Scheme > Run > Arguments.
    static let confirmationArgument = "-SkyLineConfirmWipe"

    static var isArmed: Bool {
        ProcessInfo.processInfo.arguments.contains(confirmationArgument)
    }

    // MARK: - Entry Point

    static func wipeEverything() async {
        let container = CKContainer(identifier: AccountDataEraser.containerIdentifier)
        let database = container.privateCloudDatabase

        let identity = await AccountIdentity.current(of: container)
        print(identity.banner)
        print("   armed: \(isArmed ? "YES - \(confirmationArgument) present" : "no - dry run")\n")

        guard isArmed else {
            await dryRun(identity: identity, in: database)
            return
        }

        print("""

        ┌──────────────────────────────────────────────────────────┐
        │  DESTRUCTIVE: wiping this iCloud account's SkyLine data   │
        │  Private database only. This cannot be undone.           │
        └──────────────────────────────────────────────────────────┘

        """)

        // `.always`: unlike the user's own deletion, this tool clears the local
        // caches whether or not the sweep came back clean. The developer is
        // about to reinstall, and a device still holding the old cache is what
        // makes a real wipe look like it failed.
        let report = await AccountDataEraser.eraseEverything(
            localState: .always,
            log: { print($0) })

        print(report.summary(identity: identity, label: "DebugDataWipe"))
    }

    /// Counts what a real run would delete, and deletes nothing.
    ///
    /// This is what happens without `-SkyLineConfirmWipe`, and it is also the
    /// only safe way to find out whether the device is signed into the account
    /// you think it is: the counts are recognisably yours, or they are not.
    private static func dryRun(identity: AccountIdentity, in database: CKDatabase) async {
        guard identity.isUsable else {
            print("""
            ❌ DebugDataWipe: cannot even count - \(identity.blockingReason ?? "no iCloud account")

               Sign the device into the intended iCloud account and run again.
            """)
            return
        }

        print("""

        ┌──────────────────────────────────────────────────────────┐
        │  DRY RUN - nothing will be deleted                       │
        │  Launch with \(confirmationArgument) to arm the delete.      │
        └──────────────────────────────────────────────────────────┘

        """)

        let counted = await AccountDataEraser.countCloudKitRecords(
            in: database,
            log: { print($0) })

        for line in AccountDataEraser.localInventory() { print("   " + line) }

        print("""

        🧪 DebugDataWipe: DRY RUN complete - \(counted.total) CloudKit records would be deleted, 0 were.
           \(counted.unconfirmed.isEmpty
                ? "Every record type answered."
                : "COULD NOT COUNT: \(counted.unconfirmed.joined(separator: ", ")) - the real run would report these as unconfirmed.")
           Re-launch with \(confirmationArgument) to delete.

        """)
    }
}

#endif
