//
//  DebugDataWipe.swift
//  SkyLine
//
//  Deletes every SkyLine record from the signed-in user's CloudKit PRIVATE
//  database, plus the local defaults, files and caches that mirror it.
//
//  WHY THIS EXISTS. Testing first-run behaviour needs a genuinely empty account,
//  and there is no other way to get one. A developer cannot reach a user's
//  private database - CloudKit Dashboard shows the public database only - and
//  the Settings > iCloud > Manage Account Storage entry that would do it does
//  not reliably appear. The only process that can delete these records is the
//  app itself, running as the user.
//
//  RUN IT ON A FRESH INSTALL. The stores are `@StateObject`s built during app
//  init, so on an install with a warm cache they already hold the old places and
//  flights in memory before this runs - and their CloudKit sync writes every one
//  of them straight back up. Deleting the records is not enough while something
//  is still holding them. Uninstall first, then wipe on the first launch.
//
//  IT MUST NEVER CLAIM MORE THAN IT DID. Twice this printed a clean summary over
//  a run that left records behind, and both times the developer reinstalled and
//  watched the data sync back:
//
//   - `modifyRecords(saving:deleting:)` only throws for whole-operation
//     failures. Per-record refusals (`serverRecordChanged`, `zoneBusy`,
//     `batchRequestFailed`) come back inside `deleteResults`, and these records
//     live in the DEFAULT zone where `atomically:` has no effect, so a partly
//     refused batch is normal rather than exceptional. Counting the ids we ASKED
//     to delete counted attempts; the cursor then paged past the survivors and
//     never came back. Only `.success` in `deleteResults` is a deletion now.
//   - A query that failed for any reason other than a wrong field was reported
//     as an empty record type. Signed out, in airplane mode, or rate limited on
//     the heavy account this tool exists for, "we could not tell" printed as
//     "empty". A type is only clean when a query ran to completion and every
//     delete was acknowledged; everything else is `unconfirmed` and forces a
//     FAILED summary that names the type.
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

    // MARK: - Configuration

    private static let containerIdentifier = "iCloud.com.skyline.flighttracker"

    /// The second signal, beyond `DebugFlags.wipeAllDataOnLaunch`, that arms the
    /// delete. Add it under Product > Scheme > Run > Arguments.
    static let confirmationArgument = "-SkyLineConfirmWipe"

    /// Small enough that a refused batch loses little, large enough that a heavy
    /// account does not take hundreds of round trips.
    private static let pageSize = 200

    /// Attempts per page before a transient error becomes an honest failure.
    private static let maxTransientRetries = 3

    /// Every record type SkyLine writes to the private database.
    ///
    /// The public database is deliberately absent. It holds shared reference
    /// data that does not belong to this user, and the app only ever touches it
    /// to probe the schema.
    private static let privateRecordTypes = [
        "Place", "Visit", "DetectedPlace",
        "Trip", "TripEntry", "TripImages",
        "Flight", "SearchHistory", "DestinationImage",
        "Configuration", "UserProfile", "Airline", "AirportCoordinates"
    ]

    /// Records written to a hard-coded `recordName`.
    ///
    /// These need no query at all, which is fortunate: `SearchHistory` carries
    /// no queryable field, so the predicate ladder can never reach it. Deleting
    /// by id sidesteps the schema entirely.
    private static let fixedRecordIDs = ["user_search_history"]

    // MARK: - Entry Point

    static func wipeEverything() async {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        let identity = await AccountIdentity.current(of: container)
        print(identity.banner)

        // No reachable account means no private database to read, let alone
        // empty. Deleting nothing and calling it done is the exact lie this
        // tool has already told twice.
        guard identity.isUsable else {
            print("""
            ❌ DebugDataWipe: FAILED before it started - \(identity.blockingReason ?? "no iCloud account")

               Nothing was deleted and nothing was cleared. Sign the device into
               the intended iCloud account and run again.
            """)
            return
        }

        guard isArmed else {
            await dryRun(in: database)
            return
        }

        print("""

        ┌──────────────────────────────────────────────────────────┐
        │  DESTRUCTIVE: wiping this iCloud account's SkyLine data   │
        │  Private database only. This cannot be undone.           │
        └──────────────────────────────────────────────────────────┘

        """)

        var report = WipeReport()
        for type in privateRecordTypes {
            let status = await sweepAll(ofType: type, mode: .delete, in: database)
            let typeReport = TypeReport(type: type, status: status)
            report.types.append(typeReport)
            print("   " + typeReport.line)
        }

        let fixed = await deleteFixedIDs(in: database)
        report.types.append(fixed)
        print("   " + fixed.line)

        let local = await clearLocal()
        report.local = local
        print("   " + local.line)

        print(report.summary(identity: identity))
    }

    /// Counts what a real run would delete, and deletes nothing.
    ///
    /// This is what happens without `-SkyLineConfirmWipe`, and it is also the
    /// only safe way to find out whether the device is signed into the account
    /// you think it is: the counts are recognisably yours, or they are not.
    private static func dryRun(in database: CKDatabase) async {
        print("""

        ┌──────────────────────────────────────────────────────────┐
        │  DRY RUN - nothing will be deleted                       │
        │  Launch with \(confirmationArgument) to arm the delete.      │
        └──────────────────────────────────────────────────────────┘

        """)

        var total = 0
        var unconfirmed: [String] = []
        for type in privateRecordTypes {
            let status = await sweepAll(ofType: type, mode: .count, in: database)
            total += status.matched
            if !status.isConfirmed { unconfirmed.append(type) }
            print("   " + TypeReport(type: type, status: status).dryRunLine)
        }

        let fixed = await countFixedIDs(in: database)
        total += fixed.present.count
        if !fixed.unconfirmed.isEmpty { unconfirmed.append(contentsOf: fixed.unconfirmed) }
        print("   · fixed ids: \(fixed.present.isEmpty ? "none present" : fixed.present.joined(separator: ", "))")

        for line in localInventory() { print("   " + line) }

        print("""

        🧪 DebugDataWipe: DRY RUN complete - \(total) CloudKit records would be deleted, 0 were.
           \(unconfirmed.isEmpty
                ? "Every record type answered."
                : "COULD NOT COUNT: \(unconfirmed.joined(separator: ", ")) - the real run would report these as unconfirmed.")
           Re-launch with \(confirmationArgument) to delete.

        """)
    }

    private static var isArmed: Bool {
        ProcessInfo.processInfo.arguments.contains(confirmationArgument)
    }

    // MARK: - Identity

    /// Who this run would delete from.
    struct AccountIdentity {
        let status: CKAccountStatus
        let userRecordName: String?
        let hasUbiquityToken: Bool
        let lookupError: String?

        static func current(of container: CKContainer) async -> AccountIdentity {
            var status: CKAccountStatus = .couldNotDetermine
            var recordName: String?
            var failure: String?

            do {
                status = try await container.accountStatus()
            } catch {
                failure = "accountStatus: \(error.localizedDescription)"
            }
            do {
                recordName = try await container.userRecordID().recordName
            } catch {
                // Not fatal on its own: the status above is the gate. But a run
                // that cannot name the account must say so rather than print a
                // blank line where the identity should be.
                failure = [failure, "userRecordID: \(error.localizedDescription)"]
                    .compactMap { $0 }
                    .joined(separator: "; ")
            }

            return AccountIdentity(
                status: status,
                userRecordName: recordName,
                hasUbiquityToken: FileManager.default.ubiquityIdentityToken != nil,
                lookupError: failure
            )
        }

        /// `.available` is the only status with a private database behind it.
        var isUsable: Bool { status == .available }

        var blockingReason: String? {
            isUsable ? nil : "iCloud account status is \(Self.describe(status))"
        }

        var banner: String {
            """

            ┌──────────────────────────────────────────────────────────┐
            │  DebugDataWipe - THIS iCLOUD ACCOUNT                     │
            └──────────────────────────────────────────────────────────┘
               user record: \(userRecordName ?? "UNKNOWN")
               account status: \(Self.describe(status))
               signed into iCloud: \(hasUbiquityToken ? "yes" : "NO")
               armed: \(DebugDataWipe.isArmed ? "YES - \(DebugDataWipe.confirmationArgument) present" : "no - dry run")
            \(lookupError.map { "   lookup problem: \($0)\n" } ?? "")
               If that user record is not the throwaway account you meant, stop
               now: the private database belongs to the DEVICE's iCloud login,
               not to whoever is signed into SkyLine.

            """
        }

        static func describe(_ status: CKAccountStatus) -> String {
            switch status {
            case .available: return "available"
            case .noAccount: return "noAccount (signed out)"
            case .restricted: return "restricted"
            case .couldNotDetermine: return "couldNotDetermine"
            case .temporarilyUnavailable: return "temporarilyUnavailable"
            @unknown default: return "unknown (\(status.rawValue))"
            }
        }
    }

    // MARK: - Reporting

    /// What we can honestly say about one record type after a sweep.
    ///
    /// The distinction that matters is `confirmedEmpty` versus `unconfirmed`.
    /// The old code collapsed the two, so a query that failed for any reason
    /// printed as "empty" and the run still claimed success.
    enum TypeStatus: Equatable {
        /// A query ran to completion and every delete was acknowledged.
        /// `matched` is what was found, `deleted` what the server confirmed
        /// removing; they differ when a record was already gone.
        case confirmedEmpty(matched: Int, deleted: Int)
        /// The query completed but the server refused to delete some records.
        /// Those records are still there and paging has moved past them.
        case survivorsRemain(deleted: Int, survivors: Int, reason: String)
        /// We never established what this type holds. NOT empty - unknown.
        case unconfirmed(deleted: Int, reason: String)
        /// The schema has no such record type, so there is nothing to hold.
        case noSuchType

        var deleted: Int {
            switch self {
            case .confirmedEmpty(_, let deleted): return deleted
            case .survivorsRemain(let deleted, _, _): return deleted
            case .unconfirmed(let deleted, _): return deleted
            case .noSuchType: return 0
            }
        }

        var matched: Int {
            switch self {
            case .confirmedEmpty(let matched, _): return matched
            case .survivorsRemain(let deleted, let survivors, _): return deleted + survivors
            case .unconfirmed(let deleted, _): return deleted
            case .noSuchType: return 0
            }
        }

        /// True only when this type is known to hold nothing now.
        var isConfirmed: Bool {
            switch self {
            case .confirmedEmpty, .noSuchType: return true
            case .survivorsRemain, .unconfirmed: return false
            }
        }

        var problem: String? {
            switch self {
            case .confirmedEmpty, .noSuchType:
                return nil
            case .survivorsRemain(let deleted, let survivors, let reason):
                return "\(survivors) record(s) SURVIVED after deleting \(deleted) - \(reason)"
            case .unconfirmed(let deleted, let reason):
                return "could not confirm empty after deleting \(deleted) - \(reason)"
            }
        }
    }

    struct TypeReport {
        let type: String
        let status: TypeStatus

        var line: String {
            switch status {
            case .confirmedEmpty(_, let deleted):
                return deleted > 0 ? "· \(type): deleted \(deleted)" : "· \(type): empty"
            case .noSuchType:
                return "· \(type): no such record type"
            case .survivorsRemain, .unconfirmed:
                return "❌ \(type): \(status.problem ?? "unconfirmed")"
            }
        }

        var dryRunLine: String {
            switch status {
            case .confirmedEmpty(let matched, _):
                return matched > 0 ? "· \(type): \(matched) would be deleted" : "· \(type): empty"
            case .noSuchType:
                return "· \(type): no such record type"
            case .survivorsRemain(_, let survivors, let reason):
                return "❌ \(type): could not read \(survivors) - \(reason)"
            case .unconfirmed(_, let reason):
                return "❌ \(type): COULD NOT COUNT - \(reason)"
            }
        }
    }

    struct WipeReport {
        var types: [TypeReport] = []
        var local: LocalReport?

        var deleted: Int { types.reduce(0) { $0 + $1.status.deleted } }

        /// Every type that is not known to be empty now, whether because
        /// records survived or because a query never answered.
        var unconfirmed: [TypeReport] { types.filter { !$0.status.isConfirmed } }

        /// The one condition under which a success line may be printed.
        var isCleanSweep: Bool { unconfirmed.isEmpty && (local?.isComplete ?? false) }

        func summary(identity: AccountIdentity? = nil) -> String {
            let account = identity?.userRecordName ?? "unknown account"
            guard !isCleanSweep else {
                return """

                🧹 DebugDataWipe: finished - \(deleted) CloudKit records deleted, \
                every record type confirmed empty (\(account)).

                """
            }

            var lines: [String] = []
            lines.append("")
            lines.append("┌──────────────────────────────────────────────────────────┐")
            lines.append("│  DebugDataWipe: FAILED - the account is NOT empty        │")
            lines.append("└──────────────────────────────────────────────────────────┘")
            lines.append("   \(deleted) record(s) deleted from \(account), but:")
            for report in unconfirmed {
                lines.append("   ❌ \(report.type): \(report.status.problem ?? "unconfirmed")")
            }
            if let local, !local.isComplete {
                for problem in local.problems { lines.append("   ❌ local: \(problem)") }
            }
            lines.append("")
            lines.append("   Do NOT treat this as an empty account. Run again once the")
            lines.append("   cause above is fixed; the sweep is idempotent.")
            lines.append("")
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Sweeping One Record Type

    private enum Mode {
        case delete
        case count
    }

    /// Walks the predicate ladder until one answers, then reports what it found.
    ///
    /// Only a genuine `invalidArguments` on the FIRST page - the server saying
    /// this type has no such field - advances the ladder. A transient error used
    /// to advance it too, so one rate-limited response burned a predicate and,
    /// once the ladder ran out, the type reported "NOT WIPED" or worse, "empty".
    private static func sweepAll(ofType type: String, mode: Mode, in database: CKDatabase) async -> TypeStatus {
        let predicates = candidatePredicates()
        for predicate in predicates {
            switch await sweep(type: type, predicate: predicate, mode: mode, in: database) {
            case .wrongPredicate:
                continue                       // wrong field for this type; try the next
            case .noSuchType:
                return .noSuchType
            case .swept(let sweep):
                guard sweep.survivors.isEmpty else {
                    return .survivorsRemain(
                        deleted: sweep.deleted,
                        survivors: sweep.survivors.count,
                        reason: describe(sweep.survivors))
                }
                return .confirmedEmpty(matched: sweep.matched, deleted: sweep.deleted)
            case .interrupted(let sweep, let reason):
                return .unconfirmed(deleted: sweep.deleted, reason: reason)
            }
        }
        // Every predicate was rejected as a wrong field. This is NOT an empty
        // type: it is a type we have no way to query, which is exactly how a
        // wipe of nothing used to read as a success.
        return .unconfirmed(
            deleted: 0,
            reason: "no queryable field found (tried \(predicates.count) predicates)")
    }

    /// Running total for one predicate against one type.
    private struct Sweep {
        /// Records the query returned.
        var matched = 0
        /// Deletes the server acknowledged as `.success`.
        var deleted = 0
        /// Deletes the server refused, by id. These records are still there.
        var survivors: [CKRecord.ID: String] = [:]
    }

    private enum SweepOutcome {
        /// Paged to the end. `survivors` may still be non-empty.
        case swept(Sweep)
        /// Stopped early. Whatever is left is unknown, not empty.
        case interrupted(Sweep, reason: String)
        /// This predicate names a field the type does not have.
        case wrongPredicate
        /// The schema has no such record type.
        case noSuchType
    }

    private static func sweep(
        type: String,
        predicate: NSPredicate,
        mode: Mode,
        in database: CKDatabase
    ) async -> SweepOutcome {
        var cursor: CKQueryOperation.Cursor?
        var sweep = Sweep()
        var attempt = 0
        var finished = false

        while !finished {
            do {
                let page: (
                    matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                    queryCursor: CKQueryOperation.Cursor?
                )

                // `desiredKeys: []` because only the ids are ever used. Pulling
                // field values back to throw them away costs real time on a
                // heavy account.
                if let cursor {
                    page = try await database.records(
                        continuingMatchFrom: cursor,
                        desiredKeys: [],
                        resultsLimit: pageSize)
                } else {
                    let query = CKQuery(recordType: type, predicate: predicate)
                    page = try await database.records(
                        matching: query,
                        desiredKeys: [],
                        resultsLimit: pageSize)
                }
                attempt = 0

                let ids = page.matchResults.map(\.0)
                sweep.matched += ids.count

                if mode == .delete, !ids.isEmpty {
                    let batch = try await delete(ids, in: database)
                    sweep.deleted += batch.deleted
                    for (id, reason) in batch.refused { sweep.survivors[id] = reason }
                }

                if let next = page.queryCursor { cursor = next } else { finished = true }
            } catch let error as CKError {
                switch reaction(to: error) {
                case .wrongField:
                    // Only meaningful before the predicate has ever worked. Mid
                    // sweep it is a real failure, not a hint to try another field.
                    guard sweep.matched == 0 else {
                        return .interrupted(sweep, reason: describe(error))
                    }
                    return .wrongPredicate
                case .noSuchType:
                    guard sweep.matched == 0 else {
                        return .interrupted(sweep, reason: describe(error))
                    }
                    return .noSuchType
                case .retry(let after):
                    attempt += 1
                    guard attempt <= maxTransientRetries else {
                        return .interrupted(
                            sweep,
                            reason: "\(describe(error)) after \(maxTransientRetries) retries")
                    }
                    try? await Task.sleep(nanoseconds: UInt64(max(after, 1) * 1_000_000_000))
                    continue                   // same page, cursor untouched
                case .fatal:
                    return .interrupted(sweep, reason: describe(error))
                }
            } catch {
                return .interrupted(sweep, reason: error.localizedDescription)
            }
        }

        // One bounded retry over what the server refused. `zoneBusy` and
        // `serverRecordChanged` are routinely transient, and the paging loop has
        // already moved past these ids, so this is their only second chance.
        if mode == .delete, !sweep.survivors.isEmpty {
            let retryIDs = Array(sweep.survivors.keys)
            if let batch = try? await delete(retryIDs, in: database) {
                sweep.deleted += batch.deleted
                for id in retryIDs where batch.refused[id] == nil {
                    sweep.survivors.removeValue(forKey: id)
                }
                for (id, reason) in batch.refused { sweep.survivors[id] = reason }
            }
        }

        return .swept(sweep)
    }

    /// Deletes one batch and reports per-record truth.
    ///
    /// `modifyRecords` throws only for whole-operation failures. Everything
    /// else - and in the default zone, where `atomically:` is ignored, that is
    /// most of it - arrives in `deleteResults` keyed by id. An id missing from
    /// that dictionary is not a success either: the server said nothing about
    /// it, so we do not know it is gone.
    private static func delete(
        _ ids: [CKRecord.ID],
        in database: CKDatabase
    ) async throws -> (deleted: Int, refused: [CKRecord.ID: String]) {
        let results = try await database.modifyRecords(saving: [], deleting: ids)
        var deleted = 0
        var refused: [CKRecord.ID: String] = [:]

        for id in ids {
            switch results.deleteResults[id] {
            case .success:
                deleted += 1
            case .failure(let error):
                // Already gone is the outcome we wanted; it is not a survivor.
                if let ckError = error as? CKError, ckError.code == .unknownItem { continue }
                refused[id] = describe(error)
            case .none:
                refused[id] = "no result returned for this id"
            }
        }
        return (deleted, refused)
    }

    // MARK: - Predicate Ladder

    /// Every predicate worth trying, in order.
    ///
    /// `TRUEPREDICATE` is the obvious one and the one that does NOT work here:
    /// querying by it needs `recordName` marked queryable in the schema, and
    /// this container does not mark it. CloudKit reports that as CKError 12
    /// (`invalidArguments`), which reads exactly like "no records" if you are
    /// not looking. The app's own sync works around it with `createdAt > 1970`,
    /// because `createdAt` IS indexed - so that is tried first here too.
    private static func candidatePredicates() -> [NSPredicate] {
        let epoch = Date(timeIntervalSince1970: 0) as NSDate
        return [
            NSPredicate(format: "createdAt > %@", epoch),
            NSPredicate(format: "updatedAt > %@", epoch),
            NSPredicate(format: "date > %@", epoch),
            NSPredicate(format: "timestamp > %@", epoch),
            NSPredicate(format: "startDate > %@", epoch),
            NSPredicate(format: "departureTime > %@", epoch),
            // String fallbacks for the types that carry no indexed date:
            // settings, caches and the profile record.
            NSPredicate(format: "configType != %@", ""),
            NSPredicate(format: "userId != %@", ""),
            NSPredicate(format: "airportCode != %@", ""),
            NSPredicate(format: "code != %@", ""),
            NSPredicate(format: "name != %@", ""),
            NSPredicate(value: true)
        ]
    }

    // MARK: - Error Classification

    /// How a sweep should react to a CloudKit error.
    ///
    /// Exposed for tests: the difference between `wrongField` and everything
    /// else is what decides whether the ladder advances, and getting it wrong
    /// is what let a rate-limited account report itself empty.
    enum ErrorReaction: Equatable {
        /// The type has no such field. Try the next predicate.
        case wrongField
        /// The schema has no such record type.
        case noSuchType
        /// Worth trying the same page again after a pause.
        case retry(after: TimeInterval)
        /// Nothing here will improve by retrying. Report it.
        case fatal
    }

    static func reaction(to error: CKError) -> ErrorReaction {
        switch error.code {
        case .invalidArguments:
            return .wrongField
        case .unknownItem:
            return .noSuchType
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .serverResponseLost:
            return .retry(after: error.retryAfterSeconds ?? 2)
        default:
            // Includes notAuthenticated, permissionFailure, quotaExceeded,
            // managedAccountRestricted. All of them mean "we cannot tell what
            // this account holds", never "it holds nothing".
            return .fatal
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        return "CKError \(ckError.errorCode) (\(ckError.code)): \(ckError.localizedDescription)"
    }

    private static func describe(_ survivors: [CKRecord.ID: String]) -> String {
        let names = survivors.keys.map(\.recordName).sorted().prefix(3).joined(separator: ", ")
        let reason = survivors.values.first ?? "unknown"
        let more = survivors.count > 3 ? " (+\(survivors.count - 3) more)" : ""
        return "\(reason); e.g. \(names)\(more)"
    }

    // MARK: - Fixed Record IDs

    private static func deleteFixedIDs(in database: CKDatabase) async -> TypeReport {
        var deleted = 0
        var survivors: [CKRecord.ID: String] = [:]

        for name in fixedRecordIDs {
            do {
                try await database.deleteRecord(withID: CKRecord.ID(recordName: name))
                deleted += 1
            } catch let error as CKError where error.code == .unknownItem {
                continue                       // already gone is the goal, not a failure
            } catch {
                // Previously printed as a warning and then forgotten, so a
                // record that refused to die still ended in a clean summary.
                survivors[CKRecord.ID(recordName: name)] = describe(error)
            }
        }

        let status: TypeStatus = survivors.isEmpty
            ? .confirmedEmpty(matched: deleted, deleted: deleted)
            : .survivorsRemain(deleted: deleted, survivors: survivors.count, reason: describe(survivors))
        return TypeReport(type: "fixed ids", status: status)
    }

    private static func countFixedIDs(
        in database: CKDatabase
    ) async -> (present: [String], unconfirmed: [String]) {
        let ids = fixedRecordIDs.map { CKRecord.ID(recordName: $0) }
        guard let results = try? await database.records(for: ids, desiredKeys: []) else {
            return ([], fixedRecordIDs)
        }
        var present: [String] = []
        var unconfirmed: [String] = []
        for id in ids {
            switch results[id] {
            case .success:
                present.append(id.recordName)
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .unknownItem { continue }
                unconfirmed.append(id.recordName)
            case .none:
                unconfirmed.append(id.recordName)
            }
        }
        return (present, unconfirmed)
    }

    // MARK: - Local State

    /// Defaults keys that cache the CloudKit records above. Left behind, they
    /// repopulate the UI from disk and make a real wipe look like it failed.
    ///
    /// Every key here was read from the source that writes it; a key nobody
    /// writes is worse than no key, because it implies coverage that is absent.
    private static let localKeys = [
        "CachedPlaces", "CachedVisits", "CachedTrips", "CachedTripEntries",
        "PendingPlaceWrites", "PendingVisitWrites",
        "LastPlaceSyncDate", "LastTripSyncDate", "last_sync_date",
        "saved_flights", "deleted_flights", "cached_airlines",
        "search_history", "hasFixedFlightDates",
        // AuthenticationService.swift:106-107 - both halves of the session, not
        // just the user. Clearing the user and leaving the provider behind left
        // the app half signed in.
        "authenticated_user", "authenticated_user_provider",
        // ConfigurationService.swift:16
        "cached_boarding_pass_config",
        // UnifiedBoardingPassService.swift:220,233
        "UnifiedBoardingPassService.UsageStatistics",
        "skyline_onboarding_seen_v1", "skyline_onboarding_first_run_detection_v1"
    ]

    /// Defaults keys whose names carry a record id, so they cannot be listed.
    ///
    /// `regionBannerDismissed_<tripId>` (TripDetailView.swift:137) accumulates
    /// one key per trip. Enumerating the defaults dictionary by prefix is the
    /// only way to catch them; a hard-coded list would go stale the first time
    /// a trip is added.
    private static let localKeyPrefixes = ["regionBannerDismissed_"]

    /// Files and directories that outlive a defaults wipe entirely.
    ///
    /// This is the class of leftover that made a successful wipe look failed:
    /// `pending-review.json` alone can hold ~114 places from a library scan, so
    /// the place log still advertised pending work over an empty account.
    /// Internal rather than private so a test can assert the list covers each
    /// of them; a file missing from here is invisible until a wipe leaves it.
    static func localFileURLs() -> [(label: String, url: URL)] {
        let fileManager = FileManager.default
        var entries: [(String, URL)] = []

        // PendingReviewStore.swift - Application Support, loaded in `init()`.
        if let pendingReview = PendingReviewStore.defaultFileURL {
            entries.append(("pending-review.json", pendingReview))
        }
        // TripStore.swift:102 - Documents/TripImages/<tripId>[_theme].jpg
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            entries.append(("TripImages/", documents.appendingPathComponent("TripImages")))
        }
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // PlaceNamingService.swift:114
            entries.append(("place_names_cache.json", caches.appendingPathComponent("place_names_cache.json")))
            // RouteCache.swift:50
            entries.append(("route_cache.json", caches.appendingPathComponent("route_cache.json")))
        }
        return entries
    }

    struct LocalReport {
        var clearedKeys: [String] = []
        var clearedFiles: [String] = []
        var problems: [String] = []

        var isComplete: Bool { problems.isEmpty }

        var line: String {
            let base = "· local: cleared \(clearedKeys.count) keys, \(clearedFiles.count) files, backfill marked done"
            return problems.isEmpty ? base : "❌ local: \(problems.joined(separator: "; "))"
        }
    }

    /// What exists on disk right now, for the dry run to print.
    private static func localInventory() -> [String] {
        let defaults = UserDefaults.standard
        let keys = keysToClear(in: defaults)
        let present = keys.filter { defaults.object(forKey: $0) != nil }
        var lines = ["· local: \(present.count) of \(keys.count) defaults keys present"]
        for entry in localFileURLs() where FileManager.default.fileExists(atPath: entry.url.path) {
            lines.append("· local: \(entry.label) present")
        }
        return lines
    }

    /// The full key list, static plus every dynamically suffixed key currently
    /// in the defaults dictionary.
    static func keysToClear(in defaults: UserDefaults) -> [String] {
        let dynamic = defaults.dictionaryRepresentation().keys.filter { key in
            localKeyPrefixes.contains { key.hasPrefix($0) }
        }
        return localKeys + dynamic.sorted()
    }

    @MainActor
    private static func clearLocal() async -> LocalReport {
        var report = LocalReport()
        let defaults = UserDefaults.standard

        let keys = keysToClear(in: defaults)
        for key in keys { defaults.removeObject(forKey: key) }
        report.clearedKeys = keys

        // The store is a `@MainActor` singleton that loads its file in `init()`.
        // Deleting the file alone would leave a live instance still publishing
        // ~114 pending places into the place log, and that instance would write
        // them back on its next save. Clear the instance, then the file.
        PendingReviewStore.shared.clear()

        for entry in localFileURLs() {
            guard FileManager.default.fileExists(atPath: entry.url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: entry.url)
                report.clearedFiles.append(entry.label)
            } catch {
                report.problems.append("could not remove \(entry.label): \(error.localizedDescription)")
            }
        }

        // NOT cleared - deliberately SET.
        //
        // `PlaceImportVersion` gates the flight-to-place backfill. Clearing it
        // told `PlaceImportService.runIfNeeded` the backfill had never run, so
        // the next launch re-derived a place for every flight and the wipe
        // appeared to undo itself: 537 records deleted, then 22 places back.
        // Marking it complete is what actually leaves the account empty.
        defaults.set(PlaceImportService.currentImportVersion, forKey: "PlaceImportVersion")

        let stillPresent = keys.filter { defaults.object(forKey: $0) != nil }
        if !stillPresent.isEmpty {
            report.problems.append("keys survived removal: \(stillPresent.joined(separator: ", "))")
        }
        return report
    }
}

#endif
