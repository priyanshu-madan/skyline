//
//  AccountDeletionTests.swift
//  SkyLineTests
//
//  In-app account deletion (App Store Guideline 5.1.1(v)) runs the same sweep as
//  `DebugDataWipe`, so it inherits the same failure mode: a clean summary printed
//  over a run that left records behind. The difference is who reads it. The debug
//  tool lies to a developer who can reinstall; this lies to a user who has been
//  told their flights are gone and will find out otherwise the next time they
//  sign in.
//
//  So these tests pin the messages, not the network:
//   - nothing that did not finish may produce a "deleted" result,
//   - a report that never started is distinct from one that failed part way,
//   - the sentence the user reads names what survived, in words they recognise,
//   - a credential that was not revoked says so.
//
//  `DebugDataWipeTests` covers the sweep's own decisions and still runs against
//  the extracted engine; nothing here duplicates it.
//

import Testing
import Foundation
import CloudKit
@testable import SkyLine

@Suite("Account deletion")
struct AccountDeletionTests {

    // MARK: - Fixtures

    private func report(
        types: [AccountDataEraser.TypeReport],
        local: AccountDataEraser.LocalReport? = .init(clearedKeys: ["saved_flights"], clearedFiles: [], problems: []),
        blockedReason: String? = nil,
        identity: AccountDataEraser.AccountIdentity? = nil
    ) -> AccountDataEraser.EraseReport {
        var report = AccountDataEraser.EraseReport()
        report.types = types
        report.local = local
        report.blockedReason = blockedReason
        report.identity = identity
        return report
    }

    private func identity(_ status: CKAccountStatus) -> AccountDataEraser.AccountIdentity {
        AccountDataEraser.AccountIdentity(
            status: status, userRecordName: "_test", hasUbiquityToken: status == .available, lookupError: nil)
    }

    // MARK: - The one report that may say "deleted"

    @Test("An empty report is not a successful deletion")
    func emptyReportIsNotSuccess() {
        // A default-constructed report has swept nothing. "No type was
        // unconfirmed" is true of it, and meaningless.
        let untouched = AccountDataEraser.EraseReport()
        #expect(!untouched.isCleanSweep)
        #expect(untouched.userFacingProblem != nil)
    }

    @Test("Only a confirmed sweep with a complete local clear reads as deleted")
    func cleanReportHasNothingToReport() {
        let clean = report(types: [
            .init(type: "Flight", status: .confirmedEmpty(matched: 42, deleted: 42)),
            .init(type: "Place", status: .noSuchType)
        ])
        #expect(clean.isCleanSweep)
        #expect(clean.cloudIsClean)
        #expect(clean.userFacingProblem == nil)
    }

    // MARK: - Never started versus failed part way

    @Test("A run that never started says nothing was deleted")
    func blockedRunIsDistinctFromAFailedOne() {
        let blocked = report(
            types: [],
            local: nil,
            blockedReason: "iCloud account status is noAccount (signed out)",
            identity: identity(.noAccount))

        #expect(!blocked.isCleanSweep)
        #expect(!blocked.cloudIsClean)
        #expect(blocked.deleted == 0)

        let problem = blocked.userFacingProblem
        // The user is told the cause they can act on, not the CKAccountStatus.
        #expect(problem?.contains("iCloud") == true)
        #expect(problem?.contains("noAccount") == false)
    }

    @Test("Every blocking account status has a sentence a user can act on")
    func everyBlockingStatusIsExplained() {
        for status in [CKAccountStatus.noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable] {
            let identity = identity(status)
            #expect(!identity.isUsable)
            #expect(identity.userFacingBlockingReason != nil, "\(status) has no user-facing reason")
        }
        #expect(identity(.available).userFacingBlockingReason == nil)
    }

    // MARK: - What the user is told when records survive

    @Test("A partial deletion names what survived and refuses to claim success")
    func partialDeletionNamesWhatSurvived() {
        let partial = report(types: [
            .init(type: "Place", status: .confirmedEmpty(matched: 8, deleted: 8)),
            .init(type: "Flight", status: .survivorsRemain(deleted: 40, survivors: 2, reason: "zoneBusy"))
        ])

        #expect(!partial.isCleanSweep)
        let text = partial.userFacingProblem ?? ""
        #expect(text.contains("flights"))            // not "Flight", not "CKError"
        #expect(text.contains("48"))                 // 8 + 40 actually deleted
        #expect(text.contains("has not been deleted"))
        #expect(text.contains("try again"))
    }

    @Test("A type that never answered is reported, not silently dropped")
    func unconfirmedTypeReachesTheUser() {
        let stuck = report(types: [
            .init(type: "Trip", status: .unconfirmed(deleted: 0, reason: "CKError 3 (networkUnavailable)"))
        ])
        #expect(!stuck.isCleanSweep)
        #expect(stuck.userFacingProblem?.contains("trips") == true)
    }

    @Test("A clean sweep whose local clear was skipped is still not a deletion")
    func skippedLocalClearIsNotADeletion() {
        // `LocalStatePolicy.onlyWhenCloudIsClean` leaves `local` nil when the
        // sweep failed. It must never be read as "there was nothing to clear".
        let cloudCleanLocalSkipped = report(
            types: [.init(type: "Flight", status: .confirmedEmpty(matched: 1, deleted: 1))],
            local: nil)
        #expect(cloudCleanLocalSkipped.cloudIsClean)
        #expect(!cloudCleanLocalSkipped.isCleanSweep)
        #expect(cloudCleanLocalSkipped.userFacingProblem != nil)
    }

    @Test("Local state that could not be cleared is surfaced too")
    func localProblemsReachTheUser() {
        let localFailed = report(
            types: [.init(type: "Flight", status: .confirmedEmpty(matched: 3, deleted: 3))],
            local: .init(clearedKeys: [], clearedFiles: [],
                         problems: ["could not remove pending-review.json: permission denied"]))
        #expect(!localFailed.isCleanSweep)
        #expect(localFailed.userFacingProblem?.contains("this device") == true)
    }

    // MARK: - Plain English

    @Test("No record type reaches the user under its schema name")
    func everyRecordTypeHasAUserFacingNoun() {
        // A CloudKit record type is an implementation detail. "SkyLine couldn't
        // remove your TripEntry" is not a sentence anyone can act on.
        for type in AccountDataEraser.privateRecordTypes + [AccountDataEraser.fixedIDsLabel] {
            let noun = AccountDataEraser.userFacingNoun(for: type)
            #expect(noun != type, "\(type) is shown to the user under its schema name")
            #expect(noun == noun.lowercased(), "\(type) -> \"\(noun)\" reads as a proper noun")
        }
    }

    @Test("Several surviving types are listed, not just the first")
    func multipleSurvivorsAreAllNamed() {
        let many = report(types: [
            .init(type: "Flight", status: .unconfirmed(deleted: 0, reason: "rate limited")),
            .init(type: "Trip", status: .unconfirmed(deleted: 0, reason: "rate limited")),
            .init(type: "Place", status: .unconfirmed(deleted: 0, reason: "rate limited"))
        ])
        let text = many.userFacingProblem ?? ""
        #expect(text.contains("flights"))
        #expect(text.contains("trips"))
        #expect(text.contains("places"))
    }

    // MARK: - The credential

    @Test("A credential that was not revoked tells the user where to finish the job")
    func unrevokedCredentialIsAdmitted() {
        // Guideline 5.1.1(v) wants the token REVOKED. A build with no server
        // behind it cannot, and saying nothing would leave SkyLine listed under
        // the user's Apple Account with no explanation.
        #expect(CredentialRevocation.revoked.userFacingNote == nil)
        #expect(CredentialRevocation.notApplicable(provider: .google).userFacingNote == nil)

        let unavailable = CredentialRevocation.unavailable(reason: "no revocation service is configured")
        #expect(unavailable.userFacingNote == CredentialRevocation.notRevokedNote)
        #expect(CredentialRevocation.failed(reason: "500").userFacingNote == CredentialRevocation.notRevokedNote)
        #expect(CredentialRevocation.notRevokedNote.contains("Sign in with Apple"))
    }

    @Test("The log distinguishes revoked from merely forgotten")
    func revocationLogIsUnambiguous() {
        #expect(CredentialRevocation.revoked.logDescription.contains("revoked with Apple"))
        #expect(CredentialRevocation.unavailable(reason: "no server").logDescription.contains("NOT revoked"))
        #expect(CredentialRevocation.failed(reason: "timeout").logDescription.contains("FAILED"))
    }

    // MARK: - One engine, two callers

    #if DEBUG
    @Test("The debug wipe and account deletion share one implementation")
    func thereIsOnlyOneWipe() {
        // These aliases are the guard against the two paths forking again. If
        // someone re-declares the reporting types inside `DebugDataWipe`, this
        // stops compiling rather than silently drifting.
        let status: DebugDataWipe.TypeStatus = .confirmedEmpty(matched: 1, deleted: 1)
        let shared: AccountDataEraser.TypeStatus = status
        #expect(shared.isConfirmed)

        #expect(DebugDataWipe.reaction(to: CKError(_nsError: NSError(
            domain: CKErrorDomain, code: CKError.Code.invalidArguments.rawValue))) == .wrongField)
        #expect(DebugDataWipe.keysToClear(in: .standard)
            == AccountDataEraser.keysToClear(in: .standard))
        #expect(DebugDataWipe.localFileURLs().map(\.label)
            == AccountDataEraser.localFileURLs().map(\.label))
    }
    #endif
}
