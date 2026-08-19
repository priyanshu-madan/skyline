//
//  PhotoAssetImageLoader.swift
//  SkyLine
//
//  Efficient PHAsset → SwiftUI rendering: one shared PHCachingImageManager,
//  pixel-correct target sizes, prefetching for the swipe deck, and hard
//  cancellation on disappear.
//

import Foundation
import Photos
import SwiftUI
import UIKit

// MARK: - Image Size

/// Two fixed sizes for the whole app.
///
/// PHImageManager caches per (asset, targetSize, contentMode, options) tuple —
/// the header states the options and targetSize must match exactly between the
/// prefetch and the later request or the cache silently misses. Ad-hoc sizes
/// derived from GeometryReader therefore defeat caching completely. Two named
/// sizes keep every prefetch and every request in agreement.
enum PhotoImageSize {
    /// Grid thumbnail inside a place card.
    case thumbnail
    /// Full-bleed hero on a swipe card.
    case card

    /// PhotoKit sizes are in PIXELS — "Note that all sizes are in pixels"
    /// (PHImageManager.h). Passing points yields a soft image on every device.
    /// Scale is clamped at 3 so a 3x screen does not request a needlessly
    /// large render for a thumbnail.
    func pixelSize(screenWidth: CGFloat? = nil) -> CGSize {
        let scale = min(UITraitCollection.current.displayScale, 3.0)
        let screenWidth = screenWidth ?? PhotoImageSize.currentScreenWidth
        switch self {
        case .thumbnail:
            return CGSize(width: 120 * scale, height: 120 * scale)
        case .card:
            return CGSize(width: screenWidth * scale, height: screenWidth * 1.25 * scale)
        }
    }

    /// `UIScreen.main` is deprecated in iOS 26 — resolve the width from the
    /// active window scene instead, falling back to a sane iPhone width when
    /// no scene is attached (unit tests, background refresh).
    private static let currentScreenWidth: CGFloat = {
        // Resolved once at first use. Width is only used to size a cache key,
        // so it does not need to track rotation — and it MUST be stable, since
        // a changing targetSize would invalidate every prefetched image.
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.screen.bounds.width ?? 393
        }
    }()

    var requestOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.version = .current
        switch self {
        case .thumbnail:
            // Opportunistic delivers an instant low-res frame then a sharp one,
            // so a grid never shows a hole.
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            // No iCloud downloads for thumbnails. On an optimized library a
            // 12-cell grid would otherwise kick off 12 downloads at once.
            options.isNetworkAccessAllowed = false
        case .card:
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            // The hero is worth a download — it is the single image the user
            // is looking at while deciding a verdict.
            options.isNetworkAccessAllowed = true
        }
        return options
    }
}

// MARK: - Loader

/// One process-wide `PHCachingImageManager`.
///
/// NOT `PHImageManager.default()`: the default manager does no preheating, so
/// a swipe deck stutters on every card. `PHCachingImageManager` is documented
/// as safe to call from any thread and is marked NS_SWIFT_SENDABLE in the
/// iOS 26 header, so the singleton is shared freely.
final class PhotoAssetImageLoader: @unchecked Sendable {

    // MARK: - Properties

    static let shared = PhotoAssetImageLoader()

    private let manager = PHCachingImageManager()
    private let fetcher = PhotoAssetFetcher()

    private init() {}

    // MARK: - Loading

    /// Loads one image. Returns a request ID the caller MUST cancel on disappear.
    ///
    /// The handler can fire more than once for `.opportunistic` delivery — a
    /// degraded frame first, then the real one. `isDegraded` is surfaced so a
    /// view can keep a shimmer up until the sharp frame lands rather than
    /// flashing blurry-then-sharp.
    @discardableResult
    func requestImage(
        for asset: PHAsset,
        size: PhotoImageSize,
        completion: @escaping @MainActor (UIImage?, Bool) -> Void
    ) -> PHImageRequestID {
        manager.requestImage(
            for: asset,
            targetSize: size.pixelSize(),
            contentMode: .aspectFill,
            options: size.requestOptions
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
            guard !isCancelled else { return }
            // The result handler is called on the main thread for async
            // requests, but can be called synchronously on the calling thread
            // when data is immediately available — so hop explicitly.
            Task { @MainActor in completion(image, isDegraded) }
        }
    }

    func cancel(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(requestID)
    }

    /// Async convenience for one-shot loads (share-sheet rendering, exports).
    func image(for asset: PHAsset, size: PhotoImageSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            _ = requestImage(for: asset, size: size) { image, isDegraded in
                // Only resume on the final, non-degraded delivery.
                guard !isDegraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Prefetching

    /// Warms the cache for the next few cards in the deck.
    /// `size` MUST match the size the view later requests, or this is wasted work.
    func startCaching(assets: [PHAsset], size: PhotoImageSize) {
        guard !assets.isEmpty else { return }
        manager.startCachingImages(
            for: assets,
            targetSize: size.pixelSize(),
            contentMode: .aspectFill,
            options: size.requestOptions
        )
    }

    func stopCaching(assets: [PHAsset], size: PhotoImageSize) {
        guard !assets.isEmpty else { return }
        manager.stopCachingImages(
            for: assets,
            targetSize: size.pixelSize(),
            contentMode: .aspectFill,
            options: size.requestOptions
        )
    }

    /// Call when the deck closes. Leaving a large cache warm costs real memory.
    func stopCachingAll() {
        manager.stopCachingImagesForAllAssets()
        print("💾 PhotoLoader: Stopped caching all assets")
    }

    // MARK: - Deck Window

    /// Keeps a sliding window warm around the current card.
    ///
    /// Sizing rationale: a swipe deck only ever shows one card plus a peek of
    /// the next, so caching ±3 covers a fast flick without holding a whole trip
    /// of full-width images in memory.
    func updateDeckWindow(
        identifiers: [String],
        currentIndex: Int,
        lookahead: Int = 3,
        size: PhotoImageSize = .card
    ) {
        guard !identifiers.isEmpty else { return }
        let lower = max(0, currentIndex - 1)
        let upper = min(identifiers.count - 1, currentIndex + lookahead)
        guard lower <= upper else { return }
        let window = Array(identifiers[lower...upper])
        startCaching(assets: fetcher.assets(for: window), size: size)
    }
}

// MARK: - SwiftUI View

/// Renders a `PHAsset` by local identifier.
///
/// Keyed on the identifier so SwiftUI recycling never leaves a stale image in a
/// reused cell, and cancels its in-flight request in `onDisappear` — without
/// which a fast scroll queues hundreds of decodes that all complete for cells
/// that are long gone.
struct PHAssetImageView: View {
    let localIdentifier: String?
    var size: PhotoImageSize = .card
    var contentMode: ContentMode = .fill

    @EnvironmentObject var themeManager: ThemeManager

    @State private var image: UIImage?
    @State private var isDegraded = true
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .blur(radius: isDegraded ? 8 : 0)
                    .animation(.easeOut(duration: 0.18), value: isDegraded)
            } else {
                Rectangle()
                    .fill(themeManager.currentTheme.colors.surface)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .regular, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    )
            }
        }
        .clipped()
        .task(id: localIdentifier) { await load() }
        .onDisappear {
            PhotoAssetImageLoader.shared.cancel(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    @MainActor
    private func load() async {
        PhotoAssetImageLoader.shared.cancel(requestID)
        image = nil
        isDegraded = true

        guard let localIdentifier else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            // The asset can genuinely be gone — deleted, or dropped from a
            // limited-access selection since detection ran.
            print("⚠️ PHAssetImageView: Asset \(localIdentifier) no longer available")
            return
        }

        requestID = PhotoAssetImageLoader.shared.requestImage(for: asset, size: size) { loaded, degraded in
            guard let loaded else { return }
            self.image = loaded
            self.isDegraded = degraded
        }
    }
}
