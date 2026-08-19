//
//  SkyLineGlass.swift
//  SkyLine
//
//  Liquid Glass surfaces for the place log, on top of the WebKit globe.
//
//  Verified against iOS 26.0 SDK (Xcode 26.0.1):
//    View.glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())
//    Glass.regular / .clear / .identity / .tint(Color?) / .interactive(Bool = true)
//    GlassEffectContainer(spacing: CGFloat? = nil, content: () -> Content)
//    View.glassEffectID(_:in:) / .glassEffectUnion(id:namespace:) / .glassEffectTransition(_:)
//    View.scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set)
//    ConcentricRectangle(corners:isUniform:) + View.containerShape(_ some RoundedRectangularShape)
//  NOTE: `glassBackgroundEffect` does NOT exist on iOS — it is visionOS only. Do not reach for it.
//

import SwiftUI

// MARK: - Glass Style
/// The three roles glass plays in this app. Anything else should be a plain surface.
enum SkyLineGlassRole {
    /// Floating chrome over the globe: tab bar, toolbars, the sheet grabber row.
    case chrome
    /// A content card that must stay readable over an arbitrary photo or the globe.
    case card
    /// A tappable pill: verdict chips, filter segments, circular icon buttons.
    case control
}

// MARK: - Glass Surface Modifier
private struct SkyLineGlassSurface<S: Shape>: ViewModifier {
    let role: SkyLineGlassRole
    let shape: S
    let tint: Color?
    let isInteractive: Bool
    let theme: AppTheme

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Reduce Transparency turns glass off system-wide. Fall back to an opaque
            // surface so contrast never depends on what is behind the view.
            content
                .background(
                    shape.fill(tint.map { $0.opacity(theme == .light ? 0.16 : 0.24) } ?? Color.clear)
                )
                .background(shape.fill(theme.colors.glassFallback))
                .overlay(shape.stroke(theme.colors.border, lineWidth: 0.5))
        } else {
            content
                .glassEffect(
                    Glass.regular
                        .tint(tint)
                        .interactive(isInteractive),
                    in: shape
                )
        }
    }
}

extension View {
    /// Applies the app's glass treatment. Prefer this over calling `.glassEffect`
    /// directly so the Reduce Transparency fallback stays in one place.
    func skylineGlass<S: Shape>(
        _ role: SkyLineGlassRole = .card,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        theme: AppTheme
    ) -> some View {
        modifier(
            SkyLineGlassSurface(
                role: role,
                shape: shape,
                tint: tint,
                isInteractive: interactive,
                theme: theme
            )
        )
    }

    /// Capsule glass, the default for controls.
    func skylineGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = false,
        theme: AppTheme
    ) -> some View {
        skylineGlass(.control, in: Capsule(), tint: tint, interactive: interactive, theme: theme)
    }

    /// Rounded-rect glass, the default for cards. Also installs the container shape
    /// so any `ConcentricRectangle` child nests its corners correctly.
    func skylineGlassCard(
        cornerRadius: CGFloat = AppRadius.card,
        tint: Color? = nil,
        theme: AppTheme
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return skylineGlass(.card, in: shape, tint: tint, theme: theme)
            .containerShape(shape)
    }
}

// MARK: - Glass Panel
/// Wraps a run of glass elements in a single `GlassEffectContainer` so adjacent
/// pieces sample one shared backdrop and merge instead of stacking blurs.
/// Use this around any row of two or more glass views — a chip row, a toolbar.
struct SkyLineGlassPanel<Content: View>: View {
    var spacing: CGFloat = AppSpacing.sm
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

// MARK: - Glass Bar
/// The floating bar treatment: a capsule of glass that hovers clear of the safe
/// area rather than sitting flush against it. This is what replaces the hand-rolled
/// `CustomTabBar` background (`RoundedRectangle` + `.shadow`) in SkyLineBottomBarView.
struct SkyLineGlassBar<Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager

    var cornerRadius: CGFloat = 28
    var horizontalPadding: CGFloat = AppSpacing.md
    var verticalPadding: CGFloat = AppSpacing.sm + 2
    @ViewBuilder var content: () -> Content

    var body: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .skylineGlass(
                    .chrome,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                    theme: themeManager.currentTheme
                )
        }
    }
}

// MARK: - Circular Glass Icon Button
/// The 44x44 control used by the globe overlay and the section headers.
/// Replaces the `.buttonStyle(.glass) + .buttonBorderShape(.circle)` pairs so the
/// hit target and symbol size are consistent everywhere.
struct SkyLineGlassIconButton: View {
    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    var accessibilityLabel: String
    var tint: Color? = nil
    var isProminent: Bool = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44

    var body: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(AppTypography.mono(.body, weight: .semibold))
                .foregroundStyle(tint ?? themeManager.currentTheme.colors.text)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .skylineGlass(
            .control,
            in: Circle(),
            tint: isProminent ? tint : nil,
            interactive: true,
            theme: themeManager.currentTheme
        )
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Globe Scrim
/// A vertical veil laid between the globe WebView and the sheet. Glass needs
/// something with predictable luminance underneath it; a live 3D globe on a black
/// field does not provide that, and unscrimmed glass over it reads as muddy grey.
/// Put this in the ZStack directly above `WebViewGlobeView` and below the sheet.
struct SkyLineGlobeScrim: View {
    @EnvironmentObject var themeManager: ThemeManager

    /// Fraction of the screen height the sheet currently occupies, so the scrim
    /// can deepen as the sheet grows. Drive it from `selectedDetent`.
    var sheetFraction: CGFloat = 0.2

    var body: some View {
        let colors = themeManager.currentTheme.colors
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: max(0.0, 1.0 - sheetFraction - 0.22)),
                .init(color: colors.scrim, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Sheet Chrome
extension View {
    /// The presentation configuration for the globe sheet, kept in one place.
    /// Detent values are unchanged from ContentView so existing equality checks
    /// (`selectedDetent == .fraction(0.3)`) keep working.
    func skylineGlobeSheetChrome(selectedDetent: Binding<PresentationDetent>) -> some View {
        self
            .presentationDetents(
                [.height(80), .fraction(0.2), .fraction(0.3), .fraction(0.6), .large],
                selection: selectedDetent
            )
            .presentationBackgroundInteraction(.enabled)
            .presentationBackground(.clear)
            .presentationCornerRadius(AppRadius.sheet)
    }

    /// Softens the fade where scrolling content passes under glass chrome.
    /// `.soft` is the right choice over a live globe: `.hard` draws a visible
    /// hairline that reads as a seam.
    func skylineScrollEdges() -> some View {
        self.scrollEdgeEffectStyle(.soft, for: .all)
    }
}
