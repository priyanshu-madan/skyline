//
//  OnboardingPage.swift
//  SkyLine
//
//  The beats of first run, as data. No views here, so the copy and the ordering
//  can be read (and argued about) in one screen.
//
//  WHY THIS ORDER.
//
//    1. premise  — what the app is, in one sentence. Nothing can be asked for
//                  until this lands.
//    2. verdict  — the vocabulary, PERFORMED rather than read. The user taps a
//                  real verdict onto a real card before being asked for
//                  anything. A tutorial you perform is remembered; one you read
//                  is not.
//    3. detect   — the permission and the payoff, in that order, both owned by
//                  `FirstRunDetectionView`.
//
//  WHERE THE PHOTO ASK WENT. iOS shows the photo prompt exactly once per
//  install, so the sentence immediately before it has to be the true one — and
//  the only screen that knows what is about to be read is the one about to read
//  it. `FirstRunDetectionView` opens on a primer written for a whole-library
//  pass (it can promise things this file cannot: that days near home are
//  ignored, that the scan covers the user's entire history) and calls into the
//  system prompt from a button and from nowhere else. Onboarding's job is
//  therefore to put that ask in the right PLACE in the arc — after the user has
//  performed a verdict, so "we group your photos into places for you to judge"
//  refers to something they have already done with their thumb — and then get
//  out of the way. Writing a second, vaguer primer to sit in front of it would
//  spend the one shot twice.
//
//  SKIP is the emotional core of the product, so it is not a footnote on the
//  verdict page — it is the punchline. See `verdictLesson(for:)`: whichever
//  verdict the user tries, the follow-up names Skip as the one thing a
//  saved-places list can never record.
//

import Foundation

// MARK: - Onboarding Page

enum OnboardingPage: String, CaseIterable, Identifiable, Hashable {
    /// What SkyLine is.
    case premise
    /// Worth it / Fine / Skip, learned by tapping one.
    case verdict
    /// Handoff to `FirstRunDetectionView`: the photo primer, the one system
    /// prompt, the library scan, and the first populated map.
    case detect

    var id: String { rawValue }

    // MARK: Progress

    /// The pages that carry the step indicator.
    ///
    /// `.detect` is excluded: it is handed to `FirstRunDetectionView`, which
    /// owns its own chrome and narrates its own progress against a real photo
    /// count. A "3 of 3" pill floating over that would be two progress
    /// indicators arguing with each other.
    static let indicated: [OnboardingPage] = [.premise, .verdict]

    /// 1-based position in the indicator, or `nil` for a page that is not indicated.
    var stepNumber: Int? {
        OnboardingPage.indicated.firstIndex(of: self).map { $0 + 1 }
    }

    /// Whether onboarding draws its own top bar over this page.
    var showsChrome: Bool { stepNumber != nil }

    var next: OnboardingPage? {
        switch self {
        case .premise: return .verdict
        case .verdict: return .detect
        case .detect:  return nil
        }
    }

    var previous: OnboardingPage? {
        switch self {
        case .premise: return nil
        case .verdict: return .premise
        // No way back out of detection. By the time that screen is up the
        // system prompt may already have been answered, and a back button that
        // returns to a pitch for a question iOS will never ask again is a lie.
        case .detect:  return nil
        }
    }

    // MARK: Copy

    var systemImage: String {
        switch self {
        case .premise: return "globe.europe.africa.fill"
        case .verdict: return "hand.tap.fill"
        case .detect:  return "mappin.and.ellipse"
        }
    }

    /// The one sentence per page. Kept short enough to survive monospaced type
    /// on a 375pt screen at accessibility sizes.
    var title: String {
        switch self {
        case .premise:
            return "Everywhere you went, and whether it was worth it."
        case .verdict:
            return "Three answers. The third is the point."
        case .detect:
            return "Finding your first places"
        }
    }

    var message: String {
        switch self {
        case .premise:
            return "SkyLine logs the places you have actually been, one verdict each. That log becomes your map — and a guide worth handing to a friend."
        case .verdict:
            return "Every place gets exactly one. Try it on this one."
        case .detect:
            return "Reading your library and grouping it into places."
        }
    }

    /// `nil` where the page supplies its own call to action.
    var primaryActionTitle: String? {
        switch self {
        case .premise: return "Start"
        // Names the next screen rather than dismissing this one. This is the
        // bridge into the photo ask: the user is agreeing to a goal, not
        // tapping Next.
        case .verdict: return "Find where I have been"
        case .detect:  return nil
        }
    }

    /// Shown in place of the primary button until the user has performed the
    /// verdict tap. A dead disabled button teaches nothing; a nudge does.
    var interactionHint: String? {
        switch self {
        case .verdict: return "Pick one to keep going."
        default: return nil
        }
    }

    // MARK: The Skip lesson

    /// The line revealed after the user tries a verdict.
    ///
    /// Every branch lands on the same idea, because it is the idea the whole
    /// product is built on: Skip is the verdict no saved-places list can hold.
    /// The user gets it as a payoff for the tap they just made, not as a bullet
    /// they scrolled past.
    static func verdictLesson(for verdict: Verdict) -> String {
        switch verdict {
        case .worthIt:
            return "That is the easy one. Skip is the interesting one — no saved-places list can record that you went, and would not go back."
        case .fine:
            return "Honest. Most places are fine. But Skip is the interesting one — no saved-places list can record that you went, and would not go back."
        case .skip:
            return "That is the one no saved-places list can hold. Here it is a real answer, worth as much as the other two."
        }
    }

    // MARK: Accessibility

    var accessibilityProgressLabel: String {
        guard let stepNumber else { return title }
        return "Step \(stepNumber) of \(OnboardingPage.indicated.count)"
    }
}
