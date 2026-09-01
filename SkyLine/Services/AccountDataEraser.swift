//
//  AccountDataEraser.swift
//  SkyLine
//
//  Deletes every SkyLine record from the signed-in user's CloudKit PRIVATE
//  database, plus the local defaults, files and caches that mirror it.
//
//  This is the engine. It has two callers and deliberately no opinion about
//  which one is running:
//
//   - `AccountDeletionService`, the App Store requirement (Guideline 5.1.1(v)):
//     the user asks for their account to be deleted from inside the app.
//   - `DebugDataWipe`, the DEBUG-only tool that arms the same sweep from a
//     launch argument so first-run behaviour can be tested against a genuinely
//     empty account.
//
//  Both existed as one file until account deletion needed it, and copying it
//  would have produced two wipes that drift apart. Everything below was written
//  for the debug tool and is unchanged in substance; what moved is the printing,
//  which is now an optional `log` closure so the console tool can stream and the
//  user-facing path can stay quiet and read the report instead.
//
//  IT MUST NEVER CLAIM MORE THAN IT DID. Twice the debug tool printed a clean
//  summary over a run that left records behind, and both times the developer
//  reinstalled and watched the data sync back:
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
//     FAILED result that names the type.
//
//  That last rule is what account deletion needs most. A user who is told their
//  account is gone and then signs back in to find their flights has been lied
//  to, so `EraseReport.isCleanSweep` is the only thing allowed to produce a
//  success message, and `userFacingProblem` names what is still there.
//
//  WHOSE ACCOUNT IS THIS? CloudKit's private database is keyed to the DEVICE's
//  iCloud account, not to app-level sign-in, so this deletes from whichever
//  account the device happens to be signed into. For the user-initiated path
//  that is exactly right - it is their device and their request. For the debug
//  tool it is a hazard, which is why `DebugDataWipe` keeps its own identity
//  banner and launch-argument arming on top of this.
//

import Foundation
import CloudKit

enum AccountDataEraser {

    // MARK: - Configuration

    static let containerIdentifier = "iCloud.com.skyline.flighttracker"

    /// Receives one line per record type as the sweep goes. `nil` for the
    /// user-facing path, which reads the returned report instead of the console.
    typealias Log = (String) -> Void

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
    static let privateRecordTypes = [
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

    /// The label `deleteFixedIDs` reports under. Not a record type, but it
    /// occupies the same column in every report.
    static let fixedIDsLabel = "fixed ids"

    // MARK: - Entry Point

    /// Whether the local caches are cleared when the CloudKit sweep did not come
    /// back clean.
    enum LocalStatePolicy {
        /// Clear regardless. What `DebugDataWipe` has always done: the developer
        /// is about to reinstall anyway, and a half-cleared device is the point.
        case always
        /// Only clear once every record type is confirmed empty.
        ///
        /// Account deletion needs this. The local keys include
        /// `authenticated_user`, so clearing them after a failed sweep would
        /// half sign the user out of an account that still exists, leaving them
        /// nothing to retry from.
        case onlyWhenCloudIsClean
    }

    /// Deletes the account's CloudKit records and, per `localState`, the local
    /// caches that mirror them.
    ///
    /// Never throws and never partially reports: the returned `EraseReport` is
    /// the whole truth about what happened, including the case where the run
    /// could not start.
    static func eraseEverything(
        localState: LocalStatePolicy = .onlyWhenCloudIsClean,
        log: Log? = nil
    ) async -> EraseReport {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        let identity = await AccountIdentity.current(of: container)

        // No reachable account means no private database to read, let alone
        // empty. Deleting nothing and calling it done is the exact lie this
        // engine has already told twice.
        guard identity.isUsable else {
            return EraseReport(
                blockedReason: identity.blockingReason ?? "no iCloud account",
                identity: identity)
        }

        var report = EraseReport(identity: identity)
        report.types = await eraseCloudKitRecords(in: database, log: log)

        let clearLocal: Bool
        switch localState {
        case .always: clearLocal = true
        case .onlyWhenCloudIsClean: clearLocal = report.cloudIsClean
        }

        if clearLocal {
            let local = await clearLocalState()
            report.local = local
            log?("   " + local.line)
        } else {
            log?("   · local: left alone - the CloudKit sweep was not clean")
        }

        return report
    }

    /// Sweeps every private record type, plus the fixed ids, and reports each.
    static func eraseCloudKitRecords(in database: CKDatabase, log: Log? = nil) async -> [TypeReport] {
        var reports: [TypeReport] = []
        for type in privateRecordTypes {
            let status = await sweepAll(ofType: type, mode: .delete, in: database)
            let typeReport = TypeReport(type: type, status: status)
            reports.append(typeReport)
            log?("   " + typeReport.line)
        }

        let fixed = await deleteFixedIDs(in: database)
        reports.append(fixed)
        log?("   " + fixed.line)
        return reports
    }

    /// Counts what a real run would delete, and deletes nothing.
    ///
    /// The only safe way to find out whether the device is signed into the
    /// account you think it is: the counts are recognisably yours, or they are
    /// not.
    static func countCloudKitRecords(
        in database: CKDatabase,
        log: Log? = nil
    ) async -> (total: Int, unconfirmed: [String]) {
        var total = 0
        var unconfirmed: [String] = []

        for type in privateRecordTypes {
            let status = await sweepAll(ofType: type, mode: .count, in: database)
            total += status.matched
            if !status.isConfirmed { unconfirmed.append(type) }
            log?("   " + TypeReport(type: type, status: status).dryRunLine)
        }

        let fixed = await countFixedIDs(in: database)
        total += fixed.present.count
        unconfirmed.append(contentsOf: fixed.unconfirmed)
        log?("   · \(fixedIDsLabel): \(fixed.present.isEmpty ? "none present" : fixed.present.joined(separator: ", "))")

        return (total, unconfirmed)
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

        /// The same fact in words a user can act on, rather than a CloudKit enum.
        var userFacingBlockingReason: String? {
            switch status {
            case .available:
                return nil
            case .noAccount:
                return "This device isn't signed in to iCloud, so SkyLine can't reach the flights stored there."
            case .restricted:
                return "iCloud is restricted on this device, so SkyLine can't reach the flights stored there."
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable. Nothing was deleted - please try again shortly."
            case .couldNotDetermine:
                return "SkyLine couldn't reach iCloud. Check your connection and try again."
            @unknown default:
                return "SkyLine couldn't reach iCloud (status \(status.rawValue))."
            }
        }

        var banner: String {
            """

            ┌──────────────────────────────────────────────────────────┐
            │  THIS iCLOUD ACCOUNT                                     │
            └──────────────────────────────────────────────────────────┘
               user record: \(userRecordName ?? "UNKNOWN")
               account status: \(Self.describe(status))
               signed into iCloud: \(hasUbiquityToken ? "yes" : "NO")
            \(lookupError.map { "   lookup problem: \($0)\n" } ?? "")
               If that user record is not the account you meant, stop now: the
               private database belongs to the DEVICE's iCloud login, not to
               whoever is signed into SkyLine.

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

        /// The record type as something a user recognises. Deletion failure is
        /// read by someone who has never heard of a `TripEntry`.
        var userFacingNoun: String { AccountDataEraser.userFacingNoun(for: type) }
    }

    /// Plain-English names for the record types, used only in messages the user
    /// sees. A type missing from here falls back to its own name, which is
    /// wrong-sounding but never misleading.
    static func userFacingNoun(for type: String) -> String {
        switch type {
        case "Flight": return "flights"
        case "Place": return "places"
        case "Visit": return "visits"
        case "DetectedPlace": return "detected places"
        case "Trip": return "trips"
        case "TripEntry": return "trip entries"
        case "TripImages": return "trip images"
        case "SearchHistory", fixedIDsLabel: return "search history"
        case "DestinationImage": return "destination images"
        case "Configuration": return "settings"
        case "UserProfile": return "your profile"
        case "Airline": return "airline details"
        case "AirportCoordinates": return "airport details"
        default: return type
        }
    }

    struct EraseReport {
        var types: [TypeReport] = []
        var local: LocalReport?
        /// Set when the run never started, so nothing was attempted at all.
        /// Distinct from a failed sweep: here `deleted` is genuinely zero and
        /// the user's data is untouched.
        var blockedReason: String?
        var identity: AccountIdentity?

        var deleted: Int { types.reduce(0) { $0 + $1.status.deleted } }

        /// Every type that is not known to be empty now, whether because
        /// records survived or because a query never answered.
        var unconfirmed: [TypeReport] { types.filter { !$0.status.isConfirmed } }

        /// Every record type answered and holds nothing. Says nothing about the
        /// local caches.
        var cloudIsClean: Bool { blockedReason == nil && !types.isEmpty && unconfirmed.isEmpty }

        /// The one condition under which a success line may be printed.
        ///
        /// `!types.isEmpty` is not pedantry: a default-constructed report has
        /// swept nothing, and "nothing was unconfirmed" is exactly how a run
        /// that never happened reads as a run that succeeded.
        var isCleanSweep: Bool {
            blockedReason == nil && !types.isEmpty && unconfirmed.isEmpty && (local?.isComplete ?? false)
        }

        /// What went wrong, in words a user can act on. `nil` only when the
        /// account really is empty.
        ///
        /// This exists because the alternative - a Bool - is how the console
        /// summary lied twice. The caller cannot accidentally flatten "we
        /// deleted 40 of 42 records" into "done".
        var userFacingProblem: String? {
            if blockedReason != nil {
                return identity?.userFacingBlockingReason
                    ?? "SkyLine couldn't reach iCloud, so nothing was deleted."
            }
            guard !isCleanSweep else { return nil }

            var sentences: [String] = []
            let stuck = unconfirmed
            if !stuck.isEmpty {
                let nouns = Array(Set(stuck.map(\.userFacingNoun))).sorted()
                sentences.append(
                    deleted > 0
                        ? "SkyLine deleted \(deleted) item\(deleted == 1 ? "" : "s"), but couldn't finish removing your \(list(nouns))."
                        : "SkyLine couldn't remove your \(list(nouns)).")
            }
            if let local, !local.isComplete {
                sentences.append("Some data on this device also couldn't be cleared.")
            }
            if sentences.isEmpty {
                // Reachable when the cloud sweep was clean but the local clear
                // was skipped or never ran. Still not a deletion.
                sentences.append("SkyLine couldn't finish clearing your data.")
            }
            sentences.append("Your account has not been deleted. Nothing else was changed, so you can try again.")
            return sentences.joined(separator: " ")
        }

        private func list(_ items: [String]) -> String {
            switch items.count {
            case 0: return "data"
            case 1: return items[0]
            case 2: return "\(items[0]) and \(items[1])"
            default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
            }
        }

        /// The console form. `label` names the caller so a developer reading the
        /// log knows whether this was the debug tool or a real deletion.
        func summary(identity: AccountIdentity? = nil, label: String = "SkyLine erase") -> String {
            let account = (identity ?? self.identity)?.userRecordName ?? "unknown account"
            guard !isCleanSweep else {
                return """

                🧹 \(label): finished - \(deleted) CloudKit records deleted, \
                every record type confirmed empty (\(account)).

                """
            }

            var lines: [String] = []
            lines.append("")
            lines.append("┌──────────────────────────────────────────────────────────┐")
            lines.append("│  \(label): FAILED - the account is NOT empty")
            lines.append("└──────────────────────────────────────────────────────────┘")
            if let blockedReason {
                lines.append("   Never started: \(blockedReason)")
                lines.append("   Nothing was deleted and nothing was cleared.")
            } else {
                lines.append("   \(deleted) record(s) deleted from \(account), but:")
                for report in unconfirmed {
                    lines.append("   ❌ \(report.type): \(report.status.problem ?? "unconfirmed")")
                }
                if let local, !local.isComplete {
                    for problem in local.problems { lines.append("   ❌ local: \(problem)") }
                }
                if local == nil {
                    lines.append("   ❌ local: not cleared - the CloudKit sweep was not clean")
                }
            }
            lines.append("")
            lines.append("   Do NOT treat this as an empty account. Run again once the")
            lines.append("   cause above is fixed; the sweep is idempotent.")
            lines.append("")
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Sweeping One Record Type

    enum Mode {
        case delete
        case count
    }

    /// Walks the predicate ladder until one answers, then reports what it found.
    ///
    /// Only a genuine `invalidArguments` on the FIRST page - the server saying
    /// this type has no such field - advances the ladder. A transient error used
    /// to advance it too, so one rate-limited response burned a predicate and,
    /// once the ladder ran out, the type reported "NOT WIPED" or worse, "empty".
    static func sweepAll(ofType type: String, mode: Mode, in database: CKDatabase) async -> TypeStatus {
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
        return TypeReport(type: fixedIDsLabel, status: status)
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

    /// What exists on disk right now, for a dry run to print.
    static func localInventory() -> [String] {
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
    static func clearLocalState() async -> LocalReport {
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
