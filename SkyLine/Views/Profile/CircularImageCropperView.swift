//
//  CircularImageCropperView.swift
//  SkyLine
//
//  Circular image cropper for profile pictures
//

import SwiftUI

struct CircularImageCropperView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var screenSize: CGSize = .zero

    private let cropSize: CGFloat = 340

    var body: some View {
        ZStack {
            themeManager.currentTheme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }

                    Spacer()

                    Text("Crop Photo")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)

                    Spacer()

                    Button {
                        cropImage()
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(themeManager.currentTheme.colors.background)
                .zIndex(10)

                // Crop Area - Full screen with overlay
                GeometryReader { geometry in
                    ZStack {
                        // Full image that can be panned and zoomed
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 0.5), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0

                                        // Constrain offset after zoom to keep image within bounds
                                        let constrained = constrainOffset(
                                            offset: offset,
                                            scale: scale,
                                            imageSize: image.size,
                                            screenSize: geometry.size
                                        )

                                        if constrained != offset {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                offset = constrained
                                                lastOffset = constrained
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        // Constrain offset to keep image within crop bounds
                                        let constrained = constrainOffset(
                                            offset: offset,
                                            scale: scale,
                                            imageSize: image.size,
                                            screenSize: geometry.size
                                        )

                                        if constrained != offset {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                offset = constrained
                                                lastOffset = constrained
                                            }
                                        } else {
                                            lastOffset = offset
                                        }
                                    }
                            )

                        // Dark overlay with circular cutout
                        OverlayWithCircularCutout(
                            circleSize: cropSize,
                            overlayColor: Color.black.opacity(0.6)
                        )
                        .allowsHitTesting(false)

                        // Circular border
                        Circle()
                            .strokeBorder(themeManager.currentTheme.colors.primary, lineWidth: 3)
                            .frame(width: cropSize, height: cropSize)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        screenSize = geometry.size
                    }
                }
                .clipped()

                // Instructions
                VStack(spacing: 12) {
                    Text("Pinch to zoom, drag to reposition")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                    // Reset button
                    Button {
                        withAnimation(.spring()) {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Text("Reset")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.bottom, 40)
                .background(themeManager.currentTheme.colors.background)
                .zIndex(10)
            }
        }
    }

    private func constrainOffset(offset: CGSize, scale: CGFloat, imageSize: CGSize, screenSize: CGSize) -> CGSize {
        // Calculate how the image is displayed on screen
        let imageAspect = imageSize.width / imageSize.height
        let screenAspect = screenSize.width / screenSize.height

        // Calculate the displayed image size (scaledToFill behavior)
        var displayedImageSize: CGSize
        if imageAspect > screenAspect {
            // Image is wider - fill height
            displayedImageSize = CGSize(
                width: screenSize.height * imageAspect,
                height: screenSize.height
            )
        } else {
            // Image is taller - fill width
            displayedImageSize = CGSize(
                width: screenSize.width,
                height: screenSize.width / imageAspect
            )
        }

        // Apply scale
        displayedImageSize = CGSize(
            width: displayedImageSize.width * scale,
            height: displayedImageSize.height * scale
        )

        // Calculate initial centered position
        let centeredOrigin = CGPoint(
            x: (screenSize.width - displayedImageSize.width) / 2,
            y: (screenSize.height - displayedImageSize.height) / 2
        )

        // Calculate crop circle bounds
        let cropCenterX = screenSize.width / 2
        let cropCenterY = screenSize.height / 2
        let cropRadius = cropSize / 2

        // The image position after offset
        let imageX = centeredOrigin.x + offset.width
        let imageY = centeredOrigin.y + offset.height

        // Calculate the bounds - image must fully cover the crop circle
        // For a circle, we need to ensure all points on the circle are covered
        // The circle extends from (cropCenterX ± cropRadius, cropCenterY ± cropRadius)

        // Maximum offset that keeps the crop circle covered
        let maxOffsetX = centeredOrigin.x + (displayedImageSize.width / 2) - cropRadius
        let minOffsetX = centeredOrigin.x - (displayedImageSize.width / 2) + cropRadius

        let maxOffsetY = centeredOrigin.y + (displayedImageSize.height / 2) - cropRadius
        let minOffsetY = centeredOrigin.y - (displayedImageSize.height / 2) + cropRadius

        // Constrain the offset
        var constrainedOffset = offset

        // Check right edge
        if imageX + displayedImageSize.width < cropCenterX + cropRadius {
            constrainedOffset.width = cropCenterX + cropRadius - centeredOrigin.x - displayedImageSize.width
        }

        // Check left edge
        if imageX > cropCenterX - cropRadius {
            constrainedOffset.width = cropCenterX - cropRadius - centeredOrigin.x
        }

        // Check bottom edge
        if imageY + displayedImageSize.height < cropCenterY + cropRadius {
            constrainedOffset.height = cropCenterY + cropRadius - centeredOrigin.y - displayedImageSize.height
        }

        // Check top edge
        if imageY > cropCenterY - cropRadius {
            constrainedOffset.height = cropCenterY - cropRadius - centeredOrigin.y
        }

        return constrainedOffset
    }

    private func cropImage() {
        // Create a renderer for the cropped image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropSize, height: cropSize))

        let croppedImage = renderer.image { context in
            // Create circular clipping path
            let circlePath = UIBezierPath(
                ovalIn: CGRect(x: 0, y: 0, width: cropSize, height: cropSize)
            )
            circlePath.addClip()

            // Calculate how the image is displayed on screen
            let imageSize = image.size
            let imageAspect = imageSize.width / imageSize.height
            let screenAspect = screenSize.width / screenSize.height

            // Calculate the displayed image size (scaledToFill behavior)
            var displayedImageSize: CGSize
            if imageAspect > screenAspect {
                // Image is wider - fill height
                displayedImageSize = CGSize(
                    width: screenSize.height * imageAspect,
                    height: screenSize.height
                )
            } else {
                // Image is taller - fill width
                displayedImageSize = CGSize(
                    width: screenSize.width,
                    height: screenSize.width / imageAspect
                )
            }

            // Apply scale
            displayedImageSize = CGSize(
                width: displayedImageSize.width * scale,
                height: displayedImageSize.height * scale
            )

            // Calculate initial position (centered on screen)
            var imageOriginOnScreen = CGPoint(
                x: (screenSize.width - displayedImageSize.width) / 2,
                y: (screenSize.height - displayedImageSize.height) / 2
            )

            // Apply offset
            imageOriginOnScreen.x += offset.width
            imageOriginOnScreen.y += offset.height

            // Calculate crop area center on screen
            let cropCenterOnScreen = CGPoint(
                x: screenSize.width / 2,
                y: screenSize.height / 2
            )

            // Calculate crop area top-left on screen
            let cropOriginOnScreen = CGPoint(
                x: cropCenterOnScreen.x - cropSize / 2,
                y: cropCenterOnScreen.y - cropSize / 2
            )

            // Calculate where to draw the image in the crop canvas
            // The image needs to be positioned relative to the crop area
            let drawOrigin = CGPoint(
                x: imageOriginOnScreen.x - cropOriginOnScreen.x,
                y: imageOriginOnScreen.y - cropOriginOnScreen.y
            )

            let drawRect = CGRect(origin: drawOrigin, size: displayedImageSize)

            // Draw the image
            image.draw(in: drawRect)
        }

        onCrop(croppedImage)
        dismiss()
    }
}

// MARK: - Overlay with Circular Cutout

struct OverlayWithCircularCutout: View {
    let circleSize: CGFloat
    let overlayColor: Color

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Fill the entire canvas with the overlay color
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(overlayColor)
                )

                // Cut out a circle in the center
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let circlePath = Path(ellipseIn: CGRect(
                    x: center.x - circleSize / 2,
                    y: center.y - circleSize / 2,
                    width: circleSize,
                    height: circleSize
                ))

                context.blendMode = .destinationOut
                context.fill(circlePath, with: .color(.white))
            }
        }
    }
}

#Preview {
    CircularImageCropperView(
        image: UIImage(systemName: "person.circle")!,
        onCrop: { _ in }
    )
    .environmentObject(ThemeManager())
}
