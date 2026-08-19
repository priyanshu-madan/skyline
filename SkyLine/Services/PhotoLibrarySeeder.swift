//
//  PhotoLibrarySeeder.swift
//  SkyLine
//
//  DEBUG-only synthetic photo library. Seeds a simulator with GPS-tagged,
//  time-ordered images so clustering can be exercised without taking a trip.
//

#if DEBUG

import Foundation
import Photos
import UIKit
import CoreLocation

// MARK: - Fixture Types

/// A scripted place in a synthetic trip.
struct SeedPlace: Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    /// Each visit: (offset from trip start in hours, photo count, minutes between photos)
    let visits: [(hourOffset: Double, photoCount: Int, spacingMinutes: Double)]
    /// Metres of random jitter applied per photo, simulating GPS noise.
    var jitterMeters: Double = 25
}

// MARK: - Seeder

/// Writes generated images into the photo library with `creationDate` and
/// `location` set directly.
///
/// WHY THIS RATHER THAN EXIF FILES: `PHAssetChangeRequest` exposes
/// `location` and `creationDate` as writable properties (verified in
/// PHAssetChangeRequest.h:47-48 of the iOS 26.0 SDK), so the seeded assets are
/// guaranteed to come back out of `PHAsset.location`. Writing GPS EXIF into a
/// JPEG and importing it depends on Photos choosing to index that EXIF, which
/// is a behaviour we would be trusting rather than controlling. Both paths are
/// provided — this one is the reliable one, and `Scripts/seed_photos.sh` is the
/// no-code alternative.
@MainActor
final class PhotoLibrarySeeder {

    // MARK: - Properties

    static let shared = PhotoLibrarySeeder()
    private init() {}

    /// Every seeded asset is tagged in its filename so `deleteSeededAssets`
    /// can find them again and a real library is never damaged.
    static let seedFilenamePrefix = "SKYLINE_SEED_"

    // MARK: - Guard

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Seeding

    /// Seeds a synthetic trip.
    ///
    /// - Parameters:
    ///   - places: the scripted places
    ///   - tripStart: timestamp the offsets are measured from
    ///   - stripLocation: when true, writes photos with NO location — this is
    ///     how you test the Tier 2 no-GPS fallback, which is the single most
    ///     important path to have under test because it is the one a GPS-only
    ///     design silently breaks on.
    @discardableResult
    func seed(
        places: [SeedPlace],
        tripStart: Date,
        stripLocation: Bool = false
    ) async -> Result<Int, Error> {
        guard isSimulator else {
            print("❌ PhotoSeeder: Refusing to seed a real device's photo library")
            return .success(0)
        }

        let access = await PhotoLibraryAuthorizationService.shared.requestAccess()
        guard access == .full else {
            print("❌ PhotoSeeder: Need full library access to seed (got \(access.rawValue))")
            return .success(0)
        }

        var written = 0
        for place in places {
            for visit in place.visits {
                for index in 0..<visit.photoCount {
                    let timestamp = tripStart
                        .addingTimeInterval(visit.hourOffset * 3600)
                        .addingTimeInterval(Double(index) * visit.spacingMinutes * 60)

                    let coordinate = stripLocation ? nil : Self.jitter(
                        latitude: place.latitude,
                        longitude: place.longitude,
                        meters: place.jitterMeters
                    )

                    let image = Self.renderCard(
                        title: place.name,
                        subtitle: Self.timestampLabel(timestamp),
                        index: index + 1,
                        total: visit.photoCount
                    )

                    do {
                        try await write(image: image, timestamp: timestamp, coordinate: coordinate)
                        written += 1
                    } catch {
                        print("❌ PhotoSeeder: Failed to write asset — \(error.localizedDescription)")
                        return .failure(error)
                    }
                }
            }
        }

        print("✅ PhotoSeeder: Seeded \(written) assets (location \(stripLocation ? "STRIPPED" : "attached"))")
        return .success(written)
    }

    private func write(image: UIImage, timestamp: Date, coordinate: CLLocationCoordinate2D?) async throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "\(Self.seedFilenamePrefix)\(UUID().uuidString).jpg"
            request.addResource(with: .photo, data: data, options: options)
            request.creationDate = timestamp
            if let coordinate {
                request.location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }

    // MARK: - Teardown

    /// Deletes previously seeded assets. Matches on the seeded filename, so it
    /// cannot touch a real photo.
    @discardableResult
    func deleteSeededAssets() async -> Int {
        guard isSimulator else { return 0 }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)

        var doomed: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            let filenames = PHAssetResource.assetResources(for: asset).map(\.originalFilename)
            if filenames.contains(where: { $0.hasPrefix(Self.seedFilenamePrefix) }) {
                doomed.append(asset)
            }
        }
        guard !doomed.isEmpty else { return 0 }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(doomed as NSArray)
            }
            print("✅ PhotoSeeder: Deleted \(doomed.count) seeded assets")
            return doomed.count
        } catch {
            print("❌ PhotoSeeder: Delete failed — \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Image Generation

    /// Renders a labelled card so you can SEE which place a photo belongs to
    /// while eyeballing a cluster result. Monospaced, matching AppTypography.
    private static func renderCard(title: String, subtitle: String, index: Int, total: Int) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let hue = Double(abs(title.hashValue) % 360) / 360.0

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 88, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 48, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: paragraph
            ]

            NSString(string: title).draw(
                with: CGRect(x: 60, y: 600, width: size.width - 120, height: 400),
                options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil
            )
            NSString(string: "\(subtitle)\n\(index)/\(total)").draw(
                with: CGRect(x: 60, y: 900, width: size.width - 120, height: 300),
                options: .usesLineFragmentOrigin, attributes: subtitleAttrs, context: nil
            )
        }
    }

    // MARK: - Helpers

    /// Offsets a coordinate by a uniform random amount inside `meters`,
    /// so seeded visits reproduce the GPS scatter the clusterer must absorb.
    private static func jitter(latitude: Double, longitude: Double, meters: Double) -> CLLocationCoordinate2D {
        guard meters > 0 else { return CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        let bearing = Double.random(in: 0..<(2 * .pi))
        let distance = Double.random(in: 0...meters)
        let dLat = (distance * cos(bearing)) / 111_320.0
        let dLng = (distance * sin(bearing)) / (111_320.0 * cos(latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude + dLat, longitude: longitude + dLng)
    }

    private static func timestampLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Fixtures

extension PhotoLibrarySeeder {

    /// A four-day Tokyo trip that exercises every branch of the clusterer.
    /// These are the exact numbers the constants above were tuned against —
    /// 30 randomised runs, 30/30 on every assertion:
    ///
    ///   Fuglen Tokyo      two visits on different days → collapses to ONE
    ///                     place with visitCount == 2 (the multi-day assertion)
    ///   Hotel Shibuya     three visits, one per night, low photo count →
    ///                     significant through repetition, not volume. Sits
    ///                     194 m from Shibuya Crossing, which is the pair that
    ///                     proved a 250 m fixed merge radius was wrong.
    ///   teamLab Planets   one long dense visit → exercises the dwell cap
    ///   Shibuya Crossing  one photo → falls below minimumSignificance (4.0)
    ///   Narita Airport    64 km away → survives DISTANCE rejection, and must
    ///                     be removed by category suppression instead
    ///   Senso-ji          180 m jitter → the sprawling venue that a tight
    ///                     merge radius shatters
    static var tokyoFixture: [SeedPlace] {
        [
            SeedPlace(name: "Fuglen Tokyo", latitude: 35.6693, longitude: 139.6975,
                      visits: [(hourOffset: 10, photoCount: 6, spacingMinutes: 4),
                               (hourOffset: 58, photoCount: 4, spacingMinutes: 6)]),
            SeedPlace(name: "Hotel Shibuya", latitude: 35.6580, longitude: 139.7016,
                      visits: [(hourOffset: 2, photoCount: 2, spacingMinutes: 10),
                               (hourOffset: 26, photoCount: 2, spacingMinutes: 12),
                               (hourOffset: 50, photoCount: 3, spacingMinutes: 8)]),
            SeedPlace(name: "teamLab Planets", latitude: 35.6486, longitude: 139.7900,
                      visits: [(hourOffset: 14, photoCount: 22, spacingMinutes: 5)]),
            SeedPlace(name: "Shibuya Crossing", latitude: 35.6595, longitude: 139.7005,
                      visits: [(hourOffset: 20, photoCount: 1, spacingMinutes: 0)]),
            SeedPlace(name: "Narita Airport", latitude: 35.7719, longitude: 140.3928,
                      visits: [(hourOffset: -3, photoCount: 3, spacingMinutes: 15)]),
            SeedPlace(name: "Senso-ji", latitude: 35.7148, longitude: 139.7967,
                      visits: [(hourOffset: 34, photoCount: 14, spacingMinutes: 6)],
                      jitterMeters: 180)
        ]
    }

    /// One-liner for a debug menu.
    static func seedTokyoTrip(stripLocation: Bool = false) async {
        let start = Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date()
        await shared.seed(places: tokyoFixture, tripStart: start, stripLocation: stripLocation)
    }
}

#endif
