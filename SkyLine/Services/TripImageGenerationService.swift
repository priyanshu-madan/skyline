//
//  TripImageGenerationService.swift
//  SkyLine
//
//  On-device trip cover image generation with premium minimal design
//

import Foundation
import UIKit

// MARK: - Image Generation Service

class TripImageGenerationService {
    static let shared = TripImageGenerationService()

    private init() {}

    // MARK: - Generate Images

    /// Generates both dark and light mode cover images for a trip
    func generateTripCoverImages(destination: String) async throws -> (darkImage: UIImage, lightImage: UIImage) {
        print("🎨 Generating cover images for: \(destination)")

        // Generate premium minimal images on-device (instant and reliable)
        let darkImage = createCoverImage(destination: destination, theme: .dark)
        let lightImage = createCoverImage(destination: destination, theme: .light)

        print("✅ Generated both theme variants")
        return (darkImage, lightImage)
    }

    // MARK: - Image Creation

    /// Creates a premium minimal cover image with gradient and typography
    private func createCoverImage(destination: String, theme: ImageTheme) -> UIImage {
        let size = CGSize(width: 1792, height: 1024) // 16:9 aspect ratio

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext

            // Set up gradient colors based on theme
            let gradientColors: [UIColor]
            let accentColor: UIColor
            let textColor: UIColor

            if theme == .dark {
                gradientColors = [
                    UIColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1.0), // #0A0E1A
                    UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0),
                    UIColor(red: 0.11, green: 0.11, blue: 0.15, alpha: 1.0)
                ]
                accentColor = UIColor(red: 0.00, green: 0.83, blue: 1.00, alpha: 1.0) // #00D4FF
                textColor = UIColor(red: 0.70, green: 0.73, blue: 0.78, alpha: 1.0)
            } else {
                gradientColors = [
                    UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0),
                    UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0), // #F7F9FC
                    UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
                ]
                accentColor = UIColor(red: 0.15, green: 0.38, blue: 0.92, alpha: 1.0) // #2563EB
                textColor = UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
            }

            // Draw gradient background
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = gradientColors.map { $0.cgColor } as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!

            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )

            // Draw decorative minimal dots pattern
            ctx.setFillColor(accentColor.withAlphaComponent(0.08).cgColor)
            let dotSize: CGFloat = 8
            let dotSpacing: CGFloat = 40

            for row in 0..<Int(size.height / dotSpacing) {
                for col in 0..<Int(size.width / dotSpacing) {
                    let x = CGFloat(col) * dotSpacing + dotSpacing / 2
                    let y = CGFloat(row) * dotSpacing + dotSpacing / 2

                    // Only draw dots in lower half for subtle pattern
                    if y > size.height * 0.5 {
                        let dotRect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                        ctx.fillEllipse(in: dotRect)
                    }
                }
            }

            // Extract city name (take first part before comma)
            let cityName = destination.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? destination

            // Add destination text with better styling
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let mainAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80, weight: .ultraLight),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                .kern: 4.0 // Letter spacing
            ]

            let text = cityName.uppercased() as NSString

            // Center text in lower half
            let textSize = text.size(withAttributes: mainAttributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: size.height * 0.55,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: mainAttributes)

            // Add subtle accent line above text
            let lineWidth: CGFloat = 120
            let lineHeight: CGFloat = 3
            let lineRect = CGRect(
                x: (size.width - lineWidth) / 2,
                y: textRect.minY - 30,
                width: lineWidth,
                height: lineHeight
            )

            ctx.setFillColor(accentColor.withAlphaComponent(0.4).cgColor)
            let linePath = UIBezierPath(roundedRect: lineRect, cornerRadius: lineHeight / 2)
            ctx.addPath(linePath.cgPath)
            ctx.fillPath()

            // Add small "travel destination" subtitle
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .light),
                .foregroundColor: textColor.withAlphaComponent(0.5),
                .paragraphStyle: paragraphStyle,
                .kern: 2.0
            ]

            let subtitle = "TRAVEL DESTINATION" as NSString
            let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
            let subtitleRect = CGRect(
                x: (size.width - subtitleSize.width) / 2,
                y: textRect.maxY + 20,
                width: subtitleSize.width,
                height: subtitleSize.height
            )

            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)
        }

        return image
    }
}

// MARK: - Supporting Types

enum ImageTheme: String {
    case dark
    case light
}
