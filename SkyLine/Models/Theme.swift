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

    // MARK: Glass Support
    /// Darkening veil laid between the globe and any glass chrome, so glass has
    /// something with predictable luminance to sample.
    let scrim: Color
    /// Opaque stand-in for `.glassEffect` when Reduce Transparency is on.
    let glassFallback: Color

    static let light = ThemeColors(
        background: Color.white,
        surface: Color(.systemGray6),
        text: Color.black,
        textSecondary: Color(.systemGray),
        border: Color(.systemGray4),
        primary: Color.blue,
        secondary: Color.purple,
        accent: Color.orange,
        success: Color.green,
        warning: Color.orange,
        error: Color.red,
        info: Color.blue,
        statusScheduled: Color(.systemGray2),
        statusBoarding: Color.orange,
        statusDeparted: Color.blue,
        statusInAir: Color.green,
        statusLanded: Color.mint,
        statusDelayed: Color.red,
        statusCancelled: Color.pink,
        globeBackground: Color(.systemGray6),
        globeAtmosphere: Color.cyan.opacity(0.3),
        globeCountries: Color.black,
        flightPathStart: Color.blue,
        flightPathEnd: Color.blue.opacity(0.8),
        verdictWorthIt: Color.appHex(0x00727F),          // deep teal      5.66:1 on white
        verdictFine: Color.appHex(0x9A6400),             // bronze/amber   5.00:1 on white
        verdictSkip: Color.appHex(0x8E1B2E),             // deep crimson   8.95:1 on white
        verdictWorthItSurface: Color.appHex(0xDCF0F2),
        verdictFineSurface: Color.appHex(0xF6E9D2),
        verdictSkipSurface: Color.appHex(0xF7DFE4),
        scrim: Color.black.opacity(0.18),
        glassFallback: Color(.systemGray6)
    )

    static let dark = ThemeColors(
        background: Color(red: 0.145, green: 0.145, blue: 0.145),  // oklch(0.145 0 0)
        surface: Color(red: 0.145, green: 0.145, blue: 0.145),     // oklch(0.145 0 0) - card background
        text: Color(red: 0.985, green: 0.985, blue: 0.985),        // oklch(0.985 0 0)
        textSecondary: Color(red: 0.708, green: 0.708, blue: 0.708), // oklch(0.708 0 0)
        border: Color(red: 0.269, green: 0.269, blue: 0.269),      // oklch(0.269 0 0)
        primary: Color.blue,
        secondary: Color.purple,
        accent: Color.orange,
        success: Color.green,
        warning: Color.orange,
        error: Color.red,
        info: Color.blue,
        statusScheduled: Color(.systemGray2),
        statusBoarding: Color.orange,
        statusDeparted: Color.blue,
        statusInAir: Color.green,
        statusLanded: Color.mint,
        statusDelayed: Color.red,
        statusCancelled: Color.pink,
        globeBackground: Color(.init(red: 0.0, green: 0.0, blue: 0.067, alpha: 1.0)),
        globeAtmosphere: Color.blue.opacity(0.4),
        globeCountries: Color.white,
        flightPathStart: Color.blue,
        flightPathEnd: Color.blue.opacity(0.8),
        verdictWorthIt: Color.appHex(0x2FD1C4),          // bright teal    8.06:1 on #252525
        verdictFine: Color.appHex(0xF2B33D),             // amber          8.24:1 on #252525
        verdictSkip: Color.appHex(0xFF7A6B),             // coral red      6.02:1 on #252525
        verdictWorthItSurface: Color.appHex(0x123B3C),
        verdictFineSurface: Color.appHex(0x3D3018),
        verdictSkipSurface: Color.appHex(0x431F1C),
        scrim: Color.black.opacity(0.35),
        glassFallback: Color(red: 0.20, green: 0.20, blue: 0.20)
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
        }
    }

    /// How far the token may shrink before it truncates. Display sizes get the most
    /// room because they are the ones that overflow on a 375pt screen.
    var minimumScaleFactor: CGFloat {
        switch self {
        case .titleLarge: return 0.55
        case .title, .headline, .placeName: return 0.65
        case .flightNumber, .airportCode: return 0.7
        default: return 0.8
        }
    }

    /// Default line budget. `nil` means "wrap freely" (body copy).
    var defaultLineLimit: Int? {
        switch self {
        case .titleLarge, .title, .headline, .placeName: return 2
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
        case .titleLarge, .title:
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
struct AppShadow {
    static let sm: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.1), 2, 0, 1)
    static let md: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.1), 4, 0, 2)
    static let lg: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.15), 8, 0, 4)
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
