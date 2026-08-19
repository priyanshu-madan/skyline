//
//  PlaceCard.swift
//  SkyLine
//
//  A place the user actually spent time in: photo, name, verdict, date.
//  Takes primitives rather than a model type so it does not block on the
//  clustered-place model landing.
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
}

// MARK: - Place Card Style
enum PlaceCardStyle {
    /// Photo-forward tile for the swipe deck and the trip grid.
    case poster
    /// Dense row for lists and the shareable guide.
    case row
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
    var onTap: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var posterHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var rowThumbSize: CGFloat = 64

    private var dateText: String {
        let formatter = showsYear ? DateFormatter.placeCardDateWithYear : DateFormatter.placeCardDate
        return formatter.string(from: date)
    }

    var body: some View {
        Group {
            switch style {
            case .poster: posterBody
            case .row: rowBody
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .onTapGesture {
            guard let onTap else { return }
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var accessibilitySummary: String {
        var parts: [String] = [name, dateText]
        if let subtitle { parts.append(subtitle) }
        if photoCount > 0 { parts.append("\(photoCount) photos") }
        if let verdict { parts.append(verdict.accessibilityLabel) }
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
                    .foregroundStyle(.white)

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
                .foregroundStyle(.white.opacity(0.85))
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
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.28), location: 0.62),
                .init(color: .black.opacity(0.68), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: - Row

    private var rowBody: some View {
        let theme = themeManager.currentTheme
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

        return HStack(spacing: AppSpacing.md - 4) {
            photoLayer
                .frame(width: rowThumbSize, height: rowThumbSize)
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                HStack(spacing: AppSpacing.xs + 1) {
                    Text(dateText)
                    if let subtitle {
                        Text("·")
                        Text(subtitle)
                            .lineLimit(1)
                    }
                }
                .appFont(.placeMeta)
                .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let verdict {
                VerdictBadge(verdict: verdict, showsLabel: false, size: .compact)
            }
        }
        .padding(AppSpacing.sm + 2)
        .skylineGlass(.card, in: cardShape, theme: theme)
        .containerShape(cardShape)
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoLayer: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                themeManager.currentTheme.colors.surface
                Image(systemName: "photo")
                    .font(AppTypography.mono(.title3))
                    .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
            }
        }
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

#Preview("Row") {
    VStack(spacing: AppSpacing.sm) {
        PlaceCard(name: "Kissa Sakaiki", date: Date(), subtitle: "Shibuya", verdict: .worthIt, style: .row)
        PlaceCard(name: "Shibuya Sky", date: Date(), subtitle: "Observation deck", verdict: .fine, style: .row)
        PlaceCard(name: "Takeshita Street", date: Date(), subtitle: "Harajuku", verdict: .skip, style: .row)
    }
    .padding()
    .environmentObject(ThemeManager())
}
