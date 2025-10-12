//
//  Theme.swift
//  SkyLine
//
//  Theme system matching React Native implementation
//

import SwiftUI
import Foundation

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
        flightPathEnd: Color.blue.opacity(0.8)
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
        flightPathEnd: Color.blue.opacity(0.8)
    )
}

// MARK: - Typography
struct AppTypography {
    // Using system monospace font for reliable cross-device compatibility
    static let titleLarge = Font.system(size: 34, weight: .bold, design: .monospaced)
    static let title = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let headline = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let body = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let bodyBold = Font.system(size: 16, weight: .medium, design: .monospaced)
    static let bodySmall = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let captionBold = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let footnote = Font.system(size: 10, weight: .regular, design: .monospaced)
    
    // Flight-specific typography
    static let flightNumber = Font.system(size: 18, weight: .bold, design: .monospaced)
    static let airportCode = Font.system(size: 16, weight: .bold, design: .monospaced)
    static let flightTime = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let flightStatus = Font.system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: - Spacing
struct AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Border Radius
struct AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 1000
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