//
//  LibraryPlaceDetectionService.swift
//  SkyLine
//
//  Retroactive place detection across the WHOLE photo library.
//
//  WHY THIS EXISTS — the cold start.
//  `PhotoPlaceDetectionService.detectPlaces(for:)` only ever looks inside one
//  trip's date window. That is correct once a trip exists, and useless on day
//  one: a new user has no trips, so the globe is empty and stays empty until
//  they next travel — even though their camera roll already holds years of it.
//  This service reads the library end to end, works out which runs of days were
//  spent away from home, and hands each of those episodes to the SAME clusterer
//  the trip path uses.
//
//  THE FOUR JOBS, and how each is done:
//
//   1. READ THE WHOLE LIBRARY WITHOUT SILENTLY TRUNCATING IT.
//      `PhotoAssetFetcher` fetches with an ASCENDING sort and a fetch limit,
//      which over a whole library would keep only the OLDEST n photos and drop
//      every recent trip without saying so. Nothing here inherits that: the
//      fetch carries no `fetchLimit`, assets are enumerated in index batches so
//      the work is interruptible, and if a library really is enormous the
//      retained set is THINNED EVENLY across the whole timeline (see
//      `maxLocatedPoints`) and the thinning is reported in
//      `diagnostics.samplingStride`. A sample is never presented as a full read.
//
//   2. FIND THE TRIPS. Home is where you are on the most DAYS, not where you
//      have the most photos — one heavily photographed weekend abroad can
//      outshoot a month of ordinary life, but it cannot outlast it. A trip is
//      then a run of days whose photos sit far from home. See `findHome` and
//      `segmentEpisodes` for the thresholds and the reasoning behind each.
//
//   3. REUSE `PlaceClusterer`. It is a pure function over `[PhotoPoint]`, and
//      an episode is exactly the same shape of input a trip window produces.
//      There is no second clustering algorithm in this file.
//
//   4. BE INTERRUPTIBLE AND IDEMPOTENT. Scanning tens of thousands of assets
//      and reverse-geocoding a hundred clusters takes minutes, so every stage
//      checks `Task.isCancelled`, `places` is published as it grows, and
//      cancelling returns everything found so far rather than throwing it away.
//      Re-running produces the same `DetectedPlace.id` values because
//      `PlaceClusterer.stableClusterID` derives identity from asset identifiers
//      rather than `UUID()` — so a second run UPDATES rather than duplicates,
//      and `existingPlaces:` carries the user's verdicts and edits forward.
//
//  HANDOFF: each `LibraryEpisode` converts to a `Trip` via `asTrip()`, so the
//  existing `PlaceReviewView(trip:detectedPlaces:)` deck works unchanged:
//      PlaceReviewView(trip: episode.asTrip(),
//                      detectedPlaces: result.places(in: episode))
//

import Foundation
import Photos
import CoreLocation
import MapKit
import Combine

// MARK: - Phase

/// The stages worth narrating on a scan that can run for minutes.
enum LibraryDetectionPhase: String, Sendable {
    case idle
    case requestingAccess
    case scanningLibrary
    case findingTrips
    case groupingPlaces
    case namingPlaces
    case finished
}

// MARK: - Outcome

/// How the scan ended. NONE of these is an error.
///
/// An empty library and a library with location services switched off are
/// ordinary, common states — a user whose camera never wrote GPS has done
/// nothing wrong and must still be offered a way forward. Modelling them as
/// failures would put an error screen in front of the most fragile moment the
/// product has.
enum LibraryDetectionOutcome: String, Codable, Sendable {
    /// Places were found. The normal path.
    case places
    /// The library is empty, or nothing in it is visible to SkyLine.
    case noPhotos
    /// Photos exist, but not one of them carries a usable coordinate.
    case noLocations
    /// Located photos exist, but they all sit around one place: home.
    case noTripsFound
    /// Trips were found, but no run of photos inside them was substantial
    /// enough to call a place.
    case noPlacesInTrips
    /// The user declined photo access.
    case accessDenied
}

// MARK: - Episode

/// A trip-shaped run of days spent away from home.
///
/// `id` is derived from the episode's own dates and rough position rather than
/// `UUID()`, so a second scan of the same library labels the same trip the same
/// way. Note that place identity does NOT depend on this: a `DetectedPlace`'s id
/// comes from its photos, so a verdict survives even if an episode's boundaries
/// shift by a day when new photos are added.
struct LibraryEpisode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    /// Best-effort label — the locality MapKit returned for the episode's
    /// strongest place. Falls back to the date range, never to a guess.
    let title: String
    let startDate: Date
    let endDate: Date
    let latitude: Double
    let longitude: Double
    /// Distinct calendar days with photos inside this episode.
    let dayCount: Int
    /// Located photos that fed the clusterer.
    let photoCount: Int
    /// Places detected inside this episode, after suppression and capping.
    let placeCount: Int

    var dateRangeText: String {
        Self.dateRangeText(start: startDate, end: endDate)
    }

    static func dateRangeText(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        let first = formatter.string(from: start)
        let last = formatter.string(from: end)
        return first == last ? first : "\(first) – \(last)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Adapts an episode to the existing trip-shaped surfaces — the verdict deck
    /// takes a `Trip`, and an episode is a trip SkyLine worked out rather than
    /// one the user typed. `createdAt`/`updatedAt` are pinned to the episode's
    /// own dates so the value is stable across calls and safe to hash into a
    /// navigation destination.
    func asTrip() -> Trip {
        Trip(
            id: id,
            title: title,
            destination: title,
            startDate: startDate,
            endDate: endDate,
            latitude: latitude,
            longitude: longitude,
            createdAt: startDate,
            updatedAt: endDate
        )
    }
}

// MARK: - Diagnostics

/// Everything needed to write an honest screen, and everything a bug report
/// would ask for.
struct LibraryDetectionDiagnostics: Codable, Sendable {
    var assetsInLibrary: Int = 0
    var assetsScanned: Int = 0
    var screenshotsExcluded: Int = 0
    var assetsWithLocation: Int = 0
    var assetsWithoutLocation: Int = 0
    /// 1 means every located photo was kept. Anything higher means the retained
    /// set is an even sample of the library, not all of it.
    var samplingStride: Int = 1
    var locatedPhotosThinned: Int = 0
    var daysWithPhotos: Int = 0
    var awayDays: Int = 0
    var episodesFound: Int = 0
    var episodesProcessed: Int = 0
    var clustersSuppressed: Int = 0
    var geocodeFailures: Int = 0
    var placesCarriedOver: Int = 0
    var isLimitedLibraryAccess: Bool = false
    var wasCancelled: Bool = false
    var homeLatitude: Double?
    var homeLongitude: Double?

    var wasSampled: Bool { samplingStride > 1 }

    var locationCoverage: Double {
        let total = assetsWithLocation + assetsWithoutLocation
        guard total > 0 else { return 0 }
        return Double(assetsWithLocation) / Double(total)
    }

    /// One line the user can read and check against their own library.
    var userFacingExplanation: String? {
        if isLimitedLibraryAccess {
            return "SkyLine can only see the photos you picked, so this is not your whole history. Choose more to find more trips."
        }
        if wasCancelled {
            return "Stopped early — these are the trips SkyLine got to."
        }
        if wasSampled {
            return "Your library is large, so SkyLine read an even sample across all of it rather than every single photo."
        }
        let total = assetsWithLocation + assetsWithoutLocation
        if total > 0 && locationCoverage < 0.25 {
            return "Only \(assetsWithLocation) of \(total) photos have a location saved, so some trips may be missing."
        }
        return nil
    }
}

// MARK: - Result

struct LibraryDetectionResult: Codable, Sendable {
    let outcome: LibraryDetectionOutcome
    let episodes: [LibraryEpisode]
    /// Every detected place across every episode. `tripId` is the episode id.
    let places: [DetectedPlace]
    let diagnostics: LibraryDetectionDiagnostics

    func places(in episode: LibraryEpisode) -> [DetectedPlace] {
        places.filter { $0.tripId == episode.id }
    }

    var placeCount: Int { places.count }
    var episodeCount: Int { episodes.count }
    var isEmpty: Bool { places.isEmpty }
}

// MARK: - Service

@MainActor
final class LibraryPlaceDetectionService: ObservableObject {

    // MARK: - Configuration

    struct Configuration: Sendable {

        /// Assets read per enumeration batch. Between batches the scan checks
        /// for cancellation and publishes progress, so this is the granularity
        /// at which a long scan can be stopped and narrated.
        var batchSize: Int = 1500

        /// Ceiling on RETAINED located photos.
        ///
        /// Not a fetch limit — the fetch has none. When the retained set reaches
        /// this size it is halved in place and the keep-every-nth stride
        /// doubles, which yields an even sample across the ENTIRE library
        /// instead of a prefix of it. 60,000 geotagged photos is far beyond a
        /// typical library and keeps peak memory in the low tens of megabytes.
        var maxLocatedPoints: Int = 60_000

        /// Screenshots are never photos of a place.
        var excludeScreenshots: Bool = true

        /// Side of the grid cell used to find home, in degrees.
        ///
        /// 0.25° is ~28 km north-south, ~19 km east-west at 45° latitude — the
        /// scale of a metro area. Smaller cells split a city across several
        /// cells and let a suburb win; larger ones start swallowing weekend
        /// destinations into "home".
        var homeCellDegrees: Double = 0.25

        /// Distinct days needed in the winning cell before we believe in a home
        /// at all. Below this the library is too thin (or too nomadic) to have
        /// a centre of gravity, and every day is treated as away.
        var minimumHomeDays: Int = 5

        /// How far ahead of its nearest FAR rival the winning cell must be
        /// before it is called home.
        ///
        /// Without this, a library that is mostly travel crowns its longest
        /// trip as "home" and then measures every other trip against it — a
        /// library of a six-day Lisbon trip and a six-day Tokyo trip finds
        /// "home: Lisbon" and reports one trip. Requiring a clear winner means
        /// a library with no real centre of gravity gets no home at all, and
        /// every run of days in it counts as travel, which is the truth.
        ///
        /// The rival is measured only among cells more than `homeRadiusMeters`
        /// away, because the two halves of one city are not rivals — a metro
        /// straddling four grid cells must not disqualify itself.
        var homeDominanceRatio: Double = 1.25

        /// How far from home a day has to sit to count as travel.
        ///
        /// 100 km clears a large metro area plus its exurbs and any ordinary
        /// commute, so normal life never registers as a trip; it is short
        /// enough that a genuine weekend away in the next region still does.
        var homeRadiusMeters: Double = 100_000

        /// Days without away-photos that a trip may contain without splitting.
        /// You do not photograph every day of a holiday, and two silent days in
        /// the middle of a fortnight are not two trips.
        var bridgeDays: Int = 2

        /// Maximum distance between ANY two days inside one episode.
        ///
        /// Tied directly to `PlaceClusterer.Configuration.outlierRadiusMeters`,
        /// which is 300 km measured from the episode's own median: an episode
        /// whose day-to-day diameter is capped at 250 km cannot contain a place
        /// that the clusterer will then reject as an outlier. Without this, a
        /// Tokyo-and-Osaka fortnight would arrive as one episode and quietly
        /// lose one of the two cities. Splitting it into two episodes loses
        /// nothing — they are two runs of days in two places, which is what
        /// they were.
        var maxEpisodeDiameterMeters: Double = 250_000

        /// Located photos an episode needs before it is worth clustering. Below
        /// this there is not enough evidence to place anything.
        var minimumEpisodePhotos: Int = 6

        /// Safety valve on a very well-travelled library. Applied by recency,
        /// and reported as `episodesFound` vs `episodesProcessed`.
        var maxEpisodes: Int = 40

        /// Places per episode. Lower than the clusterer's own 14 because this
        /// deck spans a user's whole history rather than one trip, and a
        /// first-run deck of four hundred cards is not a deck.
        var maxPlacesPerEpisode: Int = 10

        /// Hard ceiling on places NAMED in one run. Naming is one throttled
        /// MapKit round trip per cluster (~0.6 s floor), so this is also the
        /// wall-clock budget: 120 places is roughly 90 seconds of geocoding.
        var maxPlacesTotal: Int = 120

        static let `default` = Configuration()
    }

    // MARK: - Published State

    static let shared = LibraryPlaceDetectionService()

    @Published private(set) var phase: LibraryDetectionPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRunning = false

    /// Total image assets the scan will walk. 0 until the fetch resolves.
    @Published private(set) var photosTotal: Int = 0
    @Published private(set) var photosScanned: Int = 0
    /// Photos carrying a usable coordinate, counted as the scan runs.
    @Published private(set) var photosLocated: Int = 0

    /// Runs of days away from home, published as soon as segmentation finishes.
    /// Monotone during a run — it is the count on screen, and a live number that
    /// goes backwards reads as a bug.
    @Published private(set) var tripsDetected: Int = 0
    /// Episodes that produced at least one place, filled in as naming completes.
    @Published private(set) var episodes: [LibraryEpisode] = []
    /// Grows as places are named. This is what makes "stop and keep what you
    /// found" real rather than a polite word for "discard".
    @Published private(set) var places: [DetectedPlace] = []

    @Published private(set) var lastResult: LibraryDetectionResult?

    // MARK: - Dependencies

    let configuration: Configuration
    private let namingService: PlaceNamingService
    private let authorization = PhotoLibraryAuthorizationService.shared
    private var task: Task<Void, Never>?

    /// Categories that are never "a place I went" even when the clustering is
    /// perfect. Airports cluster beautifully — you are there for hours and you
    /// photograph things — and no distance threshold can catch them, because
    /// they sit a legitimate day-trip away from the city they serve. Same
    /// reasoning, and the same single entry, as
    /// `PhotoPlaceDetectionService.suppressedCategories`; that one is private,
    /// so it cannot be shared without widening its surface.
    private static let suppressedCategories: Set<String> = [
        MKPointOfInterestCategory.airport.rawValue
    ]

    init(
        configuration: Configuration = .default,
        namingService: PlaceNamingService = PlaceNamingService.shared
    ) {
        self.configuration = configuration
        self.namingService = namingService
    }

    // MARK: - Control

    /// Starts a full-library scan. Safe to call twice — the second call is a
    /// no-op while the first is still running.
    ///
    /// - Parameter existingPlaces: places from a previous run. Any place whose
    ///   id matches keeps its verdict, note, user-edited name and original
    ///   creation date, which is what makes re-running an UPDATE.
    func start(existingPlaces: [DetectedPlace] = []) {
        guard !isRunning else {
            print("⚠️ LibraryDetection: Already running — ignoring start()")
            return
        }
        // Set synchronously, not inside the task. `run` only reaches its own
        // assignment after the first suspension, so two taps in the same
        // runloop turn would both pass the guard and start two library passes.
        isRunning = true
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(existingPlaces: existingPlaces)
        }
    }

    /// Requests cancellation. Whatever has already been found stays in `places`
    /// and arrives in `lastResult` with `diagnostics.wasCancelled` set.
    func cancel() {
        guard isRunning else { return }
        print("🛑 LibraryDetection: Cancellation requested")
        task?.cancel()
    }

    /// Clears the previous run so the screen can offer a fresh scan.
    func reset() {
        guard !isRunning else { return }
        phase = .idle
        progress = 0
        photosTotal = 0
        photosScanned = 0
        photosLocated = 0
        tripsDetected = 0
        episodes = []
        places = []
        lastResult = nil
    }

    // MARK: - Pipeline

    private func run(existingPlaces: [DetectedPlace]) async {
        isRunning = true
        phase = .requestingAccess
        progress = 0
        photosTotal = 0
        photosScanned = 0
        photosLocated = 0
        tripsDetected = 0
        episodes = []
        places = []
        lastResult = nil

        var diagnostics = LibraryDetectionDiagnostics()

        defer {
            isRunning = false
            phase = .finished
            progress = 1
        }

        // MARK: Access
        let access = await authorization.requestAccess()
        guard access == .full || access == .limited else {
            print("❌ LibraryDetection: Photo access \(access.rawValue)")
            finish(outcome: .accessDenied, diagnostics: diagnostics)
            return
        }
        diagnostics.isLimitedLibraryAccess = (access == .limited)

        // MARK: Scan
        phase = .scanningLibrary
        let cfg = configuration
        let report: @Sendable (Int, Int, Int) async -> Void = { [weak self] scanned, total, located in
            guard let self else { return }
            await self.reportScan(scanned: scanned, total: total, located: located)
        }
        let scan = await Task.detached(priority: .userInitiated) {
            await Self.scanLibrary(configuration: cfg, onProgress: report)
        }.value

        diagnostics.assetsInLibrary = scan.assetsInLibrary
        diagnostics.assetsScanned = scan.assetsScanned
        diagnostics.screenshotsExcluded = scan.screenshotsExcluded
        diagnostics.assetsWithLocation = scan.assetsWithLocation
        diagnostics.assetsWithoutLocation = scan.assetsWithoutLocation
        diagnostics.samplingStride = scan.samplingStride
        diagnostics.locatedPhotosThinned = scan.locatedPhotosThinned
        diagnostics.wasCancelled = scan.wasCancelled || Task.isCancelled

        photosTotal = scan.assetsInLibrary
        photosScanned = scan.assetsScanned
        photosLocated = scan.points.count
        progress = 0.35

        // Two ordinary, non-error outcomes.
        if scan.assetsInLibrary == 0 {
            print("📭 LibraryDetection: Library is empty")
            finish(outcome: .noPhotos, diagnostics: diagnostics)
            return
        }
        if scan.points.isEmpty {
            print("📭 LibraryDetection: \(scan.assetsScanned) photos, none with a usable location")
            finish(outcome: .noLocations, diagnostics: diagnostics)
            return
        }

        // MARK: Episodes
        phase = .findingTrips
        let points = scan.points
        let segmentation = await Task.detached(priority: .userInitiated) {
            Self.segmentation(points: points, configuration: cfg)
        }.value

        diagnostics.daysWithPhotos = segmentation.daysWithPhotos
        diagnostics.awayDays = segmentation.awayDays
        diagnostics.homeLatitude = segmentation.home?.latitude
        diagnostics.homeLongitude = segmentation.home?.longitude
        diagnostics.episodesFound = segmentation.episodes.count
        progress = 0.42

        guard !segmentation.episodes.isEmpty else {
            print("🏠 LibraryDetection: No run of days away from home")
            finish(outcome: .noTripsFound, diagnostics: diagnostics)
            return
        }

        // Newest first. If the scan is stopped halfway, the trips kept are the
        // ones the user can still remember — which is also the order in which
        // the deck is most worth swiping.
        let ordered = Array(
            segmentation.episodes
                .sorted { $0.startDate > $1.startDate }
                .prefix(cfg.maxEpisodes)
        )
        diagnostics.episodesProcessed = ordered.count
        tripsDetected = ordered.count

        if Task.isCancelled { diagnostics.wasCancelled = true }

        // MARK: Cluster
        phase = .groupingPlaces
        let clusterConfiguration = Self.clusterConfiguration(from: cfg)
        var clustered: [(segment: EpisodeSegment, clusters: [PlaceCluster])] = []

        for (index, segment) in ordered.enumerated() {
            if Task.isCancelled { diagnostics.wasCancelled = true; break }
            let episodePoints = segment.points
            let clusters = await Task.detached(priority: .userInitiated) {
                PlaceClusterer(configuration: clusterConfiguration).cluster(points: episodePoints)
            }.value
            if !clusters.isEmpty {
                clustered.append((segment, clusters))
            }
            progress = 0.42 + 0.13 * (Double(index + 1) / Double(ordered.count))
        }

        guard !clustered.isEmpty else {
            print("🔍 LibraryDetection: \(ordered.count) episodes, no clusters survived ranking")
            finish(outcome: .noPlacesInTrips, diagnostics: diagnostics)
            return
        }

        // MARK: Name
        phase = .namingPlaces
        let priorByID = Dictionary(existingPlaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let totalToName = min(clustered.reduce(0) { $0 + $1.clusters.count }, cfg.maxPlacesTotal)

        var namedCount = 0
        var seenIDs = Set<String>()
        var producedEpisodes: [LibraryEpisode] = []
        var producedPlaces: [DetectedPlace] = []

        naming: for entry in clustered {
            if Task.isCancelled { diagnostics.wasCancelled = true; break }

            var episodePlaces: [DetectedPlace] = []
            var locality: String?

            for cluster in entry.clusters {
                if Task.isCancelled { diagnostics.wasCancelled = true; break naming }
                if namedCount >= cfg.maxPlacesTotal {
                    print("⚠️ LibraryDetection: Hit the \(cfg.maxPlacesTotal)-place naming cap")
                    break naming
                }
                guard !seenIDs.contains(cluster.id) else { continue }

                let resolved = await namingService.resolveName(
                    latitude: cluster.latitude,
                    longitude: cluster.longitude,
                    spreadMeters: cluster.spreadMeters
                )
                namedCount += 1
                if resolved.isFallbackCoordinate { diagnostics.geocodeFailures += 1 }
                if locality == nil { locality = resolved.locality }
                progress = 0.55 + 0.45 * (Double(namedCount) / Double(max(totalToName, 1)))

                if let category = resolved.category, Self.suppressedCategories.contains(category) {
                    diagnostics.clustersSuppressed += 1
                    continue
                }

                seenIDs.insert(cluster.id)
                let place = Self.makePlace(
                    cluster: cluster,
                    episodeID: entry.segment.id,
                    resolved: resolved,
                    prior: priorByID[cluster.id]
                )
                if priorByID[cluster.id] != nil { diagnostics.placesCarriedOver += 1 }

                episodePlaces.append(place)
                producedPlaces.append(place)
                // Published live: this is the count on screen, and it is also
                // exactly what survives a cancellation.
                places = producedPlaces
            }

            guard !episodePlaces.isEmpty else { continue }

            producedEpisodes.append(
                Self.makeEpisode(from: entry.segment, locality: locality, placeCount: episodePlaces.count)
            )
            episodes = producedEpisodes
        }

        guard !producedPlaces.isEmpty else {
            finish(outcome: .noPlacesInTrips, diagnostics: diagnostics)
            return
        }

        print("✅ LibraryDetection: \(producedPlaces.count) places across \(producedEpisodes.count) episodes\(diagnostics.wasCancelled ? " (stopped early)" : "")")
        finish(outcome: .places, diagnostics: diagnostics, episodes: producedEpisodes, places: producedPlaces)
    }

    private func finish(
        outcome: LibraryDetectionOutcome,
        diagnostics: LibraryDetectionDiagnostics,
        episodes: [LibraryEpisode] = [],
        places: [DetectedPlace] = []
    ) {
        self.episodes = episodes
        self.places = places
        self.lastResult = LibraryDetectionResult(
            outcome: outcome,
            episodes: episodes,
            places: places,
            diagnostics: diagnostics
        )
    }

    private func reportScan(scanned: Int, total: Int, located: Int) {
        photosScanned = scanned
        photosTotal = total
        photosLocated = located
        guard total > 0 else { return }
        progress = 0.35 * (Double(scanned) / Double(total))
    }

    // MARK: - Cluster Configuration

    /// The clusterer, configured for a library pass. Everything except the
    /// place cap is left exactly as the trip path tunes it — the merge radii and
    /// significance floor were measured against real fixtures and an episode is
    /// the same kind of input a trip window is.
    private nonisolated static func clusterConfiguration(from configuration: Configuration) -> PlaceClusterer.Configuration {
        var clusterConfiguration = PlaceClusterer.Configuration.default
        clusterConfiguration.maxPlaces = configuration.maxPlacesPerEpisode
        return clusterConfiguration
    }

    // MARK: - Place Assembly

    /// Builds the `DetectedPlace`, carrying a previous run's user input forward.
    ///
    /// This is the idempotency contract in one function: the id comes from the
    /// cluster (content-derived, stable across runs), while the verdict, the
    /// note, a name the user typed and the original `createdAt` come from the
    /// previous run if there was one. A rescan therefore refreshes the
    /// machine-derived fields and touches nothing the user decided.
    private nonisolated static func makePlace(
        cluster: PlaceCluster,
        episodeID: String,
        resolved: ResolvedPlaceName,
        prior: DetectedPlace?
    ) -> DetectedPlace {
        let keepsUserName = prior?.isNameUserEdited == true
        return DetectedPlace(
            id: cluster.id,
            tripId: episodeID,
            name: keepsUserName ? (prior?.name ?? resolved.name) : resolved.name,
            latitude: cluster.latitude,
            longitude: cluster.longitude,
            category: resolved.category,
            visits: cluster.visits,
            representativeAssetIdentifier: cluster.representativeAssetIdentifier,
            allAssetIdentifiers: cluster.allAssetIdentifiers,
            source: .photoGPS,
            significance: cluster.significance,
            isNameUserEdited: keepsUserName,
            verdict: prior?.verdict,
            note: prior?.note,
            createdAt: prior?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    /// Names the episode from the locality MapKit already returned for its
    /// strongest place — no extra request, and no invented destination. When
    /// there is no locality the trip is labelled by WHEN it happened, which is
    /// something SkyLine actually knows.
    private nonisolated static func makeEpisode(
        from segment: EpisodeSegment,
        locality: String?,
        placeCount: Int
    ) -> LibraryEpisode {
        let fallback = LibraryEpisode.dateRangeText(start: segment.startDate, end: segment.endDate)
        let trimmed = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LibraryEpisode(
            id: segment.id,
            title: trimmed.isEmpty ? fallback : trimmed,
            startDate: segment.startDate,
            endDate: segment.endDate,
            latitude: segment.latitude,
            longitude: segment.longitude,
            dayCount: segment.dayCount,
            photoCount: segment.points.count,
            placeCount: placeCount
        )
    }
}

// MARK: - Library Scan

/// Raw output of the library pass. Only located photos are RETAINED —
/// unlocated ones are counted and dropped, because they cannot cluster and
/// keeping tens of thousands of them costs memory for nothing. The count is
/// what drives the "your camera did not save locations" screen.
struct LibraryScan: Sendable {
    var points: [PhotoPoint] = []
    var assetsInLibrary: Int = 0
    var assetsScanned: Int = 0
    var screenshotsExcluded: Int = 0
    var assetsWithLocation: Int = 0
    var assetsWithoutLocation: Int = 0
    var samplingStride: Int = 1
    var locatedPhotosThinned: Int = 0
    var wasCancelled: Bool = false
}

extension LibraryPlaceDetectionService {

    /// Walks every image asset in the library.
    ///
    /// DELIBERATELY NOT `PhotoAssetFetcher.fetchPoints(start:end:)`: that method
    /// is date-windowed by design, and its cap plus ascending sort would, over a
    /// whole library, silently keep the oldest photos and drop every recent
    /// trip. Two things are different here and both matter:
    ///
    ///   • NO `fetchLimit`. `PHFetchResult` is lazy — creating one over 100,000
    ///     assets is cheap — so the cost is enumeration, which is paid in
    ///     batches and can be stopped.
    ///   • Thinning, if it happens at all, is EVEN and REPORTED. On reaching
    ///     `maxLocatedPoints` the retained array is halved and the keep stride
    ///     doubles, so the sample stays spread across the whole timeline. Every
    ///     era of the library is represented at the same rate; `samplingStride`
    ///     tells the UI to say so.
    ///
    /// EXIF recovery is not attempted. `PhotoAssetFetcher` does it for a few
    /// hundred assets inside one trip; the same pass over a whole library would
    /// mean reading a file header for tens of thousands of photos to rescue a
    /// minority of imported ones. That is minutes of I/O for a small yield, and
    /// it is the wrong trade on the very first screen a user sees.
    nonisolated static func scanLibrary(
        configuration: Configuration,
        onProgress: @escaping @Sendable (Int, Int, Int) async -> Void
    ) async -> LibraryScan {
        let options = PHFetchOptions()
        // Only mediaType is filtered. PHFetchOptions.predicate does not accept
        // `location` as a key — putting it there raises an unsupported-predicate
        // exception at fetch time — so the GPS filter happens in memory below.
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false   // one representative frame per burst
        // The user's own library only. Shared-album assets are other people's
        // photos, often from cities the user never visited, and would invent
        // trips out of nothing.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.wantsIncrementalChangeDetails = false
        // NOTE the absence of `options.fetchLimit`. See the doc comment.

        let result = PHAsset.fetchAssets(with: options)
        var scan = LibraryScan()
        scan.assetsInLibrary = result.count
        await onProgress(0, result.count, 0)

        guard result.count > 0 else {
            print("📭 LibraryScan: No image assets in the library")
            return scan
        }
        print("🔄 LibraryScan: \(result.count) image assets in the library")

        var points: [PhotoPoint] = []
        points.reserveCapacity(min(result.count, 8192))
        var keepEveryNth = 1
        var locatedSeen = 0
        var screenshots = 0
        var withoutLocation = 0
        var thinned = 0
        var scanned = 0

        while scanned < result.count {
            if Task.isCancelled {
                scan.wasCancelled = true
                print("🛑 LibraryScan: Stopped after \(scanned)/\(result.count) assets")
                break
            }
            let upper = min(scanned + max(configuration.batchSize, 1), result.count)

            result.enumerateObjects(at: IndexSet(integersIn: scanned..<upper), options: []) { asset, _, _ in
                if asset.mediaSubtypes.contains(.photoScreenshot) {
                    screenshots += 1
                    if configuration.excludeScreenshots { return }
                }
                // A photo with no creation date cannot be placed on the
                // timeline, and the timeline is what segments trips.
                guard let created = asset.creationDate else { return }
                guard let location = asset.location else {
                    withoutLocation += 1
                    return
                }

                locatedSeen += 1
                // Even sampling, phase-aligned so that halving below keeps the
                // same lattice of retained photos.
                guard (locatedSeen - 1) % keepEveryNth == 0 else { return }

                points.append(
                    PhotoPoint(
                        id: asset.localIdentifier,
                        timestamp: created,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        horizontalAccuracy: location.horizontalAccuracy,
                        isScreenshot: false,
                        isFavorite: asset.isFavorite,
                        isPanorama: asset.mediaSubtypes.contains(.photoPanorama),
                        isDepthEffect: asset.mediaSubtypes.contains(.photoDepthEffect),
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight
                    )
                )

                if points.count >= configuration.maxLocatedPoints {
                    var kept: [PhotoPoint] = []
                    kept.reserveCapacity(points.count / 2 + 1)
                    for (offset, point) in points.enumerated() where offset % 2 == 0 {
                        kept.append(point)
                    }
                    thinned += points.count - kept.count
                    points = kept
                    keepEveryNth *= 2
                    print("⚠️ LibraryScan: Over \(configuration.maxLocatedPoints) located photos — thinning to every \(keepEveryNth)th across the whole library")
                }
            }

            scanned = upper
            await onProgress(scanned, result.count, points.count)
        }

        scan.points = points
        scan.assetsScanned = scanned
        scan.screenshotsExcluded = screenshots
        scan.assetsWithLocation = locatedSeen
        scan.assetsWithoutLocation = withoutLocation
        scan.samplingStride = keepEveryNth
        scan.locatedPhotosThinned = thinned
        print("🔄 LibraryScan: \(locatedSeen) located / \(scanned) scanned → \(points.count) points retained (every \(keepEveryNth)th)")
        return scan
    }
}

// MARK: - Home + Episodes

/// Where the user lives, in the only sense this file needs: the point most of
/// their DAYS happen around.
struct LibraryHomeAnchor: Sendable, Hashable {
    let latitude: Double
    let longitude: Double
    /// Distinct days of photos in the winning cell — the strength of the signal.
    let dayCount: Int
    let photoCount: Int
}

/// One trip-shaped run of days, with the points that belong to it.
struct EpisodeSegment: Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let latitude: Double
    let longitude: Double
    let dayCount: Int
    let points: [PhotoPoint]
}

struct LibrarySegmentation: Sendable {
    let home: LibraryHomeAnchor?
    let episodes: [EpisodeSegment]
    let daysWithPhotos: Int
    let awayDays: Int
}

extension LibraryPlaceDetectionService {

    /// Pure, synchronous, PhotoKit-free: home detection plus episode
    /// segmentation over an array of points. Same discipline as
    /// `PlaceClusterer` — everything here is drivable from a fixture.
    nonisolated static func segmentation(
        points: [PhotoPoint],
        configuration: Configuration = .default
    ) -> LibrarySegmentation {
        let located = points.filter(\.hasLocation)
        guard !located.isEmpty else {
            return LibrarySegmentation(home: nil, episodes: [], daysWithPhotos: 0, awayDays: 0)
        }

        let calendar = Calendar.current
        let home = findHome(points: located, configuration: configuration)

        // No believable home. Two very different libraries land here, and they
        // must not be treated the same:
        //   • A genuinely nomadic or travel-only library — every day is away.
        //   • A thin library of a few days, all in one town — nothing is away.
        // The spatial extent tells them apart, so a new user's first week of
        // photos around their own flat does not become "a trip".
        if home == nil {
            let extent = spread(of: located)
            if extent < configuration.homeRadiusMeters {
                print("🏠 LibraryDetection: No home anchor and only \(Int(extent)) m of spread — nothing trip-shaped")
                return LibrarySegmentation(
                    home: nil,
                    episodes: [],
                    daysWithPhotos: dayCount(of: located, calendar: calendar),
                    awayDays: 0
                )
            }
        }

        let survey = awayDayCentroids(located, home: home, calendar: calendar, configuration: configuration)
        let episodes = buildEpisodes(from: survey.days, configuration: configuration)
        print("🗺️ LibraryDetection: \(survey.totalDays) days with photos, \(survey.days.count) away, \(episodes.count) episodes")
        return LibrarySegmentation(
            home: home,
            episodes: episodes,
            daysWithPhotos: survey.totalDays,
            awayDays: survey.days.count
        )
    }

    // MARK: Home

    /// Home is the grid cell present on the most DISTINCT DAYS.
    ///
    /// Ranking by photo count instead would be wrong in a very specific and
    /// common way: a single photogenic week abroad easily out-shoots a whole
    /// month of ordinary life, so the "home" anchor would land on the last
    /// holiday and every real trip — including the one that won — would then
    /// measure as "near home" and vanish. Days are the honest unit: you can
    /// out-photograph your home town on a trip, but you cannot out-LAST it.
    nonisolated static func findHome(
        points: [PhotoPoint],
        configuration: Configuration = .default
    ) -> LibraryHomeAnchor? {
        struct Cell: Hashable { let x: Int; let y: Int }

        let size = max(configuration.homeCellDegrees, 0.01)
        var daysPerCell: [Cell: Set<Int>] = [:]
        var photosPerCell: [Cell: Int] = [:]
        var membersPerCell: [Cell: [PhotoPoint]] = [:]
        let calendar = Calendar.current

        for point in points {
            guard let lat = point.latitude, let lng = point.longitude else { continue }
            let cell = Cell(
                x: Int((lat / size).rounded(.down)),
                y: Int((lng / size).rounded(.down))
            )
            daysPerCell[cell, default: []].insert(dayIndex(of: point.timestamp, calendar: calendar))
            photosPerCell[cell, default: 0] += 1
            membersPerCell[cell, default: []].append(point)
        }

        // Deterministic ordering all the way down, so two runs over the same
        // library never pick different homes.
        let winner = daysPerCell.keys.max { a, b in
            let dayA = daysPerCell[a]?.count ?? 0
            let dayB = daysPerCell[b]?.count ?? 0
            if dayA != dayB { return dayA < dayB }
            let photoA = photosPerCell[a] ?? 0
            let photoB = photosPerCell[b] ?? 0
            if photoA != photoB { return photoA < photoB }
            return (a.x, a.y) < (b.x, b.y)
        }

        guard let winner,
              let dayCount = daysPerCell[winner]?.count,
              dayCount >= configuration.minimumHomeDays,
              let members = membersPerCell[winner], !members.isEmpty else {
            return nil
        }

        // Median rather than mean: one stray fix on the far side of the city
        // must not drag the anchor.
        let latitude = median(members.compactMap(\.latitude))
        let longitude = median(members.compactMap(\.longitude))

        // The winner has to be a clear one. Rivals are only counted somewhere
        // genuinely else — a neighbouring cell of the same city is the same
        // home, not a competitor for the title.
        var rivalDays = 0
        for (cell, cellDays) in daysPerCell where cell != winner {
            guard let cellMembers = membersPerCell[cell], !cellMembers.isEmpty else { continue }
            let cellLat = median(cellMembers.compactMap(\.latitude))
            let cellLng = median(cellMembers.compactMap(\.longitude))
            let distance = GeoMath.distance(lat1: latitude, lng1: longitude, lat2: cellLat, lng2: cellLng)
            guard distance > configuration.homeRadiusMeters else { continue }
            rivalDays = max(rivalDays, cellDays.count)
        }
        guard Double(dayCount) >= configuration.homeDominanceRatio * Double(rivalDays) else {
            print("🏠 LibraryDetection: No clear home — best cell has \(dayCount) days against a rival's \(rivalDays)")
            return nil
        }

        print("🏠 LibraryDetection: Home ≈ \(String(format: "%.3f", latitude)), \(String(format: "%.3f", longitude)) — \(dayCount) days, \(members.count) photos")
        return LibraryHomeAnchor(
            latitude: latitude,
            longitude: longitude,
            dayCount: dayCount,
            photoCount: photosPerCell[winner] ?? members.count
        )
    }

    // MARK: Episodes

    /// Groups away-days into runs.
    ///
    /// Two rules decide whether the next away-day joins the run in progress:
    ///
    ///   TIME — a gap of more than `bridgeDays` days without away-photos ends
    ///   the trip. You do not shoot every day of a holiday, and a quiet
    ///   Wednesday is not a border between two trips.
    ///
    ///   SPACE — the new day must sit within `maxEpisodeDiameterMeters` of
    ///   EVERY day already in the run, not merely of the run's centre. Checking
    ///   against the centre allows drift: a road trip adds 200 km a day, each
    ///   step passes, and the finished episode spans a thousand kilometres —
    ///   at which point `PlaceClusterer`'s own outlier rejection quietly
    ///   deletes one end of it. Bounding the DIAMETER makes that impossible by
    ///   construction.
    private nonisolated static func buildEpisodes(
        from awayDays: [DayCentroid],
        configuration: Configuration
    ) -> [EpisodeSegment] {
        guard !awayDays.isEmpty else { return [] }
        let sorted = awayDays.sorted { $0.index < $1.index }

        var runs: [[DayCentroid]] = []
        var current: [DayCentroid] = []

        func fits(_ day: DayCentroid) -> Bool {
            guard let last = current.last else { return true }
            if day.index - last.index > configuration.bridgeDays + 1 { return false }
            for member in current {
                let distance = GeoMath.distance(
                    lat1: member.latitude, lng1: member.longitude,
                    lat2: day.latitude, lng2: day.longitude
                )
                if distance > configuration.maxEpisodeDiameterMeters { return false }
            }
            return true
        }

        for day in sorted {
            if current.isEmpty || fits(day) {
                current.append(day)
            } else {
                runs.append(current)
                current = [day]
            }
        }
        if !current.isEmpty { runs.append(current) }

        return runs.compactMap { run -> EpisodeSegment? in
            let points = run.flatMap(\.points).sorted { $0.timestamp < $1.timestamp }
            guard points.count >= configuration.minimumEpisodePhotos,
                  let first = points.first, let last = points.last else { return nil }

            let latitude = median(points.compactMap(\.latitude))
            // Circular mean, so a run of days in Fiji does not average into the
            // Atlantic — the same defence `PlaceClusterer` uses.
            let longitude = GeoMath.meanLongitude(points.compactMap(\.longitude))

            return EpisodeSegment(
                id: episodeID(start: first.timestamp, end: last.timestamp, latitude: latitude, longitude: longitude),
                startDate: first.timestamp,
                endDate: last.timestamp,
                latitude: latitude,
                longitude: longitude,
                dayCount: run.count,
                points: points
            )
        }
    }

    /// Stable across runs: same dates and same rough position give the same id.
    ///
    /// Rounded to 0.1° (~11 km) and to whole days on purpose, so a few new
    /// photos nudging the centroid do not mint a new episode. Place identity
    /// does not depend on this — a `DetectedPlace`'s id comes from its own
    /// photos — so even when an episode is relabelled, the verdicts attached to
    /// its places survive.
    private nonisolated static func episodeID(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double
    ) -> String {
        let calendar = Calendar.current
        let fingerprint = [
            String(dayIndex(of: start, calendar: calendar)),
            String(dayIndex(of: end, calendar: calendar)),
            String(format: "%.1f", latitude),
            String(format: "%.1f", longitude)
        ].joined(separator: "|")
        return "episode-\(PlaceClusterer.stableHash(fingerprint))"
    }

    // MARK: Day Math

    struct DayCentroid: Sendable {
        let index: Int
        let latitude: Double
        let longitude: Double
        let points: [PhotoPoint]
    }

    /// The days spent away from home, carrying ONLY the photos taken away.
    ///
    /// Both halves of that sentence are load-bearing:
    ///
    ///   A day counts as away when MOST of its photos are away from home. The
    ///   majority test, rather than "the day's centroid is far", is what makes
    ///   travel days work: you fly out with two photos in your kitchen and
    ///   thirty in Lisbon, and that is a Lisbon day.
    ///
    ///   The day then contributes only its away photos. Keeping the kitchen
    ///   ones was a measured bug, not a hypothetical: on a fixture of seven
    ///   Lisbon days that also held three London photos each, the episode
    ///   centroid landed at -7.97° instead of -9.14° — about 100 km out into
    ///   the Alentejo, far enough that `PlaceClusterer`'s outlier rejection
    ///   would start discarding real places at the far edge of the city.
    ///   Latitude survived because it is a median; longitude did not, because
    ///   a circular mean has no defence against a fifth of its input sitting
    ///   nine degrees away.
    ///
    /// ASSUMPTION, stated because it is real: days are bucketed with
    /// `Calendar.current`, i.e. the device's CURRENT time zone, not the zone the
    /// photo was taken in. A trip to Tokyo logged from London therefore has its
    /// day boundaries shifted by up to nine hours, which can move a late-night
    /// photo into the neighbouring day. That costs nothing here — the
    /// segmentation works at day granularity with a two-day bridge, so a photo
    /// landing one day either side changes no episode boundary.
    private nonisolated static func awayDayCentroids(
        _ points: [PhotoPoint],
        home: LibraryHomeAnchor?,
        calendar: Calendar,
        configuration: Configuration
    ) -> (days: [DayCentroid], totalDays: Int) {
        var buckets: [Int: [PhotoPoint]] = [:]
        for point in points where point.hasLocation {
            buckets[dayIndex(of: point.timestamp, calendar: calendar), default: []].append(point)
        }

        let days: [DayCentroid] = buckets.compactMap { index, dayPoints in
            let away: [PhotoPoint]
            if let home {
                away = dayPoints.filter { point in
                    guard let lat = point.latitude, let lng = point.longitude else { return false }
                    return GeoMath.distance(
                        lat1: home.latitude, lng1: home.longitude,
                        lat2: lat, lng2: lng
                    ) > configuration.homeRadiusMeters
                }
            } else {
                away = dayPoints
            }
            // Majority, so an ordinary day with one distant stray fix is not a trip.
            guard away.count * 2 > dayPoints.count, !away.isEmpty else { return nil }
            return DayCentroid(
                index: index,
                latitude: median(away.compactMap(\.latitude)),
                // Circular mean, so a day in Fiji does not average into the
                // Atlantic — the same defence `PlaceClusterer` uses.
                longitude: GeoMath.meanLongitude(away.compactMap(\.longitude)),
                points: away
            )
        }

        return (days.sorted { $0.index < $1.index }, buckets.count)
    }

    private nonisolated static func dayCount(of points: [PhotoPoint], calendar: Calendar) -> Int {
        var days = Set<Int>()
        for point in points where point.hasLocation {
            days.insert(dayIndex(of: point.timestamp, calendar: calendar))
        }
        return days.count
    }

    private nonisolated static func dayIndex(of date: Date, calendar: Calendar) -> Int {
        Int(floor(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400))
    }

    /// Max distance from the median point — how far the library sprawls.
    private nonisolated static func spread(of points: [PhotoPoint]) -> Double {
        let latitudes = points.compactMap(\.latitude)
        let longitudes = points.compactMap(\.longitude)
        guard !latitudes.isEmpty, !longitudes.isEmpty else { return 0 }
        let centreLat = median(latitudes)
        let centreLng = GeoMath.meanLongitude(longitudes)
        return points.compactMap { point -> Double? in
            guard let lat = point.latitude, let lng = point.longitude else { return nil }
            return GeoMath.distance(lat1: centreLat, lng1: centreLng, lat2: lat, lng2: lng)
        }.max() ?? 0
    }

    private nonisolated static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
