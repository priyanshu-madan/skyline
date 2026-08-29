//
//  DebugDataWipeTests.swift
//  SkyLineTests
//
//  The wipe deletes a real iCloud account's records irreversibly, so the only
//  thing worse than it failing is it failing quietly. It has already printed
//  "finished — 0 CloudKit records deleted" over two runs that left records
//  behind, and both times the developer reinstalled and watched the data come
//  back down from the server.
//
//  These tests pin the reporting rules rather than the network:
//   - a run that could not confirm a type is empty must never print success,
//   - only a wrong FIELD advances the predicate ladder, never a transient error,
//   - the local state list covers the file-backed caches, not just UserDefaults,
//   - dynamically suffixed defaults keys are found by prefix, not by guesswork.
//
//  Nothing here touches CloudKit. The pieces under test are the decisions the
//  sweep makes about what it is allowed to claim.
//

import Testing
import Foundation
import CloudKit
@testable import SkyLine

#if DEBUG

@Suite("Debug data wipe")
struct DebugDataWipeTests {

    // MARK: - Fixtures

    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo))
    }

    // MARK: - Error classification

    @Test("Only a wrong field advances the predicate ladder")
    func wrongFieldAdvancesLadder() {
        #expect(DebugDataWipe.reaction(to: ckError(.invalidArguments)) == .wrongField)
    }

    @Test("A transient error is retried, not mistaken for a wrong predicate")
    func transientErrorsRetry() {
        // Each of these used to fall into `default:` and end the sweep with a
        // reported count of zero, which the caller printed as "empty".
        for code in [CKError.Code.requestRateLimited, .zoneBusy, .networkUnavailable,
                     .networkFailure, .serviceUnavailable, .serverResponseLost] {
            let reaction = DebugDataWipe.reaction(to: ckError(code))
            guard case .retry = reaction else {
                Issue.record("\(code) should be retried, got \(reaction)")
                continue
            }
        }
    }

    @Test("The server's own retry interval is honoured")
    func retryIntervalComesFromTheServer() {
        let error = ckError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 7.0])
        #expect(DebugDataWipe.reaction(to: error) == .retry(after: 7.0))
    }

    @Test("Being signed out is fatal, never 'empty'")
    func notAuthenticatedIsFatal() {
        // Airplane mode and a signed-out device are the two states in which the
        // old code cheerfully reported every record type as empty.
        #expect(DebugDataWipe.reaction(to: ckError(.notAuthenticated)) == .fatal)
        #expect(DebugDataWipe.reaction(to: ckError(.permissionFailure)) == .fatal)
    }

    @Test("A missing record type is not a query failure")
    func unknownItemMeansNoSuchType() {
        #expect(DebugDataWipe.reaction(to: ckError(.unknownItem)) == .noSuchType)
    }

    // MARK: - What a status is allowed to claim

    @Test("Only a completed sweep counts as confirmed empty")
    func onlyCompletedSweepsAreConfirmed() {
        #expect(DebugDataWipe.TypeStatus.confirmedEmpty(matched: 12, deleted: 12).isConfirmed)
        #expect(DebugDataWipe.TypeStatus.noSuchType.isConfirmed)
        #expect(!DebugDataWipe.TypeStatus.unconfirmed(deleted: 0, reason: "rate limited").isConfirmed)
        #expect(!DebugDataWipe.TypeStatus
            .survivorsRemain(deleted: 8, survivors: 3, reason: "zoneBusy").isConfirmed)
    }

    @Test("Records the server refused are counted as survivors, not deletions")
    func survivorsAreNotDeletions() {
        // The original bug: `deleted += ids.count` counted the ids we ASKED to
        // delete. Three refusals in a batch of eleven meant eight deletions and
        // three records still on the server, reported as eleven.
        let status = DebugDataWipe.TypeStatus.survivorsRemain(
            deleted: 8, survivors: 3, reason: "CKError 26 (batchRequestFailed)")
        #expect(status.deleted == 8)
        #expect(status.matched == 11)
        #expect(status.problem?.contains("3 record(s) SURVIVED") == true)
    }

    // MARK: - The summary

    @Test("A run that could not confirm a type never prints success")
    func unconfirmedTypeForcesFailure() {
        var report = DebugDataWipe.WipeReport()
        report.types = [
            .init(type: "Place", status: .confirmedEmpty(matched: 22, deleted: 22)),
            .init(type: "Visit", status: .unconfirmed(deleted: 0, reason: "CKError 3 (networkUnavailable)"))
        ]
        report.local = .init(clearedKeys: ["CachedPlaces"], clearedFiles: [], problems: [])

        #expect(!report.isCleanSweep)
        let summary = report.summary()
        #expect(summary.contains("FAILED"))
        #expect(summary.contains("Visit"))
        #expect(!summary.contains("finished"))
    }

    @Test("Survivors force a failure even when every query answered")
    func survivorsForceFailure() {
        var report = DebugDataWipe.WipeReport()
        report.types = [
            .init(type: "Flight", status: .survivorsRemain(deleted: 40, survivors: 2, reason: "zoneBusy"))
        ]
        report.local = .init(clearedKeys: [], clearedFiles: [], problems: [])

        #expect(!report.isCleanSweep)
        #expect(report.deleted == 40)
        #expect(report.summary().contains("Flight"))
    }

    @Test("Local state that survived the wipe also fails the run")
    func localProblemsForceFailure() {
        var report = DebugDataWipe.WipeReport()
        report.types = [.init(type: "Place", status: .confirmedEmpty(matched: 0, deleted: 0))]
        report.local = .init(
            clearedKeys: [], clearedFiles: [],
            problems: ["could not remove pending-review.json: permission denied"])

        #expect(!report.isCleanSweep)
        #expect(report.summary().contains("pending-review.json"))
    }

    @Test("A summary is only clean when every type and the local state are")
    func cleanSweepIsClean() {
        var report = DebugDataWipe.WipeReport()
        report.types = [
            .init(type: "Place", status: .confirmedEmpty(matched: 22, deleted: 22)),
            .init(type: "Airline", status: .noSuchType)
        ]
        report.local = .init(clearedKeys: ["CachedPlaces"], clearedFiles: ["route_cache.json"], problems: [])

        #expect(report.isCleanSweep)
        #expect(report.deleted == 22)
        #expect(report.summary().contains("finished"))
        #expect(!report.summary().contains("FAILED"))
    }

    // MARK: - Local state coverage

    @Test("Dynamically suffixed defaults keys are found by prefix")
    func dynamicKeysAreEnumerated() throws {
        let suiteName = "DebugDataWipeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // One per trip, so they can never be listed in source.
        defaults.set(true, forKey: "regionBannerDismissed_trip-abc")
        defaults.set(true, forKey: "regionBannerDismissed_trip-def")
        defaults.set("keep me", forKey: "unrelated_preference")

        let keys = DebugDataWipe.keysToClear(in: defaults)
        #expect(keys.contains("regionBannerDismissed_trip-abc"))
        #expect(keys.contains("regionBannerDismissed_trip-def"))
        #expect(!keys.contains("unrelated_preference"))
    }

    @Test("Both halves of the stored session are cleared, not just the user")
    func sessionKeysAreCovered() throws {
        let suiteName = "DebugDataWipeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = Set(DebugDataWipe.keysToClear(in: defaults))
        // Each of these was read off the source that writes it.
        #expect(keys.contains("authenticated_user"))                          // AuthenticationService:106
        #expect(keys.contains("authenticated_user_provider"))                 // AuthenticationService:107
        #expect(keys.contains("cached_boarding_pass_config"))                 // ConfigurationService:16
        #expect(keys.contains("UnifiedBoardingPassService.UsageStatistics"))  // UnifiedBoardingPassService:233
    }

    @Test("File-backed caches are on the list, not just UserDefaults")
    func fileBackedStateIsCovered() {
        // A defaults-only wipe left a library scan's ~114 pending places on
        // disk, so the place log went on advertising work over an empty account.
        let labels = DebugDataWipe.localFileURLs().map(\.label)
        #expect(labels.contains("pending-review.json"))
        #expect(labels.contains("TripImages/"))
        #expect(labels.contains("place_names_cache.json"))
        #expect(labels.contains("route_cache.json"))
    }

    @Test("The wipe targets the same file the pending store loads at launch")
    func pendingReviewPathMatchesTheStore() throws {
        let wiped = try #require(
            DebugDataWipe.localFileURLs().first { $0.label == "pending-review.json" }?.url)
        let stored = try #require(PendingReviewStore.defaultFileURL)
        #expect(wiped == stored)
        #expect(stored.lastPathComponent == PendingReviewStore.defaultFileName)
    }

    // MARK: - The identity guard

    @Test("Nothing is armed by a compile-time flag alone")
    func wipeNeedsASecondSignal() {
        // The confirmation lives in the scheme on one machine, so it cannot be
        // committed in the armed state the way a source constant can.
        #expect(DebugDataWipe.confirmationArgument == "-SkyLineConfirmWipe")
        #expect(!ProcessInfo.processInfo.arguments.contains(DebugDataWipe.confirmationArgument))
    }

    @Test("Only an available account is usable; everything else blocks the run")
    func accountStatusGatesTheRun() {
        let signedOut = DebugDataWipe.AccountIdentity(
            status: .noAccount, userRecordName: nil, hasUbiquityToken: false, lookupError: nil)
        #expect(!signedOut.isUsable)
        #expect(signedOut.blockingReason != nil)

        let available = DebugDataWipe.AccountIdentity(
            status: .available, userRecordName: "_abc123", hasUbiquityToken: true, lookupError: nil)
        #expect(available.isUsable)
        #expect(available.blockingReason == nil)
        // The account being deleted from has to be legible before anything goes.
        #expect(available.banner.contains("_abc123"))
    }
}

#endif
