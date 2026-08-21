//
//  OnboardingViewModel.swift
//  SkyLine
//
//  State for the first-run flow, plus the two flags that decide whether it runs
//  at all.
//
//  TWO FLAGS, NOT ONE. "Has the user seen onboarding" and "has the user ever run
//  place detection" are different questions, and collapsing them is what strands
//  a skipper:
//
//    hasSeenOnboarding          — set the moment the flow ends by ANY route,
//                                 including Skip. This is what makes onboarding
//                                 show exactly once.
//    hasCompletedFirstRunDetection
//                               — set only when `FirstRunDetectionView` actually
//                                 finishes. A user who skipped still reads as
//                                 "needs their first detection", so any later
//                                 surface can offer it
//                                 (`OnboardingState.needsFirstRunDetection`) and
//                                 bring the flow back at the detection step with
//                                 `OnboardingState.requestPresentation()`.
//
//  Skipping therefore closes the tour without closing the door: the photo
//  permission and the library scan both stay one call away.
//
//  Note what is NOT here: any photo-library state. Nothing in onboarding calls
//  `requestAccess()`. The one system prompt iOS will ever show is fired from
//  `FirstRunDetectionView`, behind its own primer, which is the only screen that
//  knows what it is about to read.
//

import Foundation
import SwiftUI

// MARK: - Persisted State

/// The durable half of onboarding, and the re-entry point for anything that
/// wants to bring the flow back.
///
/// A plain (non-isolated) namespace on purpose: `SkyLineApp` reads
/// `hasSeenOnboarding` from a `@State` property initialiser, which is not
/// main-actor isolated.
enum OnboardingState {

    private enum Key {
        static let seen = "skyline_onboarding_seen_v1"
        static let firstRunDetection = "skyline_onboarding_first_run_detection_v1"
    }

    /// Has the user reached the end of the first-run flow by any route,
    /// including Skip. Gates presentation, so onboarding shows exactly once.
    static var hasSeenOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Key.seen)
    }

    /// Has first-run place detection ever completed.
    static var hasCompletedFirstRunDetection: Bool {
        UserDefaults.standard.bool(forKey: Key.firstRunDetection)
    }

    /// True for the user who skipped the tour and therefore never got a
    /// populated map. Read this from the place log's empty state or the profile
    /// to offer "Find my places", rather than leaving them on an empty globe.
    static var needsFirstRunDetection: Bool {
        hasSeenOnboarding && !hasCompletedFirstRunDetection
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: Key.seen)
        print("🚀 Onboarding: marked seen")
    }

    static func markFirstRunDetectionCompleted() {
        UserDefaults.standard.set(true, forKey: Key.firstRunDetection)
        print("🚀 Onboarding: marked first-run detection complete")
    }

    /// Brings the flow back for a user who skipped. `SkyLineApp` observes this.
    ///
    /// Defaults to `.detect` rather than `.premise`: someone who has already
    /// seen the pitch and asked to find their places does not need the pitch
    /// again, they need the permission and the scan.
    static func requestPresentation(startingAt page: OnboardingPage = .detect) {
        NotificationCenter.default.post(
            name: .skyLineOnboardingRequested,
            object: page
        )
    }

    #if DEBUG
    /// Wipes both flags so the flow can be re-run on the same install.
    static func resetForDebugging() {
        UserDefaults.standard.removeObject(forKey: Key.seen)
        UserDefaults.standard.removeObject(forKey: Key.firstRunDetection)
        print("🧪 Onboarding: flags reset")
    }
    #endif
}

extension Notification.Name {
    /// Posted by `OnboardingState.requestPresentation(startingAt:)`. The object
    /// is the `OnboardingPage` to start at.
    static let skyLineOnboardingRequested = Notification.Name("SkyLineOnboardingRequested")
}

// MARK: - View Model

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var page: OnboardingPage
    /// The verdict the user tapped on the practice card. Nil until they try one,
    /// which is what unlocks the rest of that page.
    @Published private(set) var practiceVerdict: Verdict?

    // MARK: Dependencies

    private let onFinish: () -> Void
    private var didFinish = false

    // MARK: Init

    init(startingAt page: OnboardingPage = .premise, onFinish: @escaping () -> Void) {
        self.page = page
        self.onFinish = onFinish
    }

    // MARK: Derived

    /// The verdict page will not move on until the lesson has been performed.
    var canAdvance: Bool {
        page == .verdict ? practiceVerdict != nil : true
    }

    var canGoBack: Bool { page.previous != nil }

    /// `.detect` is excluded because `FirstRunDetectionView` carries its own
    /// escape hatch, wired to `skip()`. Two Skip buttons on one screen is a bug.
    var isSkippable: Bool { page.showsChrome }

    // MARK: Navigation

    func advance() {
        guard canAdvance else { return }
        guard let next = page.next else {
            complete(markingDetectionComplete: false)
            return
        }
        page = next
    }

    func goBack() {
        guard let previous = page.previous else { return }
        page = previous
    }

    func selectPractice(_ verdict: Verdict) {
        // Never toggles back to nil. Re-tapping the chosen verdict on a teaching
        // screen should not un-teach it.
        practiceVerdict = verdict
    }

    /// The always-available exit. Closes the tour and leaves
    /// `hasCompletedFirstRunDetection` false, so the user can be offered the
    /// photo permission and the scan again later.
    func skip() {
        print("🚀 Onboarding: skipped at \(page.rawValue)")
        complete(markingDetectionComplete: false)
    }

    /// `FirstRunDetectionView` finished. The only route that marks detection done.
    func finishDetection() {
        complete(markingDetectionComplete: true)
    }

    // MARK: Completion

    private func complete(markingDetectionComplete: Bool) {
        guard !didFinish else { return }
        didFinish = true
        if markingDetectionComplete {
            OnboardingState.markFirstRunDetectionCompleted()
        }
        OnboardingState.markSeen()
        onFinish()
    }
}
