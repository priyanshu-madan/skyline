//
//  Font+GeistMono.swift
//  SkyLine
//
//  Geist Mono font extensions for consistent typography
//

import SwiftUI

extension Font {
    // MARK: - Geist Mono Font Family - Direct .custom() usage recommended
    
    // MARK: - Semantic Font Sizes
    
    /// App-specific font styles using Geist Mono
    
    // Headers
    static var appTitle: Font { .custom("GeistMono-Bold", size: 28) }
    static var screenTitle: Font { .custom("GeistMono-Bold", size: 24) }
    static var sectionHeader: Font { .custom("GeistMono-Medium", size: 18) }
    static var cardTitle: Font { .custom("GeistMono-Medium", size: 16) }
    
    // Body Text
    static var body: Font { .custom("GeistMono-Regular", size: 16) }
    static var bodyMedium: Font { .custom("GeistMono-Medium", size: 16) }
    static var bodySmall: Font { .custom("GeistMono-Regular", size: 14) }
    static var caption: Font { .custom("GeistMono-Regular", size: 12) }
    static var captionMedium: Font { .custom("GeistMono-Medium", size: 12) }
    
    // Flight Specific
    static var flightNumber: Font { .custom("GeistMono-Bold", size: 18) }
    static var airportCode: Font { .custom("GeistMono-Bold", size: 16) }
    static var flightTime: Font { .custom("GeistMono-Medium", size: 14) }
    static var flightStatus: Font { .custom("GeistMono-Medium", size: 12) }
    
    // Interface Elements
    static var button: Font { .custom("GeistMono-Medium", size: 16) }
    static var buttonSmall: Font { .custom("GeistMono-Medium", size: 14) }
    static var tabBar: Font { .custom("GeistMono-Medium", size: 10) }
    static var navigationTitle: Font { .custom("GeistMono-Bold", size: 20) }
}

// MARK: - Font Registration Check
extension Font {
    /// Debug function to check if Geist Mono fonts are properly loaded
    static func checkGeistMonoAvailability() {
        let fontNames = [
            "GeistMono-Regular",
            "GeistMono-Medium", 
            "GeistMono-Bold"
        ]
        
        print("🔤 Checking Geist Mono font availability:")
        for fontName in fontNames {
            let font = UIFont(name: fontName, size: 16)
            if font != nil {
                print("✅ \(fontName) loaded successfully")
            } else {
                print("❌ \(fontName) failed to load")
            }
        }
        
        print("📝 All available fonts:")
        UIFont.familyNames.sorted().forEach { family in
            print("  Family: \(family)")
            UIFont.fontNames(forFamilyName: family).forEach { font in
                if font.contains("Geist") {
                    print("    ✅ \(font)")
                }
            }
        }
    }
}