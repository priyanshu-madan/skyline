//
//  Theme.swift
//  SkyLine
//
//  Design tokens for the SkyLine place log.
//  iOS 26 / Liquid Glass. Monospaced identity preserved, Dynamic Type aware.
//

import SwiftUI
import Foundation

// MARK: - Color Hex Helper
extension Color {
    /// Builds a Color from a 0xRRGGBB literal. Used only by the palettes below.
    static func appHex(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .dark
    @Published var isAnimating: Bool = false

    private let userDefaults = UserDefaults.standard
    private let themeKey = "app_theme"

    init() {
        loadSavedTheme()
    }

    func toggleTheme() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnimating = true
            currentTheme = currentTheme == .light ? .dark : .light
            saveTheme()
        }

        // Reset animation flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isAnimating = false
        }
    }

    private func loadSavedTheme() {
        let savedTheme = userDefaults.string(forKey: themeKey) ?? "dark"
        currentTheme = AppTheme(rawValue: savedTheme) ?? .dark
        print("🎨 ThemeManager: Loaded theme \(currentTheme.rawValue)")
    }

    private func saveTheme() {
        userDefaults.set(currentTheme.rawValue, forKey: themeKey)
    }
}

// MARK: - Theme Enum
enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colors: ThemeColors {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Colors
struct ThemeColors {
    let background: Color
    let surface: Color
    let text: Color
    let textSecondary: Color
    let border: Color
    let primary: Color
    let secondary: Color
    let accent: Color
    let success: Color
    let warning: Color
    let error: Color
    let info: Color

    // Flight Status Colors
    let statusScheduled: Color
    let statusBoarding: Color
    let statusDeparted: Color
    let statusInAir: Color
    let statusLanded: Color
    let statusDelayed: Color
    let statusCancelled: Color

    // Globe Colors
    let globeBackground: Color
    let globeAtmosphere: Color
    let globeCountries: Color
    let flightPathStart: Color
    let flightPathEnd: Color

    // MARK: Verdict Colors
    // Chosen for colour-vision-deficiency separation, not just hue semantics.
    // Worst-case CIE76 dE between any pair, simulated across normal / deuteranopia /
    // protanopia / tritanopia: 30.0 (light), 28.0 (dark). Anything above ~20 is safely
    // discriminable. Every one clears WCAG AA 4.5:1 against its own theme background.
    // These are the INK colours: icons, strokes, glass tint. Never the only signal —
    // always pair with the verdict's SF Symbol (distinct silhouettes: burst / circle / diamond).
    let verdictWorthIt: Color
    let verdictFine: Color
    let verdictSkip: Color

    // Opaque fills for the Reduce Transparency path, where glass is unavailable.
    let verdictWorthItSurface: Color
    let verdictFineSurface: Color
    let verdictSkipSurface: Color

    /// Ink to place ON a filled `primary` / `success` / `accent` surface.
    ///
    /// This cannot be white. `primary` deliberately flips polarity between the
    /// themes - it is a DARK blue on light and a LIGHT blue on dark - so white
    /// glyphs on a dark-theme fill measure 2.62:1 against #4DA3FF, well under
    /// the 4.5:1 floor. Every filled button in the app was illegible in dark
    /// mode for exactly this reason.
    let onAccent: Color

    // MARK: Glass Support
    /// Darkening veil laid between the globe and any glass chrome, so glass has
    /// something with predictable luminance to sample.
    let scrim: Color
    /// Opaque stand-in for `.glassEffect` when Reduce Transparency is on.
    let glassFallback: Color

    /// Ground for the user's OWN writing.
    ///
    /// Material as taxonomy: a note the user typed is a different class of thing
    /// from generated metadata, and rendering both in the same glass makes the
    /// one authored thing on the screen indistinguishable from four derived ones.
    /// Paired with `accent` as its border.
    let noteSurface: Color

    /// Shadow colour for a raised surface.
    ///
    /// Elevation reads differently per theme and cannot be one constant. On
    /// light, a card lifts by casting a shadow onto the page. On dark it lifts
    /// because `surface` is lighter than `background`; a black shadow on
    /// 0x0A0F1C has almost nowhere to go, so dark carries a deeper, softer one
    /// purely for edge separation rather than for depth.
    let elevation: Color

    static let light = ThemeColors(
        // Every value here is STATIC. `Color(.systemGray6)` and friends are
        // dynamic UIColors: they resolve against the DEVICE appearance, not the
        // theme the user picked in this app. Mixing them with static colours is
        // what produced a white page with dark cards and black-on-black text
        // whenever the app's Light theme ran on a dark-appearance device.
        background: Color.appHex(0xF7F8FC),          // warm paper, not pure white
        surface: Color.appHex(0xFFFFFF),             // cards lift off the page
        text: Color.appHex(0x0E1626),
        textSecondary: Color.appHex(0x5A6480),       // 5.6:1 on background
        border: Color.appHex(0xDCE2EF),
        primary: Color.appHex(0x0B63C5),             // 5.9:1 on background
        secondary: Color.appHex(0x6D4AC7),
        accent: Color.appHex(0xC2701A),
        success: Color.appHex(0x17794A),
        warning: Color.appHex(0x8A6410),
        error: Color.appHex(0xB3323C),
        info: Color.appHex(0x0B63C5),
        statusScheduled: Color.appHex(0x8892A6),
        statusBoarding: Color.appHex(0xC2701A),
        statusDeparted: Color.appHex(0x0B63C5),
        statusInAir: Color.appHex(0x17794A),
        statusLanded: Color.appHex(0x0F7A6B),
        statusDelayed: Color.appHex(0xB3323C),
        statusCancelled: Color.appHex(0xA02A5B),
        globeBackground: Color.appHex(0xEEF2FA),
        globeAtmosphere: Color.appHex(0x8FC5F0).opacity(0.35),
        globeCountries: Color.appHex(0x0E1626),
        flightPathStart: Color.appHex(0x0B63C5),
        flightPathEnd: Color.appHex(0x0B63C5).opacity(0.75),
        verdictWorthIt: Color.appHex(0x00727F),          // deep teal      5.66:1 on white
        verdictFine: Color.appHex(0x9A6400),             // bronze/amber   5.00:1 on white
        verdictSkip: Color.appHex(0x8E1B2E),             // deep crimson   8.95:1 on white
        verdictWorthItSurface: Color.appHex(0xDCF0F2),
        verdictFineSurface: Color.appHex(0xF6E9D2),
        verdictSkipSurface: Color.appHex(0xF7DFE4),
        onAccent: Color.appHex(0xFFFFFF),            // 5.8:1 on primary 0x0B63C5
        scrim: Color.black.opacity(0.18),
        glassFallback: Color.appHex(0xF1F4FA),
        noteSurface: Color.appHex(0xFDF6E8),        // warm cream, 14.9:1 with text
        elevation: Color.black.opacity(0.10)
    )

    static let dark = ThemeColors(
        // Deep navy rather than neutral grey: the globe's own night sky is the
        // app's ground, so the chrome sits in the same world as the artefact.
        // background and surface were previously the SAME value (0.145), which
        // made every card invisible against the page.
        background: Color.appHex(0x0A0F1C),
        surface: Color.appHex(0x151D30),             // now genuinely lifts off
        text: Color.appHex(0xE9EDF7),
        textSecondary: Color.appHex(0x99A3BC),       // 6.4:1 on background
        border: Color.appHex(0x27324B),
        primary: Color.appHex(0x4DA3FF),             // 7.3:1 on background
        secondary: Color.appHex(0xA78BFA),
        accent: Color.appHex(0xFFB454),
        success: Color.appHex(0x3DDC91),
        warning: Color.appHex(0xF2B33D),
        error: Color.appHex(0xFF6B6B),
        info: Color.appHex(0x4DA3FF),
        statusScheduled: Color.appHex(0x8892A6),
        statusBoarding: Color.appHex(0xFFB454),
        statusDeparted: Color.appHex(0x4DA3FF),
        statusInAir: Color.appHex(0x3DDC91),
        statusLanded: Color.appHex(0x5EE0C8),
        statusDelayed: Color.appHex(0xFF6B6B),
        statusCancelled: Color.appHex(0xFF7AAE),
        globeBackground: Color.appHex(0x000011),
        globeAtmosphere: Color.appHex(0x4DA3FF).opacity(0.4),
        globeCountries: Color.appHex(0xFFFFFF),
        flightPathStart: Color.appHex(0x4DA3FF),
        flightPathEnd: Color.appHex(0x4DA3FF).opacity(0.75),
        verdictWorthIt: Color.appHex(0x2FD1C4),          // bright teal    8.06:1 on surface
        verdictFine: Color.appHex(0xF2B33D),             // amber          8.24:1 on surface
        verdictSkip: Color.appHex(0xFF7A6B),             // coral red      6.02:1 on surface
        verdictWorthItSurface: Color.appHex(0x123B3C),
        verdictFineSurface: Color.appHex(0x3D3018),
        verdictSkipSurface: Color.appHex(0x431F1C),
        onAccent: Color.appHex(0x08101F),            // 7.1:1 on primary 0x4DA3FF
        scrim: Color.black.opacity(0.35),
        glassFallback: Color.appHex(0x1B2438),
        noteSurface: Color.appHex(0x241D10),        // warm dark, 11.2:1 with text
        elevation: Color.black.opacity(0.40)
    )
}

// MARK: - Typography
/// Every token keeps its original NAME and near-original optical size, but is now
/// expressed against a `Font.TextStyle` so it scales with Dynamic Type instead of
/// being frozen at a point size.
///
/// Fixed-size monospaced type is what caused "Welcome to SkyLine" to render as
/// "Welcome to SkyLi…" (AuthenticationView.swift:48): monospaced advance width is
/// ~0.6em, so 18 characters at 34pt need ~367pt and a 375pt-wide device cannot fit it.
/// Fonts alone cannot fix that — use the `.appFont(_:)` modifier below, which pairs
/// each token with a line limit, a minimum scale factor and tightening.
///
/// Size mapping (at Dynamic Type "Large", the default):
///   titleLarge   34 -> .largeTitle   34    exact
///   title        28 -> .title        28    exact
///   headline     20 -> .title3       20    exact
///   body         16 -> .callout      16    exact
///   bodyBold     16 -> .callout      16    exact
///   bodySmall    14 -> .subheadline  15    +1
///   caption      12 -> .caption      12    exact
///   captionBold  12 -> .caption      12    exact
///   footnote     10 -> .caption2     11    +1
///   flightNumber 18 -> .headline     17    -1
///   airportCode  16 -> .callout      16    exact
///   flightTime   14 -> .subheadline  15    +1
///   flightStatus 12 -> .caption      12    exact
struct AppTypography {
    // MARK: Core Scale
    static let titleLarge = Font.system(.largeTitle, design: .monospaced, weight: .bold)
    static let title = Font.system(.title, design: .monospaced, weight: .bold)
    static let headline = Font.system(.title3, design: .monospaced, weight: .medium)
    static let body = Font.system(.callout, design: .monospaced, weight: .regular)
    static let bodyBold = Font.system(.callout, design: .monospaced, weight: .medium)
    static let bodySmall = Font.system(.subheadline, design: .monospaced, weight: .regular)
    static let caption = Font.system(.caption, design: .monospaced, weight: .regular)
    static let captionBold = Font.system(.caption, design: .monospaced, weight: .medium)
    static let footnote = Font.system(.caption2, design: .monospaced, weight: .regular)

    // MARK: Flight-specific typography
    static let flightNumber = Font.system(.headline, design: .monospaced, weight: .bold)
    static let airportCode = Font.system(.callout, design: .monospaced, weight: .bold)
    static let flightTime = Font.system(.subheadline, design: .monospaced, weight: .medium)
    static let flightStatus = Font.system(.caption, design: .monospaced, weight: .medium)

    // MARK: Place-log typography
    static let placeName = Font.system(.title3, design: .monospaced, weight: .semibold)
    static let placeMeta = Font.system(.caption, design: .monospaced, weight: .regular)
    /// A whole sentence set at display size. Every other display token caps at
    /// two lines because it carries a NAME; this one carries a claim and must be
    /// allowed to wrap.
    static let claim = Font.system(.title2, design: .monospaced, weight: .semibold)

    static let verdictLabel = Font.system(.caption, design: .monospaced, weight: .semibold)

    /// Escape hatch for one-off sizes. Always relative to a text style so it still scales.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .monospaced, weight: weight)
    }

    // MARK: Nominal point sizes
    /// For `@ScaledMetric` on non-text metrics (icon boxes, thumbnails, row heights)
    /// so glyph frames grow in step with the type they sit beside.
    struct Metrics {
        static let titleLarge: CGFloat = 34
        static let title: CGFloat = 28
        static let headline: CGFloat = 20
        static let body: CGFloat = 16
        static let bodySmall: CGFloat = 14
        static let caption: CGFloat = 12
        static let footnote: CGFloat = 10
    }
}

// MARK: - Text Style
/// A typography token bundled with the layout rules that keep it on one line
/// without truncating. Apply with `.appFont(_:)` rather than `.font(_:)`.
enum AppTextStyle {
    case titleLarge
    case title
    case headline
    case body
    case bodyBold
    case bodySmall
    case caption
    case captionBold
    case footnote
    case flightNumber
    case airportCode
    case flightTime
    case flightStatus
    case placeName
    case placeMeta
    case verdictLabel
    /// One sentence, set large, stating a result rather than a measurement.
    case claim

    var font: Font {
        switch self {
        case .titleLarge: return AppTypography.titleLarge
        case .title: return AppTypography.title
        case .headline: return AppTypography.headline
        case .body: return AppTypography.body
        case .bodyBold: return AppTypography.bodyBold
        case .bodySmall: return AppTypography.bodySmall
        case .caption: return AppTypography.caption
        case .captionBold: return AppTypography.captionBold
        case .footnote: return AppTypography.footnote
        case .flightNumber: return AppTypography.flightNumber
        case .airportCode: return AppTypography.airportCode
        case .flightTime: return AppTypography.flightTime
        case .flightStatus: return AppTypography.flightStatus
        case .placeName: return AppTypography.placeName
        case .placeMeta: return AppTypography.placeMeta
        case .verdictLabel: return AppTypography.verdictLabel
        case .claim: return AppTypography.claim
        }
    }

    /// How far the token may shrink before it truncates. Display sizes get the most
    /// room because they are the ones that overflow on a 375pt screen.
    var minimumScaleFactor: CGFloat {
        switch self {
        case .titleLarge: return 0.55
        case .claim: return 0.7
        case .title, .headline, .placeName: return 0.65
        case .flightNumber, .airportCode: return 0.7
        default: return 0.8
        }
    }

    /// Default line budget. `nil` means "wrap freely" (body copy).
    var defaultLineLimit: Int? {
        switch self {
        case .titleLarge, .title, .headline, .placeName: return 2
        // A sentence, not a name: four lines so a long destination does not
        // truncate the claim into nonsense.
        case .claim: return 4
        case .body, .bodySmall: return nil
        default: return 1
        }
    }

    /// Ceiling on Dynamic Type. Chrome that sits in a fixed-height container
    /// (chips, badges, tab bar) must not grow without bound.
    var maxDynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .verdictLabel, .flightStatus, .footnote, .caption, .captionBold:
            return .accessibility1
        case .titleLarge, .title, .claim:
            return .accessibility3
        default:
            return nil
        }
    }
}

// MARK: - Line Budget
/// How many lines a run of text may occupy. Explicit rather than `Int?` so that
/// "use the token's default" and "wrap freely" are never confused at a call site.
enum LineBudget {
    /// Whatever the text style declares in `defaultLineLimit`.
    case auto
    /// No cap — the text wraps as far as it needs to.
    case unlimited
    case exactly(Int)

    func resolved(for style: AppTextStyle) -> Int? {
        switch self {
        case .auto: return style.defaultLineLimit
        case .unlimited: return nil
        case .exactly(let n): return n
        }
    }
}

extension View {
    /// Applies a typography token together with the truncation defences it needs.
    /// Replaces `.font(AppTypography.x)` at every call site.
    ///
    /// The font alone is not the fix. Monospaced type cannot reflow inside a word,
    /// so a long title on a 375pt device truncates unless it is also allowed to
    /// shrink. This bundles font + line budget + minimum scale factor + tightening
    /// + a Dynamic Type ceiling, which is the whole defence.
    func appFont(_ style: AppTextStyle, lineLimit: LineBudget = .auto) -> some View {
        self
            .font(style.font)
            .lineLimit(lineLimit.resolved(for: style))
            .minimumScaleFactor(style.minimumScaleFactor)
            .allowsTightening(true)
            .dynamicTypeSize(style.maxDynamicTypeSize.map { ...$0 } ?? ...DynamicTypeSize.accessibility5)
    }
}

// MARK: - Spacing
struct AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Inset used by every glass surface, so concentric corners line up.
    static let glassInset: CGFloat = 12
}

// MARK: - Border Radius
struct AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 1000

    /// Cards that host a concentric child. Matches the sheet's 40pt corner family.
    static let card: CGFloat = 22
    /// The presentation corner radius used by the globe sheet in ContentView.
    static let sheet: CGFloat = 40
}

// MARK: - Shadow Styles
/// Elevation presets. The colour always comes from `colors.elevation` so the
/// shadow is theme-aware; only geometry lives here.
///
/// Replaces a previous `AppShadow` whose colours were hardcoded `.black`,
/// which is invisible against the dark palette's 0x0A0F1C ground. It had no
/// callers, so every raised surface in the app was either flat or hand-rolling
/// its own shadow.
enum AppElevation {
    case sm, md, lg

    var radius: CGFloat {
        switch self {
        case .sm: return 2
        case .md: return 6
        case .lg: return 14
        }
    }

    var y: CGFloat {
        switch self {
        case .sm: return 1
        case .md: return 3
        case .lg: return 8
        }
    }
}

extension View {
    /// Raises a surface using the active theme's elevation colour.
    func appElevation(_ level: AppElevation, theme: AppTheme) -> some View {
        shadow(color: theme.colors.elevation, radius: level.radius, x: 0, y: level.y)
    }
}

// MARK: - Environment Key for Theme
struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeManager()
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Extension for Theme
extension View {
    func themedBackground(_ theme: ThemeManager) -> some View {
        self.background(theme.currentTheme.colors.background)
    }

    func themedSurface(_ theme: ThemeManager) -> some View {
        self.background(theme.currentTheme.colors.surface)
    }

    func statusBarStyle(_ style: UIStatusBarStyle) -> some View {
        self.background(StatusBarStyleSetter(style: style))
    }
}

// MARK: - Status Bar Style Controller
struct StatusBarStyleSetter: UIViewControllerRepresentable {
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> StatusBarViewController {
        StatusBarViewController(style: style)
    }

    func updateUIViewController(_ uiViewController: StatusBarViewController, context: Context) {
        uiViewController.statusBarStyle = style
    }
}

class StatusBarViewController: UIViewController {
    var statusBarStyle: UIStatusBarStyle = .default {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    init(style: UIStatusBarStyle) {
        self.statusBarStyle = style
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return statusBarStyle
    }
}
