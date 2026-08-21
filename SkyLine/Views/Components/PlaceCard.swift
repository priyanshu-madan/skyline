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
//    .listRow  a flat, TEXT-ONLY row for a continuous list. No surface of its
//              own, a hairline under the text column, and the verdict rail
//              running the full height of the leading edge. This is what a
//              hundred-row log is built from: stacking a hundred glass cards
//              produces a wall of specular edges, whereas an unbroken column of
//              verdict rails reads as a single ribbon of judgement.
//
//  Photographs belong where content is PRESENTED (.poster, .row); text belongs
//  where content is SCANNED (.listRow). A list row that reserved a thumbnail
//  spent 68pt of a 375pt screen on a slot that is empty for every place logged
//  without a photo — and an empty slot drawn with a border is a hole running
//  down the leading edge, competing with the very rail it sits beside. Dropping
//  it takes the name column from 216pt (~22 monospaced characters) to 284pt
//  (~29), which is the difference between "Nakameguro Riverside Walk" fitting
//  and truncating.
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
    /// A flat, text-only row for a continuous list — no surface, no thumbnail,
    /// hairline separator.
    case listRow
}

// MARK: - Row Name Alignment
/// Centres the trailing verdict pip on the place NAME rather than on the row box.
///
/// In a text-only row the name is what the verdict is a verdict *about*. A pip
/// centred on the whole two-line column sits level with the gap between name and
/// meta, so it reads as belonging to neither.
private enum PlaceRowNameAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let placeRowName = VerticalAlignment(PlaceRowNameAlignment.self)
}

// MARK: - Place Card
struct PlaceCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let name: String
    let date: Date
    var subtitle: String? = nil
    var verdict: Verdict? = nil
    /// Ignored by `.listRow` — see the note at the top of the file.
    var image: UIImage? = nil
    var photoCount: Int = 0
    var style: PlaceCardStyle = .poster
    var showsYear: Bool = false
    /// Glyph shown when there is no photograph. Pass the place's category symbol
    /// so an unphotographed place still says what kind of thing it is.
    /// Unused by `.listRow`, which carries no photo column at all.
    var placeholderSystemImage: String = "photo"
    /// `.listRow` only. Drop it on the last row of a section so the hairline does
    /// not float under the group.
    var showsSeparator: Bool = true
    var onTap: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var posterHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var rowThumbSize: CGFloat = 56

    /// Measured height of the poster's caption block, so the scrim can turn solid
    /// exactly where the caption starts instead of at a guessed fraction that goes
    /// wrong the moment Dynamic Type or a two-line name changes the block.
    @State private var captionHeight: CGFloat = 0

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

            posterCaption
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    captionHeight = height
                }

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

    private var posterCaption: some View {
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
    }

    /// Where the scrim stops being a gradient and becomes a plinth, as a fraction
    /// of the poster's height. The measured caption block, floored so a caption
    /// that has grown past the photo cannot flood the whole tile, and ceilinged so
    /// there is always a plinth even before the first geometry pass lands.
    private var captionPlinthStart: CGFloat {
        guard posterHeight > 0, captionHeight > 0 else { return 0.66 }
        return min(0.9, max(0.15, 1 - captionHeight / posterHeight))
    }

    /// Text over an arbitrary photo needs its own contrast floor, and a *gradient*
    /// cannot supply one: a photograph's luminance is unknowable, so a partial
    /// scrim is a bet on the pixels underneath. So the scrim ramps to FULL opacity
    /// and finishes ramping where the caption begins — the photo visibly becomes
    /// navy, the caption sits on flat navy, and every contrast ratio in the caption
    /// is computable rather than hoped for.
    ///
    /// The old 0.82 ceiling was the worst of both: enough haze that the "photo"
    /// behind the caption was already a murky navy band, not enough to make the
    /// caption's contrast a known quantity.
    private var legibilityGradient: some View {
        let plinth = captionPlinthStart
        // The ramp never starts above the top of the photo, so a very tall caption
        // shortens the fade instead of clipping it.
        let ramp = min(0.42, plinth)
        let start = plinth - ramp

        return LinearGradient(
            stops: [
                .init(color: PhotoOverlay.scrim.opacity(0), location: start),
                .init(color: PhotoOverlay.scrim.opacity(0.22), location: start + ramp * 0.5),
                .init(color: PhotoOverlay.scrim.opacity(0.68), location: start + ramp * 0.84),
                .init(color: PhotoOverlay.scrim, location: plinth),
                .init(color: PhotoOverlay.scrim, location: 1.0)
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
            compactMeta: false,
            textSpacing: AppSpacing.xs
        )
        .padding(AppSpacing.sm + 2)
        .skylineGlass(.card, in: cardShape, theme: theme)
        .containerShape(cardShape)
    }

    // MARK: - List Row (flat, text-only, for continuous lists)

    private var listRowBody: some View {
        let theme = themeManager.currentTheme

        return rowContent(
            theme: theme,
            // No thumbnail: a scanned row is text. See the note at the top of the file.
            thumbShape: nil,
            compactMeta: true,
            // A visible gap rather than a hairline one, so name and meta read as
            // two ranks of information instead of one wrapped paragraph. This is
            // the space the thumbnail used to buy with a border.
            textSpacing: AppSpacing.sm
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
                    .frame(width: Self.railWidth + Self.rowGutter)
                Rectangle()
                    .fill(theme.colors.border)
                    .frame(height: 0.5)
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Shared Row Content

    /// `thumbShape == nil` drops the photo column entirely — the `.listRow` case.
    private func rowContent(
        theme: AppTheme,
        thumbShape: AnyShape?,
        compactMeta: Bool,
        textSpacing: CGFloat
    ) -> some View {
        // The rail is aligned to the row box so the column of rails stays an
        // unbroken ribbon; only the row's contents hang off the name.
        HStack(spacing: 0) {
            VerdictRail(verdict: verdict, width: Self.railWidth)

            HStack(alignment: thumbShape == nil ? .placeRowName : .center, spacing: Self.rowGutter) {
                if let thumbShape {
                    photoLayer
                        .frame(width: rowThumbSize, height: rowThumbSize)
                        .clipShape(thumbShape)
                        // `surface` sits under two percent off `background` in both
                        // palettes — correct for a recessed well, not enough to
                        // describe an edge — so an empty thumbnail gets a hairline
                        // to hold its shape. A real photograph describes its own
                        // edge and does not get one.
                        .overlay {
                            if image == nil {
                                thumbShape.stroke(theme.colors.border, lineWidth: 1)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: textSpacing) {
                    Text(name)
                        .appFont(.bodyBold, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)
                        // Publishes the name's centre so the pip can find it.
                        .alignmentGuide(.placeRowName) { $0[VerticalAlignment.center] }

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
        // 25 characters — the row this style exists to fit. It truncated while a
        // thumbnail was holding 68pt of the leading edge.
        PlaceCard(name: "Nakameguro Riverside Walk", date: Date(), subtitle: "Meguro, Japan", style: .listRow, showsYear: true, placeholderSystemImage: "map", showsSeparator: false, onTap: {})
    }
    .padding()
    .environmentObject(ThemeManager())
}

#Preview("Glass row") {
    PlaceCard(name: "Kissa Sakaiki", date: Date(), subtitle: "Shibuya", verdict: .worthIt, style: .row, showsYear: true)
        .padding()
        .environmentObject(ThemeManager())
}
