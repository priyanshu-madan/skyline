//
//  VerdictChip.swift
//  SkyLine
//
//  VerdictBadge  — passive, sits on a PlaceCard or a map callout.
//  VerdictChip   — tappable, the three-up selector the user swipes or taps.
//

import SwiftUI

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

// MARK: - Verdict Chip
/// The interactive form. Selected state is carried by three redundant signals —
/// tint, filled-vs-outline symbol, and weight — so it survives greyscale,
/// colour-vision deficiency, and Differentiate Without Color.
struct VerdictChip: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let verdict: Verdict
    var isSelected: Bool = false
    var showsLabel: Bool = true
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = verdict.color(for: theme)

        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        } label: {
            HStack(spacing: AppSpacing.sm - 2) {
                Image(systemName: isSelected ? verdict.systemImage : verdict.systemImageOutline)
                    .foregroundStyle(ink)
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)

                if showsLabel {
                    Text(verdict.displayName)
                        .foregroundStyle(theme.colors.text)
                }

                if differentiateWithoutColor && isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.colors.text)
                        .imageScale(.small)
                }
            }
            .appFont(.verdictLabel)
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: minHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .skylineGlassCapsule(
            tint: isSelected ? ink.opacity(0.55) : nil,
            interactive: true,
            theme: theme
        )
        .overlay {
            // A ring is the third, colour-independent selection cue.
            if isSelected {
                Capsule().stroke(ink, lineWidth: 1.5)
            }
        }
        .modifier(GlassID(id: verdict.rawValue, namespace: namespace))
        .animation(.easeInOut(duration: 0.22), value: isSelected)
        .accessibilityLabel(Text(verdict.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
struct VerdictPicker: View {
    @EnvironmentObject var themeManager: ThemeManager

    @Binding var selection: Verdict?
    var showsLabels: Bool = true

    @Namespace private var glassNamespace

    var body: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Verdict.allCases) { verdict in
                    VerdictChip(
                        verdict: verdict,
                        isSelected: selection == verdict,
                        showsLabel: showsLabels,
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

// MARK: - Previews
#Preview("Chips") {
    VStack(spacing: AppSpacing.lg) {
        HStack {
            ForEach(Verdict.allCases) { VerdictBadge(verdict: $0) }
        }
        VerdictPickerPreviewHost()
    }
    .padding()
    .environmentObject(ThemeManager())
}

private struct VerdictPickerPreviewHost: View {
    @State private var selection: Verdict? = .worthIt
    var body: some View { VerdictPicker(selection: $selection) }
}
