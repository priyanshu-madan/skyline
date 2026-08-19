//
//  Verdict.swift
//  SkyLine
//
//  The one judgement a user makes about a place: Worth it / Fine / Skip.
//

import SwiftUI
import Foundation

// MARK: - Verdict
enum Verdict: String, Codable, CaseIterable, Identifiable, Hashable {
    case worthIt = "worth_it"
    case fine = "fine"
    case skip = "skip"

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .worthIt: return "Worth it"
        case .fine: return "Fine"
        case .skip: return "Skip"
        }
    }

    /// Fits a badge over a photo thumbnail without shrinking.
    var shortName: String {
        switch self {
        case .worthIt: return "WORTH IT"
        case .fine: return "FINE"
        case .skip: return "SKIP"
        }
    }

    /// Three deliberately different silhouettes — burst, circle, diamond — so the
    /// verdict is legible at 12pt in greyscale and to anyone with a colour vision
    /// deficiency. The colour is the second signal, never the only one.
    var systemImage: String {
        switch self {
        case .worthIt: return "checkmark.seal.fill"
        case .fine: return "equal.circle.fill"
        case .skip: return "xmark.diamond.fill"
        }
    }

    /// Unfilled variant, for the resting state of a selector.
    var systemImageOutline: String {
        switch self {
        case .worthIt: return "checkmark.seal"
        case .fine: return "equal.circle"
        case .skip: return "xmark.diamond"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .worthIt: return "Verdict: worth it"
        case .fine: return "Verdict: fine"
        case .skip: return "Verdict: skip"
        }
    }

    /// Best-first ordering for guide export and map ranking.
    var sortRank: Int {
        switch self {
        case .worthIt: return 0
        case .fine: return 1
        case .skip: return 2
        }
    }

    /// Hex the globe layer uses for a place marker. Mirrors `color(for:)` in the
    /// dark palette, which is what the globe always renders against.
    var globeHexColor: String {
        switch self {
        case .worthIt: return "#2FD1C4"
        case .fine: return "#F2B33D"
        case .skip: return "#FF7A6B"
        }
    }

    // MARK: - Theme Colors

    func color(for theme: AppTheme) -> Color {
        switch self {
        case .worthIt: return theme.colors.verdictWorthIt
        case .fine: return theme.colors.verdictFine
        case .skip: return theme.colors.verdictSkip
        }
    }

    /// Opaque fill for the Reduce Transparency path.
    func surface(for theme: AppTheme) -> Color {
        switch self {
        case .worthIt: return theme.colors.verdictWorthItSurface
        case .fine: return theme.colors.verdictFineSurface
        case .skip: return theme.colors.verdictSkipSurface
        }
    }

    // MARK: - Decoding

    /// Tolerant decode for records written before the raw values settled.
    /// Mirrors the `DataSource(rawValue:) ?? .manual` fallback in CloudKitService.
    static func lenient(_ raw: String?) -> Verdict? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        switch raw {
        case "worth_it", "worthit", "worth it", "good", "great", "recommend", "loved":
            return .worthIt
        case "fine", "ok", "okay", "neutral", "meh", "average":
            return .fine
        case "skip", "bad", "avoid", "regret":
            return .skip
        default:
            print("⚠️ Verdict: unrecognised raw value '\(raw)'")
            return nil
        }
    }

    /// Total decoder: an unknown raw value resolves to `.fine` rather than
    /// throwing.
    ///
    /// This is not defensive padding. Synthesised `Codable` conformance throws
    /// on an unrecognised raw value, and a throw inside a `[Visit]` blob takes
    /// every visit in that blob down with it - which is precisely the failure
    /// that silently emptied the flight list in commit d962e9e when two
    /// `DataSource` cases were removed. A verdict is a user opinion; losing the
    /// whole record because one string drifted is never the right trade.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(),
              let raw = try? container.decode(String.self) else {
            self = .fine
            return
        }
        self = Verdict.lenient(raw) ?? .fine
    }

    // MARK: - Globe

    /// Marker colour for a place the user has not rated yet.
    static let unratedGlobeHexColor = "#8E8E93"

    static func globeHexColor(for verdict: Verdict?) -> String {
        verdict?.globeHexColor ?? Verdict.unratedGlobeHexColor
    }
}
