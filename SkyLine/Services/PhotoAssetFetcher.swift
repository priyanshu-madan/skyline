//
//  PhotoAssetFetcher.swift
//  SkyLine
//
//  Turns a date range into [PhotoPoint]. All PhotoKit knowledge lives here.
//

import Foundation
import Photos
import CoreLocation
import ImageIO

// MARK: - Fetch Result

struct PhotoFetchOutcome: Sendable {
    let points: [PhotoPoint]
    let totalInRange: Int
    let screenshotsExcluded: Int
    let recoveredFromEXIF: Int

    var located: [PhotoPoint] { points.filter(\.hasLocation) }
}

// MARK: - Fetcher

/// Not an ObservableObject — it holds no UI state. `PhotoPlaceDetectionService`
/// owns the @Published surface.
struct PhotoAssetFetcher: Sendable {

    // MARK: Configuration

    struct Configuration: Sendable {
        /// Padding either side of the trip window. Trips are stored with
        /// midnight-ish bounds, and the photos you take on the flight home
        /// after "endDate" are still part of the trip.
        var paddingBefore: TimeInterval = 12 * 3600
        var paddingAfter: TimeInterval = 12 * 3600

        /// Hard ceiling. A three-week trip on a burst-happy phone can exceed
        /// 10,000 assets; clustering is O(n·k) and we do not need every frame
        /// of a burst to find where someone stood.
        var fetchLimit: Int = 6000

        /// Screenshots are never photos of places — boarding passes, maps,
        /// bookings. Excluded from clustering entirely.
        var excludeScreenshots: Bool = true

        /// Attempt EXIF recovery when PHAsset.location is nil. Bounded, see
        /// `recoverLocationsFromEXIF`.
        var enableEXIFRecovery: Bool = true
        var exifRecoveryLimit: Int = 300

        static let `default` = Configuration()
    }

    let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Fetch

    /// Fetches image assets created inside `[start, end]` (padded) and reduces
    /// them to `PhotoPoint`s.
    ///
    /// ⚠️ CRITICAL PHOTOKIT CONSTRAINT — the predicate cannot filter on location.
    /// `PHFetchOptions.predicate` only accepts a documented subset of keys
    /// (creationDate, modificationDate, mediaType, mediaSubtypes, duration,
    /// pixelWidth, pixelHeight, isFavorite, isHidden, burstIdentifier,
    /// localIdentifier, sourceType). `location` is NOT among them and putting
    /// it in an NSPredicate raises an unsupported-predicate exception at fetch
    /// time, not a compile error. So we filter by DATE in the predicate and by
    /// LOCATION in memory. That is also why `totalInRange` and
    /// `points.filter(\.hasLocation).count` are both reported — the gap between
    /// them is exactly the signal that drives the no-GPS fallback.
    func fetchPoints(start: Date, end: Date) async -> PhotoFetchOutcome {
        let windowStart = start.addingTimeInterval(-configuration.paddingBefore)
        let windowEnd = end.addingTimeInterval(configuration.paddingAfter)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue,
            windowStart as NSDate,
            windowEnd as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false   // one representative frame per burst
        options.fetchLimit = configuration.fetchLimit
        // Only the user's own library. Shared-album assets are excluded on
        // purpose: they are other people's photos and can be from other cities,
        // which would invent places the user never went.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        // We do not observe this fetch for incremental changes; opting out
        // avoids Photos building and retaining change-tracking state for a
        // multi-thousand-asset result.
        options.wantsIncrementalChangeDetails = false

        let result = PHAsset.fetchAssets(with: options)
        print("🔄 PhotoFetcher: \(result.count) image assets between \(windowStart) and \(windowEnd)")

        var points: [PhotoPoint] = []
        var screenshots = 0
        var assetsMissingLocation: [PHAsset] = []
        points.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            if isScreenshot {
                screenshots += 1
                if configuration.excludeScreenshots { return }
            }
            // creationDate is optional on PHAsset. Without it the asset cannot
            // be placed on the timeline at all, so it is dropped rather than
            // guessed at from modificationDate (which reflects edits).
            guard let created = asset.creationDate else { return }

            if asset.location == nil {
                assetsMissingLocation.append(asset)
            }

            points.append(
                PhotoPoint(
                    id: asset.localIdentifier,
                    timestamp: created,
                    latitude: asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude,
                    horizontalAccuracy: asset.location?.horizontalAccuracy,
                    isScreenshot: isScreenshot,
                    isFavorite: asset.isFavorite,
                    isPanorama: asset.mediaSubtypes.contains(.photoPanorama),
                    isDepthEffect: asset.mediaSubtypes.contains(.photoDepthEffect),
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            )
        }

        let locatedCount = points.filter(\.hasLocation).count
        print("🔄 PhotoFetcher: \(locatedCount)/\(points.count) have a PHAsset location")

        // EXIF rescue only when the GPS yield is poor enough to matter.
        var recovered = 0
        if configuration.enableEXIFRecovery,
           locatedCount < 3 || Double(locatedCount) / Double(max(points.count, 1)) < 0.15 {
            let rescued = await recoverLocationsFromEXIF(
                assets: Array(assetsMissingLocation.prefix(configuration.exifRecoveryLimit))
            )
            if !rescued.isEmpty {
                recovered = rescued.count
                points = points.map { point in
                    guard !point.hasLocation, let fix = rescued[point.id] else { return point }
                    return PhotoPoint(
                        id: point.id,
                        timestamp: point.timestamp,
                        latitude: fix.latitude,
                        longitude: fix.longitude,
                        horizontalAccuracy: nil,
                        isScreenshot: point.isScreenshot,
                        isFavorite: point.isFavorite,
                        isPanorama: point.isPanorama,
                        isDepthEffect: point.isDepthEffect,
                        pixelWidth: point.pixelWidth,
                        pixelHeight: point.pixelHeight
                    )
                }
                print("✅ PhotoFetcher: Recovered \(recovered) locations from EXIF")
            }
        }

        return PhotoFetchOutcome(
            points: points,
            totalInRange: points.count,
            screenshotsExcluded: screenshots,
            recoveredFromEXIF: recovered
        )
    }

    /// Fetches the `PHAsset`s behind a set of local identifiers, in the order given.
    /// `fetchAssets(withLocalIdentifiers:options:)` does NOT preserve the order
    /// of the identifiers array, so we re-index.
    func assets(for identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return identifiers.compactMap { byID[$0] }
    }

    // MARK: - EXIF Recovery

    /// Last-ditch GPS recovery for assets whose `PHAsset.location` is nil.
    ///
    /// HONEST EXPECTATION: for photos taken by the device's own camera, Photos
    /// already indexes EXIF GPS into `PHAsset.location`, so if that is nil the
    /// EXIF is almost certainly empty too and this yields nothing. The real
    /// hit rate is on imported assets — AirDropped photos, DSLR/drone imports,
    /// WhatsApp-saved images — where the library index can be missing or stale
    /// while the file header still carries GPSInfo. That is a minority of a
    /// typical trip but it is not zero, and it costs nothing when it fails.
    ///
    /// Bounded three ways: only runs when the GPS yield is already poor, capped
    /// at `exifRecoveryLimit` assets, and reads only the first 256 KB of each
    /// file (EXIF lives in the JPEG/HEIC header) via incremental CGImageSource
    /// rather than decoding the image.
    private func recoverLocationsFromEXIF(assets: [PHAsset]) async -> [String: CLLocationCoordinate2D] {
        guard !assets.isEmpty else { return [:] }
        print("🔄 PhotoFetcher: Attempting EXIF recovery on \(assets.count) assets")

        var recovered: [String: CLLocationCoordinate2D] = [:]
        for asset in assets {
            if Task.isCancelled { break }
            if let coordinate = await exifCoordinate(for: asset) {
                recovered[asset.localIdentifier] = coordinate
            }
        }
        return recovered
    }

    private func exifCoordinate(for asset: PHAsset) async -> CLLocationCoordinate2D? {
        guard let resource = PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) else { return nil }

        let headerBytes = 256 * 1024

        let data: Data? = await withCheckedContinuation { continuation in
            var buffer = Data()
            var finished = false
            let options = PHAssetResourceRequestOptions()
            // Never pull from iCloud for a long shot — that would turn a free
            // fallback into a multi-megabyte download per photo.
            options.isNetworkAccessAllowed = false

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    guard !finished else { return }
                    buffer.append(chunk)
                    if buffer.count >= headerBytes {
                        finished = true
                        continuation.resume(returning: buffer)
                    }
                },
                completionHandler: { _ in
                    guard !finished else { return }
                    finished = true
                    continuation.resume(returning: buffer.isEmpty ? nil : buffer)
                }
            )
        }

        guard let data else { return nil }

        // Incremental source so a truncated header still parses its metadata.
        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, data as CFData, false)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }

        // EXIF stores magnitude plus a hemisphere reference character.
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lngRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        let signedLat = latRef.uppercased() == "S" ? -latitude : latitude
        let signedLng = lngRef.uppercased() == "W" ? -longitude : longitude

        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: signedLat, longitude: signedLng)),
              !(signedLat == 0 && signedLng == 0) else { return nil }

        return CLLocationCoordinate2D(latitude: signedLat, longitude: signedLng)
    }
}
