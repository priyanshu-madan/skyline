//
//  VerdictChip.swift
//  SkyLine
//
//  The verdict vocabulary. Everything in the app that renders an opinion is
//  built from one of these, so the three verdicts read identically wherever
//  they appear.
//
//    VerdictRail             — the 3pt colour spine on the leading edge of a list row.
//    VerdictPip              — the trailing swatch: silhouette in an opaque verdict tint.
//    VerdictBadge            — passive glass capsule, for photos and map callouts.
//    VerdictChip             — tappable. Pill by default; a stat tile when given a
//                              count; a large stamp when asked for one.
//    VerdictPicker           — the three-up selector.
//    VerdictDistributionBar  — proportion of a whole log, as one hairline bar.
//
//  Colour is never the only signal. Every one of these pairs the verdict's
//  colour with its SF Symbol, and the three symbols are deliberately different
//  silhouettes (burst / circle / diamond) so the verdict survives greyscale,
//  colour-vision deficiency and Differentiate Without Color.
//

import SwiftUI

// MARK: - Verdict Rail
/// The leading spine of a list row. Three points wide, full row height, no gap
/// between rows — so a column of rows reads as one continuous ribbon of
/// judgement that is scannable at arm's length before a single word is read.
///
/// An unrated place keeps its place in the column with a `border` rail rather
/// than a hole, so the ribbon never breaks and "not decided yet" is visibly a
/// state rather than an absence.
struct VerdictRail: View {
    @EnvironmentObject var themeManager: ThemeManager

    let verdict: Verdict?
    var width: CGFloat = 3

    var body: some View {
        let theme = themeManager.currentTheme

        return Capsule(style: .continuous)
            .fill(verdict?.color(for: theme) ?? theme.colors.border)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

// MARK: - Verdict Pip
/// The trailing anchor of a list row: the verdict's silhouette on its own opaque
/// tint. Opaque rather than glass on purpose — a pip is a swatch of ink, not a
/// surface, and the verdict surface tokens are per-theme so the fill/ink pair
/// clears contrast in both palettes without a single branch here.
struct VerdictPip: View {
    @EnvironmentObject var themeManager: ThemeManager

    let verdict: Verdict?

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 28

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = verdict?.color(for: theme) ?? theme.colors.textSecondary
        let fill = verdict?.surface(for: theme) ?? theme.colors.surface

        return Image(systemName: verdict?.systemImage ?? "circle.dashed")
            .font(AppTypography.mono(.footnote, weight: .semibold))
            .foregroundStyle(ink)
            .symbolRenderingMode(.hierarchical)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(verdict == nil ? theme.colors.border : ink.opacity(0.35), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verdict?.accessibilityLabel ?? "Not rated"))
    }
}

// MARK: - Verdict Badge
/// Read-only verdict marker. Icon always present; the label can be dropped when
/// space is tight, but the accessibility label never is.
struct VerdictBadge: View {
    @EnvironmentObject var themeManager: ThemeManager

    let verdict: Verdict
    var showsLabel: Bool = true
    var size: Size = .regular

    enum Size {
        case compact
        case regular

        var textStyle: AppTextStyle {
            switch self {
            case .compact: return .footnote
            case .regular: return .verdictLabel
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return AppSpacing.sm
            case .regular: return AppSpacing.sm + 2
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 3
            case .regular: return 5
            }
        }
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = verdict.color(for: theme)

        HStack(spacing: AppSpacing.xs + 1) {
            Image(systemName: verdict.systemImage)
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)

            if showsLabel {
                Text(verdict.shortName)
                    .foregroundStyle(theme.colors.text)
            }
        }
        .appFont(size.textStyle)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .skylineGlassCapsule(tint: ink.opacity(0.30), theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verdict.accessibilityLabel))
    }
}

// MARK: - Verdict Chip Shape
/// Which silhouette a `VerdictChip` takes.
enum VerdictChipShape {
    /// A capsule pill, or the stat tile when a count is supplied. The chip's
    /// historical behaviour and its default.
    case automatic
    /// The compact pill, even if a count is supplied.
    case pill
    /// The stat tile — number first, verdict beneath — even with no count.
    case tile
    /// A large flat stamp: a filled circle carrying the verdict's silhouette,
    /// with the noun beneath it. For the one screen where choosing a verdict IS
    /// the screen, so the app's central act stops looking like a list filter.
    case stamp
}

// MARK: - Verdict Chip
/// The interactive form, in three shapes.
///
///   `.pill`  — a capsule. The compact form used when the chip is asking a
///              question inside a row of other chrome.
///   `.tile`  — a stat tile: the number leads, the verdict labels it. Used when
///              the chip is *also* the summary, as on the place log, where the
///              filter row doubles as the tally.
///   `.stamp` — a 64pt circle in the verdict's own surface colour, symbol in the
///              verdict's ink, noun beneath. Three of these read as three OBJECTS
///              you choose between rather than three buttons you press.
///
/// Selected state is carried by four redundant signals — tint, filled-vs-outline
/// symbol, a stroke ring and (under Differentiate Without Color) a checkmark —
/// so it survives greyscale and colour-vision deficiency. The stamp deliberately
/// keeps the distinct silhouette AND the noun: a bare colour-coded circle fails
/// greyscale, colour-vision deficiency and Differentiate Without Color all at once.
struct VerdictChip: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let verdict: Verdict
    var isSelected: Bool = false
    var showsLabel: Bool = true
    /// Supplying a count switches the chip to its stat-tile shape, unless `shape`
    /// says otherwise.
    var count: Int? = nil
    /// Overrides the shape the count would otherwise imply.
    var shape: VerdictChipShape = .automatic
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44
    /// The stamp's diameter. Large on purpose: the most important interaction on
    /// a screen should be the largest target on it.
    @ScaledMetric(relativeTo: .body) private var stampDiameter: CGFloat = 64

    /// `.automatic` resolved against whether a count was supplied.
    private var resolvedShape: VerdictChipShape {
        switch shape {
        case .automatic: return count == nil ? .pill : .tile
        case .pill, .tile, .stamp: return shape
        }
    }

    private var isStamp: Bool {
        if case .stamp = resolvedShape { return true }
        return false
    }

    /// The chip's outline — used for glass, the selection ring and the hit region.
    private var outlineShape: AnyShape {
        switch resolvedShape {
        case .pill, .automatic:
            return AnyShape(Capsule(style: .continuous))
        case .tile:
            return AnyShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        case .stamp:
            // The circle is drawn inside the stamp; this is only the tap target,
            // and it has to include the label so the noun is tappable too.
            return AnyShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = verdict.color(for: theme)

        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        } label: {
            Group {
                switch resolvedShape {
                case .stamp: stampContent(theme: theme, ink: ink)
                case .tile: tileContent(theme: theme, ink: ink)
                case .pill, .automatic: pillContent(theme: theme, ink: ink)
                }
            }
            .contentShape(outlineShape)
        }
        .buttonStyle(.plain)
        .modifier(
            ChipSurface(
                // A stamp is an opaque object, not a pane of glass: it draws its
                // own fill and its own edge, so it must not also take a glass
                // backdrop or a second ring around the label.
                isGlass: !isStamp,
                shape: outlineShape,
                tint: isSelected ? ink.opacity(0.55) : nil,
                ring: isSelected ? ink : nil,
                theme: theme
            )
        )
        .modifier(GlassID(id: verdict.rawValue, namespace: isStamp ? nil : namespace))
        .animation(.easeInOut(duration: 0.22), value: isSelected)
        .accessibilityLabel(Text(verdict.displayName))
        .accessibilityValue(Text(count.map { $0 == 1 ? "1 place" : "\($0) places" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Pill

    private func pillContent(theme: AppTheme, ink: Color) -> some View {
        HStack(spacing: AppSpacing.sm - 2) {
            symbol(ink: ink)

            if showsLabel {
                Text(verdict.displayName)
                    .foregroundStyle(theme.colors.text)
            }

            differentiator(theme: theme)
        }
        .appFont(.verdictLabel)
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tile

    private func tileContent(theme: AppTheme, ink: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            // The number is the loudest thing in the tile and it is verdict-inked,
            // which is what turns the filter row into the log's tally.
            Text("\(count ?? 0)")
                .appFont(.title, lineLimit: .exactly(1))
                .foregroundStyle(ink)
                .contentTransition(.numericText())

            HStack(spacing: AppSpacing.xs) {
                symbol(ink: ink)

                if showsLabel {
                    Text(verdict.displayName)
                        .foregroundStyle(theme.colors.text)
                }

                differentiator(theme: theme)
            }
            // Two lines, so that at accessibility type sizes "Worth it" wraps
            // rather than shrinking towards illegibility. It never wraps at the
            // default size — three tiles across a 375pt screen fit on one line.
            .appFont(.verdictLabel, lineLimit: .exactly(2))
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, AppSpacing.sm + 2)
        .padding(.horizontal, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
    }

    // MARK: Stamp

    /// The verdict as an object: a flat disc of the verdict's own surface colour
    /// with its silhouette struck into it, and the noun underneath.
    ///
    /// Opaque rather than glass, and identical in both themes' logic, because the
    /// `verdict.surface` / `verdict.color` pair is defined per palette to clear
    /// contrast without a branch here — the same pairing `VerdictPip` uses, scaled
    /// up from a 28pt swatch to a 64pt target.
    private func stampContent(theme: AppTheme, ink: Color) -> some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(verdict.surface(for: theme))

                Image(systemName: isSelected ? verdict.systemImage : verdict.systemImageOutline)
                    // @ScaledMetric-free symbol sizing: `mono` is relative to a text
                    // style, so the glyph grows with Dynamic Type in step with the
                    // circle around it.
                    .font(AppTypography.mono(.title2, weight: .semibold))
                    .foregroundStyle(ink)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: stampDiameter, height: stampDiameter)
            // The surface tints are quiet by design, so the disc gets its own edge
            // rather than relying on the fill to separate it from the card behind.
            .overlay {
                Circle().strokeBorder(
                    isSelected ? ink : ink.opacity(0.35),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }

            if showsLabel {
                HStack(spacing: AppSpacing.xs) {
                    Text(verdict.displayName)
                        .foregroundStyle(theme.colors.text)

                    differentiator(theme: theme)
                }
                // Two lines so "Worth it" wraps at accessibility sizes rather than
                // shrinking towards illegibility.
                .appFont(.verdictLabel, lineLimit: .exactly(2))
                .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity)
    }

    // MARK: Parts

    private func symbol(ink: Color) -> some View {
        Image(systemName: isSelected ? verdict.systemImage : verdict.systemImageOutline)
            .foregroundStyle(ink)
            .symbolRenderingMode(.hierarchical)
            .imageScale(count == nil ? .medium : .small)
    }

    @ViewBuilder
    private func differentiator(theme: AppTheme) -> some View {
        if differentiateWithoutColor && isSelected {
            Image(systemName: "checkmark")
                .foregroundStyle(theme.colors.text)
                .imageScale(.small)
        }
    }
}

// MARK: - Chip Surface
/// The chip's backdrop and selection ring, in one place so the stamp can opt out
/// of both without duplicating the rest of the chip's body.
private struct ChipSurface: ViewModifier {
    let isGlass: Bool
    let shape: AnyShape
    let tint: Color?
    let ring: Color?
    let theme: AppTheme

    func body(content: Content) -> some View {
        Group {
            if isGlass {
                content.skylineGlass(
                    .control,
                    in: shape,
                    tint: tint,
                    interactive: true,
                    theme: theme
                )
            } else {
                content
            }
        }
        .overlay {
            // A ring is the colour-independent selection cue.
            if isGlass, let ring {
                shape.stroke(ring, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Glass Identity Helper
/// Attaches `glassEffectID` only when a namespace was supplied, so chips can morph
/// into one another inside a `GlassEffectContainer` without forcing every call site
/// to own a `@Namespace`.
private struct GlassID: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content
                .glassEffectID(id, in: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else {
            content
        }
    }
}

// MARK: - Verdict Picker
/// The three-up selector. Wrapped in one `GlassEffectContainer` so the chips share
/// a backdrop and the selection blob flows between them instead of cross-fading.
///
/// Pass `counts` to get the stat-tile form: the same control then answers
/// "how many did I mark skip?" and "show me only the skips" with one object.
struct VerdictPicker: View {
    @EnvironmentObject var themeManager: ThemeManager

    @Binding var selection: Verdict?
    var showsLabels: Bool = true
    var counts: [Verdict: Int]? = nil

    @Namespace private var glassNamespace

    var body: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Verdict.allCases) { verdict in
                    VerdictChip(
                        verdict: verdict,
                        isSelected: selection == verdict,
                        showsLabel: showsLabels,
                        count: counts.map { $0[verdict] ?? 0 },
                        namespace: glassNamespace
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = (selection == verdict) ? nil : verdict
                        }
                        print("🎯 VerdictPicker: selected \(verdict.rawValue)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Verdict"))
    }
}

// MARK: - Verdict Distribution Bar
/// The whole log as one hairline: what proportion of everywhere you went was
/// worth it, fine, skipped, or still undecided.
///
/// Unrated is a segment rather than empty space, so the bar always reads as a
/// complete accounting and the undecided remainder is visible instead of implied.
struct VerdictDistributionBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let counts: [Verdict: Int]
    var unratedCount: Int = 0

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 10

    private var total: Int {
        Verdict.allCases.reduce(unratedCount) { $0 + (counts[$1] ?? 0) }
    }

    private func width(for count: Int, in available: CGFloat) -> CGFloat {
        guard total > 0, count > 0 else { return 0 }
        return available * CGFloat(count) / CGFloat(total)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Verdict.allCases) { verdict in
                    Rectangle()
                        .fill(verdict.color(for: theme))
                        .frame(width: width(for: counts[verdict] ?? 0, in: proxy.size.width))
                }

                Rectangle()
                    .fill(theme.colors.border)
                    .frame(width: width(for: unratedCount, in: proxy.size.width))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: barHeight)
        // The track shows through wherever rounding leaves a sliver, and is the
        // whole bar when nothing has been logged yet.
        .background(theme.colors.border)
        .clipShape(Capsule(style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        guard total > 0 else { return "Nothing logged yet" }

        var parts = Verdict.allCases.compactMap { verdict -> String? in
            let count = counts[verdict] ?? 0
            guard count > 0 else { return nil }
            return "\(count) \(verdict.displayName.lowercased())"
        }
        if unratedCount > 0 {
            parts.append("\(unratedCount) not rated")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews
#Preview("Chips") {
    VStack(spacing: AppSpacing.lg) {
        HStack {
            ForEach(Verdict.allCases) { VerdictBadge(verdict: $0) }
        }
        HStack(spacing: AppSpacing.md) {
            ForEach(Verdict.allCases) { VerdictPip(verdict: $0) }
            VerdictPip(verdict: nil)
        }
        VerdictDistributionBar(counts: [.worthIt: 12, .fine: 5, .skip: 4], unratedCount: 9)
        VerdictPickerPreviewHost()
    }
    .padding()
    .environmentObject(ThemeManager())
}

private struct VerdictPickerPreviewHost: View {
    @State private var selection: Verdict? = .worthIt

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            VerdictPicker(selection: $selection)
            VerdictPicker(selection: $selection, counts: [.worthIt: 12, .fine: 5, .skip: 4])
        }
    }
}

#Preview("Stamps") {
    StampPreviewHost()
        .padding()
        .environmentObject(ThemeManager())
}

private struct StampPreviewHost: View {
    @State private var selection: Verdict?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            ForEach(Verdict.allCases) { verdict in
                VerdictChip(
                    verdict: verdict,
                    isSelected: selection == verdict,
                    shape: .stamp
                ) {
                    selection = (selection == verdict) ? nil : verdict
                }
            }
        }
    }
}
