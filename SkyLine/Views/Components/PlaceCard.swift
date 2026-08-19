//
//  PlaceCard.swift
//  SkyLine
//
//  A place the user actually spent time in: photo, name, verdict, date.
//  Takes primitives rather than a model type so it does not block on the
//  clustered-place model landing.
//
//  Three shapes, one grammar:
//
//    .poster   photo-forward tile — the swipe deck and the trip grid.
//    .row      a standalone glass card — one place floating on its own.
//    .listRow  a flat row for a continuous list. No surface of its own, a
//              hairline under the text column, and the verdict rail running the
//              full height of the leading edge. This is what a hundred-row log
//              is built from: stacking a hundred glass cards produces a wall of
//              specular edges, whereas an unbroken column of verdict rails reads
//              as a single ribbon of judgement.
//

import SwiftUI

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let placeCardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let placeCardDateWithYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Dense rows drop day precision: across years, the day is noise and the
    /// twelve characters it costs are the ones the place name needs.
    static let placeCardMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
}

// MARK: - Photo Overlay Ink
/// Ink and scrim for text laid directly over an arbitrary photograph.
///
/// A photograph has no theme, so this pair is deliberately theme-independent —
/// but it is still built from palette tokens rather than `Color.white` /
/// `Color.black`, so that the day a real `onPhoto` / `photoScrim` token lands
/// there is exactly one place to change.
enum PhotoOverlay {
    /// Near-white, borrowed from the dark palette's text token.
    static var ink: Color { ThemeColors.dark.text }
    /// The app's deep navy, used at partial opacity as a legibility veil. Navy
    /// rather than neutral black keeps a photo sitting in the same world as the
    /// globe behind it.
    static var scrim: Color { ThemeColors.dark.background }
}

// MARK: - Place Card Style
enum PlaceCardStyle {
    /// Photo-forward tile for the swipe deck and the trip grid.
    case poster
    /// A standalone glass card, for a place shown on its own.
    case row
    /// A flat row for a continuous list — no surface, hairline separator.
    case listRow
}

// MARK: - Place Card
struct PlaceCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let name: String
    let date: Date
    var subtitle: String? = nil
    var verdict: Verdict? = nil
    var image: UIImage? = nil
    var photoCount: Int = 0
    var style: PlaceCardStyle = .poster
    var showsYear: Bool = false
    /// Glyph shown when there is no photograph. Pass the place's category symbol
    /// so an unphotographed place still says what kind of thing it is.
    var placeholderSystemImage: String = "photo"
    /// `.listRow` only. Drop it on the last row of a section so the hairline does
    /// not float under the group.
    var showsSeparator: Bool = true
    var onTap: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var posterHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var rowThumbSize: CGFloat = 56

    /// Fixed, not scaled: the rail is a hairline of colour, and a rail that grew
    /// with Dynamic Type would stop reading as an edge and start reading as a block.
    private static let railWidth: CGFloat = 3
    /// The gutter either side of the row thumbnail.
    private static let rowGutter: CGFloat = AppSpacing.md - 4

    private var dateText: String {
        switch style {
        case .listRow:
            let formatter = showsYear ? DateFormatter.placeCardMonthYear : DateFormatter.placeCardDate
            return formatter.string(from: date)
        case .poster, .row:
            let formatter = showsYear ? DateFormatter.placeCardDateWithYear : DateFormatter.placeCardDate
            return formatter.string(from: date)
        }
    }

    private var tapShape: AnyShape {
        switch style {
        case .poster: return AnyShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        case .row: return AnyShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        case .listRow: return AnyShape(Rectangle())
        }
    }

    var body: some View {
        if let onTap {
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onTap()
            } label: {
                cardBody
            }
            .buttonStyle(
                PlaceCardPressStyle(
                    theme: themeManager.currentTheme,
                    shape: tapShape,
                    // A flat row has no surface of its own, so the press state is
                    // where it briefly gets one. A glass card already responds to
                    // touch, so it only dims.
                    fillsOnPress: style == .listRow
                )
            )
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        Group {
            switch style {
            case .poster: posterBody
            case .row: rowBody
            case .listRow: listRowBody
            }
        }
        .contentShape(tapShape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var accessibilitySummary: String {
        var parts: [String] = [name, dateText]
        if let subtitle { parts.append(subtitle) }
        if photoCount > 0 { parts.append("\(photoCount) photos") }
        if let verdict {
            parts.append(verdict.accessibilityLabel)
        } else {
            parts.append("Not rated")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Poster

    private var posterBody: some View {
        let theme = themeManager.currentTheme
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            photoLayer
                .frame(height: posterHeight)
                .frame(maxWidth: .infinity)
                // A concentric child keeps its corner curvature in step with the
                // parent's, instead of guessing a smaller radius.
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                .overlay { legibilityGradient }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(name)
                    .appFont(.placeName)
                    .foregroundStyle(PhotoOverlay.ink)

                HStack(spacing: AppSpacing.sm) {
                    Text(dateText)
                    if let subtitle {
                        Text("·")
                        Text(subtitle)
                    }
                    if photoCount > 0 {
                        Text("·")
                        Label("\(photoCount)", systemImage: "photo.stack")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .appFont(.placeMeta)
                .foregroundStyle(PhotoOverlay.ink.opacity(0.85))
            }
            .padding(AppSpacing.md)

            if let verdict {
                VerdictBadge(verdict: verdict)
                    .padding(AppSpacing.sm + 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .padding(AppSpacing.xs)
        .skylineGlassCard(theme: theme)
        .containerShape(cardShape)
    }

    /// Text over an arbitrary photo needs its own contrast floor. The glass card
    /// behind the photo cannot supply it, so scrim the bottom third directly.
    private var legibilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: PhotoOverlay.scrim.opacity(0), location: 0.35),
                .init(color: PhotoOverlay.scrim.opacity(0.30), location: 0.62),
                .init(color: PhotoOverlay.scrim.opacity(0.72), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: - Row (standalone glass card)

    private var rowBody: some View {
        let theme = themeManager.currentTheme
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

        return rowContent(
            theme: theme,
            thumbShape: AnyShape(ConcentricRectangle(corners: .concentric, isUniform: true)),
            compactMeta: false
        )
        .padding(AppSpacing.sm + 2)
        .skylineGlass(.card, in: cardShape, theme: theme)
        .containerShape(cardShape)
    }

    // MARK: - List Row (flat, for continuous lists)

    private var listRowBody: some View {
        let theme = themeManager.currentTheme

        return rowContent(
            theme: theme,
            thumbShape: AnyShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)),
            compactMeta: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { listSeparator(theme: theme) }
    }

    /// Inset so the hairline starts where the text starts. It never crosses the
    /// verdict rail, which is what keeps the rail column continuous down the list.
    @ViewBuilder
    private func listSeparator(theme: AppTheme) -> some View {
        if showsSeparator {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Self.railWidth + Self.rowGutter * 2 + rowThumbSize)
                Rectangle()
                    .fill(theme.colors.border)
                    .frame(height: 0.5)
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Shared Row Content

    private func rowContent(theme: AppTheme, thumbShape: AnyShape, compactMeta: Bool) -> some View {
        HStack(spacing: 0) {
            VerdictRail(verdict: verdict, width: Self.railWidth)

            HStack(spacing: Self.rowGutter) {
                photoLayer
                    .frame(width: rowThumbSize, height: rowThumbSize)
                    .clipShape(thumbShape)
                    // `surface` sits under two percent off `background` in both
                    // palettes — correct for a recessed well, not enough to
                    // describe an edge — so an empty thumbnail gets a hairline to
                    // hold its shape. A real photograph describes its own edge and
                    // does not get one.
                    .overlay {
                        if image == nil {
                            thumbShape.stroke(theme.colors.border, lineWidth: 1)
                        }
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(name)
                        .appFont(.bodyBold, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)

                    Text(metaText(compact: compactMeta))
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VerdictPip(verdict: verdict)
            }
            .padding(.leading, Self.rowGutter)
            .padding(.trailing, AppSpacing.xs)
            .padding(.vertical, AppSpacing.sm + 2)
        }
    }

    /// One line, never two. In a dense row the city is what the reader is
    /// scanning for, so the date yields to it and the section header carries the
    /// time context instead.
    private func metaText(compact: Bool) -> String {
        let locality = (subtitle?.isEmpty == false) ? subtitle : nil
        if compact { return locality ?? dateText }
        return [dateText, locality].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoLayer: some View {
        let theme = themeManager.currentTheme

        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                theme.colors.surface
                Image(systemName: placeholderSystemImage)
                    .font(AppTypography.mono(style == .poster ? .title2 : .footnote))
                    .foregroundStyle(theme.colors.textSecondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

// MARK: - Press Style
/// Instant, unanimated press feedback — a state change rather than a motion, so
/// it needs no Reduce Motion gate.
private struct PlaceCardPressStyle: ButtonStyle {
    let theme: AppTheme
    let shape: AnyShape
    let fillsOnPress: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if fillsOnPress {
                    // `border` rather than `surface`: it is the one token that is a
                    // clear step off `background` in BOTH palettes, where `surface`
                    // is under two percent away in each.
                    shape
                        .fill(theme.colors.border)
                        .opacity(configuration.isPressed ? 1 : 0)
                }
            }
            .opacity(fillsOnPress ? 1 : (configuration.isPressed ? 0.86 : 1))
    }
}

// MARK: - Previews
#Preview("Poster") {
    PlaceCard(
        name: "Kissa Sakaiki",
        date: Date(),
        subtitle: "Shibuya",
        verdict: .worthIt,
        photoCount: 14
    )
    .padding()
    .environmentObject(ThemeManager())
}

#Preview("List rows") {
    VStack(spacing: 0) {
        PlaceCard(name: "Kissa Sakaiki", date: Date(), subtitle: "Shibuya, Japan · 3 visits", verdict: .worthIt, style: .listRow, showsYear: true, placeholderSystemImage: "cup.and.saucer", onTap: {})
        PlaceCard(name: "Shibuya Sky", date: Date(), subtitle: "Shibuya, Japan", verdict: .fine, style: .listRow, showsYear: true, placeholderSystemImage: "binoculars", onTap: {})
        PlaceCard(name: "Takeshita Street", date: Date(), subtitle: "Harajuku, Japan", verdict: .skip, style: .listRow, showsYear: true, placeholderSystemImage: "bag", onTap: {})
        PlaceCard(name: "Nakameguro", date: Date(), subtitle: "Meguro, Japan", style: .listRow, showsYear: true, placeholderSystemImage: "map", showsSeparator: false, onTap: {})
    }
    .padding()
    .environmentObject(ThemeManager())
}

#Preview("Glass row") {
    PlaceCard(name: "Kissa Sakaiki", date: Date(), subtitle: "Shibuya", verdict: .worthIt, style: .row, showsYear: true)
        .padding()
        .environmentObject(ThemeManager())
}
