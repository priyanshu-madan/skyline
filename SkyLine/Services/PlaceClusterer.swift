//
//  PlaceClusterer.swift
//  SkyLine
//
//  Pure, synchronous, dependency-free clustering of photo points into places.
//  No PhotoKit, no MapKit, no network, no actor isolation — so the whole
//  algorithm is unit-testable from a fixture array.
//

import Foundation

// MARK: - Cluster Output

/// A clustering result, before naming. `PhotoPlaceDetectionService` turns these
/// into `DetectedPlace` once names are resolved.
struct PlaceCluster: Identifiable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let visits: [PhotoVisitSession]
    let representativeAssetIdentifier: String?
    let significance: Double

    var allAssetIdentifiers: [String] { visits.flatMap(\.assetIdentifiers) }
    var photoCount: Int { visits.reduce(0) { $0 + $1.photoCount } }
    var visitCount: Int { visits.count }
    var spanStart: Date? { visits.map(\.startDate).min() }
    var spanEnd: Date? { visits.map(\.endDate).max() }

    /// Radius, in metres, that contains every visit centroid. Used to size the
    /// POI search radius during naming — a sprawling cluster (a park) needs a
    /// wider search than a tight one (a bar).
    let spreadMeters: Double
}

// MARK: - Clusterer

struct PlaceClusterer {

    // MARK: Configuration

    struct Configuration: Sendable {
        /// Radius within which consecutive photos are treated as the same stay.
        ///
        /// WHY 150 m: consumer photo GPS is a fused GNSS + Wi-Fi + cell fix.
        /// Horizontal accuracy is typically 5–65 m outdoors and degrades past
        /// 100 m in urban canyons and indoors. A threshold below ~100 m
        /// fragments a single stationary dinner into three "places", which is
        /// the worst possible failure for a swipe deck. 150 m sits above that
        /// noise floor while staying inside the scale of a single venue.
        ///
        /// The cost, stated plainly: 150 m will merge two adjacent restaurants
        /// on the same block. That is the right trade — a wrongly merged pair
        /// is one card the user can rename, while a wrongly split single place
        /// is two cards that make the app look like it does not understand
        /// where they were.
        var visitRadiusMeters: Double = 150

        /// Gap between consecutive photos that ends a stay.
        ///
        /// WHY 90 min: long enough to survive a full sit-down meal or a museum
        /// where you shoot at the entrance and again on the way out with a long
        /// quiet stretch between. Short enough that "the market in the morning,
        /// the same street at night" reads as two visits rather than one
        /// twelve-hour blur. It is also comfortably shorter than a night's
        /// sleep, so a hotel produces one visit per night rather than one visit
        /// for the whole trip.
        var visitGapSeconds: TimeInterval = 90 * 60

        /// Base radius for merging visits across time into a single place.
        ///
        /// This is a FLOOR, not the whole story — see `mergeThreshold`. A fixed
        /// merge radius cannot work, and the measurement that proved it is
        /// worth stating: on a six-place Tokyo fixture over 30 randomised runs,
        ///   150 m → never merged two distinct places, but shattered a
        ///           sprawling temple complex into 2+ cards in 15/30 runs
        ///   250 m → never shattered the temple, but merged a hotel with a
        ///           crossing 194 m away in 30/30 runs
        /// One number has to serve two incompatible jobs: absorbing GPS noise
        /// between repeat visits to a POINT venue (wants to be small, because
        /// averaging several photos already shrinks that noise), and holding a
        /// SPRAWLING venue together (wants to be large). So the threshold is
        /// derived per-pair from the visits' own measured extent instead.
        var placeMergeRadiusMeters: Double = 130

        /// Hard ceiling on the adaptive merge threshold. Beyond this, two
        /// stays are different places no matter how scattered their photos are.
        var maxMergeRadiusMeters: Double = 350

        /// How much of the visits' own spread is added to the base radius.
        /// base 130 m / coefficient 1.0 was picked off a 30-run randomised sweep
        /// of the Tokyo fixture and scores 30/30 on every assertion. It sits in
        /// the MIDDLE of the passing plateau (base 110–150 × coefficient
        /// 0.75–1.25 all pass), not on its edge, so ordinary GPS variation does
        /// not tip it over. Concretely: two tight visits get a ≈155 m threshold
        /// and stay apart at 194 m, while a temple whose photos scatter over
        /// 170 m gets the 350 m ceiling and stays whole.
        var spreadMergeCoefficient: Double = 1.0

        /// Maximum places returned. Target is "the ~12 places you actually
        /// spent time", with headroom so a genuinely busy trip is not truncated
        /// too aggressively.
        var maxPlaces: Int = 14

        /// A cluster further than this from the photo-set median is dropped as
        /// an outlier — home, a layover in another country. Deliberately
        /// generous so a legitimate multi-city trip survives.
        ///
        /// NOTE this CANNOT catch airports: the fixture's Narita cluster sits
        /// 64 km from central Tokyo and survives every radius loose enough to
        /// permit a day trip. Airports are handled by category suppression
        /// after naming — see `PhotoPlaceDetectionService.suppressedCategories`.
        var outlierRadiusMeters: Double = 300_000

        /// GPS fixes worse than this are treated as unlocated. `-1` accuracy
        /// (CoreLocation's "invalid") is always rejected.
        var maxAcceptableHorizontalAccuracyMeters: Double = 500

        /// Clusters scoring below this are discarded even if there is room.
        /// A single drive-by photo is not a place: it scores
        /// 1 photo + 2×1 visit + 0 dwell = 3.0, so the floor sits just above at 4.0.
        /// Two photos, or one photo at a place you returned to, clears it.
        var minimumSignificance: Double = 4.0

        static let `default` = Configuration()
    }

    let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Entry Point

    /// Cluster geotagged points into places.
    ///
    /// Two stages, on purpose:
    ///   Stage 1 segments the timeline into *visits* (spatio-temporal stay-point
    ///   detection). This is where time matters.
    ///   Stage 2 merges visits into *places* using space only. This is where
    ///   the "same restaurant on Tuesday and Friday" case collapses to one card.
    ///
    /// Doing it in one pass with both thresholds cannot produce that collapse:
    /// a single pass either splits repeat visits into separate clusters, or
    /// drops the time dimension and glues a whole neighbourhood together.
    func cluster(points: [PhotoPoint]) -> [PlaceCluster] {
        let located = points
            .filter { isUsableFix($0) }
            .sorted { $0.timestamp < $1.timestamp }

        guard !located.isEmpty else {
            print("⚠️ PlaceClusterer: No usable geotagged points")
            return []
        }

        let visits = segmentIntoVisits(located)
        print("🔄 PlaceClusterer: \(located.count) points → \(visits.count) visits")

        let merged = mergeVisitsIntoPlaces(visits, points: located)
        print("🔄 PlaceClusterer: \(visits.count) visits → \(merged.count) places")

        let filtered = rejectOutliers(merged, points: located)
        let ranked = filtered
            .filter { $0.significance >= configuration.minimumSignificance }
            .sorted { $0.significance > $1.significance }

        let trimmed = Array(ranked.prefix(configuration.maxPlaces))
        print("✅ PlaceClusterer: \(trimmed.count) places after ranking and trim")
        return trimmed
    }

    /// Number of clusters dropped by outlier rejection, for diagnostics.
    func outlierCount(points: [PhotoPoint]) -> Int {
        let located = points.filter { isUsableFix($0) }.sorted { $0.timestamp < $1.timestamp }
        guard !located.isEmpty else { return 0 }
        let merged = mergeVisitsIntoPlaces(segmentIntoVisits(located), points: located)
        return merged.count - rejectOutliers(merged, points: located).count
    }

    // MARK: - Stage 0: Fix Quality

    private func isUsableFix(_ point: PhotoPoint) -> Bool {
        guard point.hasLocation else { return false }
        guard let accuracy = point.horizontalAccuracy else { return true }
        // CoreLocation reports a negative horizontalAccuracy when the fix is invalid.
        guard accuracy >= 0 else { return false }
        return accuracy <= configuration.maxAcceptableHorizontalAccuracyMeters
    }

    // MARK: - Stage 1: Segment Into Visits

    /// Sequential stay-point detection. Walk the timeline; start a new visit
    /// when either the time gap or the distance from the running centroid
    /// exceeds threshold.
    ///
    /// The distance is measured against the *running centroid* rather than the
    /// previous photo. Measuring against the previous photo lets a slow walk
    /// chain indefinitely — every step is under 150 m, so a two-kilometre stroll
    /// becomes one "place". Measuring against the centroid caps the true
    /// diameter of a visit at roughly 2 × the radius.
    private func segmentIntoVisits(_ points: [PhotoPoint]) -> [PhotoVisitSession] {
        var visits: [PhotoVisitSession] = []
        var current: [PhotoPoint] = []
        var centroidLat = 0.0
        var centroidLng = 0.0

        func flush() {
            guard !current.isEmpty else { return }
            let lats = current.compactMap(\.latitude)
            let lngs = current.compactMap(\.longitude)
            guard !lats.isEmpty else { current = []; return }
            let meanLat = lats.reduce(0, +) / Double(lats.count)
            let meanLng = GeoMath.meanLongitude(lngs)
            let spread = current.compactMap { point -> Double? in
                guard let lat = point.latitude, let lng = point.longitude else { return nil }
                return GeoMath.distance(lat1: meanLat, lng1: meanLng, lat2: lat, lng2: lng)
            }.max() ?? 0
            visits.append(
                PhotoVisitSession(
                    startDate: current.first!.timestamp,
                    endDate: current.last!.timestamp,
                    assetIdentifiers: current.map(\.id),
                    latitude: meanLat,
                    longitude: meanLng,
                    spreadMeters: spread
                )
            )
            current = []
        }

        for point in points {
            guard let lat = point.latitude, let lng = point.longitude else { continue }

            if current.isEmpty {
                current = [point]
                centroidLat = lat
                centroidLng = lng
                continue
            }

            let gap = point.timestamp.timeIntervalSince(current.last!.timestamp)
            let distance = GeoMath.distance(lat1: centroidLat, lng1: centroidLng, lat2: lat, lng2: lng)

            if gap > configuration.visitGapSeconds || distance > configuration.visitRadiusMeters {
                flush()
                current = [point]
                centroidLat = lat
                centroidLng = lng
            } else {
                current.append(point)
                let n = Double(current.count)
                centroidLat += (lat - centroidLat) / n
                centroidLng += (lng - centroidLng) / n
            }
        }
        flush()
        return visits
    }

    // MARK: - Stage 2: Merge Visits Into Places

    /// Greedy agglomeration seeded by visit weight, deliberately NOT by time.
    ///
    /// Seeding by time causes chaining drift: A→B is 200 m, B→C is 200 m, and C
    /// ends up in a cluster whose anchor is 400 m away. Seeding from the
    /// heaviest visit first makes the most-photographed stay the anchor, so
    /// incidental photos attach to real places instead of dragging the centroid
    /// around. It also makes the output deterministic for a given input, which
    /// matters because the user can leave the swipe deck and come back to it.
    private func mergeVisitsIntoPlaces(_ visits: [PhotoVisitSession], points: [PhotoPoint]) -> [PlaceCluster] {
        guard !visits.isEmpty else { return [] }
        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        // Heaviest first; stable tie-break on start date so the result is
        // reproducible run to run.
        let ordered = visits.sorted {
            if $0.photoCount != $1.photoCount { return $0.photoCount > $1.photoCount }
            return $0.startDate < $1.startDate
        }

        var groups: [[PhotoVisitSession]] = []
        var centroids: [(lat: Double, lng: Double, weight: Double, spread: Double)] = []

        for visit in ordered {
            var bestIndex: Int?
            var bestDistance = Double.greatestFiniteMagnitude

            for (index, centroid) in centroids.enumerated() {
                let d = GeoMath.distance(
                    lat1: centroid.lat, lng1: centroid.lng,
                    lat2: visit.latitude, lng2: visit.longitude
                )
                let threshold = mergeThreshold(visitSpread: visit.spreadMeters, clusterSpread: centroid.spread)
                if d <= threshold && d < bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
            }

            if let index = bestIndex {
                groups[index].append(visit)
                // Photo-count-weighted centroid update: a 40-photo visit should
                // pull the centroid far harder than a 1-photo drive-by.
                let w = Double(visit.photoCount)
                let existing = centroids[index]
                let total = existing.weight + w
                centroids[index] = (
                    lat: (existing.lat * existing.weight + visit.latitude * w) / total,
                    lng: (existing.lng * existing.weight + visit.longitude * w) / total,
                    weight: total,
                    // The cluster inherits the widest extent it has seen: once a
                    // place is known to sprawl, it keeps that tolerance.
                    spread: max(existing.spread, visit.spreadMeters)
                )
            } else {
                groups.append([visit])
                centroids.append((lat: visit.latitude, lng: visit.longitude,
                                  weight: Double(visit.photoCount), spread: visit.spreadMeters))
            }
        }

        return zip(groups, centroids).map { group, centroid in
            let chronological = group.sorted { $0.startDate < $1.startDate }
            let assetIDs = chronological.flatMap(\.assetIdentifiers)
            let clusterPoints = assetIDs.compactMap { pointsByID[$0] }
            let spread = chronological
                .map { GeoMath.distance(lat1: centroid.lat, lng1: centroid.lng, lat2: $0.latitude, lng2: $0.longitude) }
                .max() ?? 0

            return PlaceCluster(
                id: UUID().uuidString,
                latitude: centroid.lat,
                longitude: centroid.lng,
                visits: chronological,
                representativeAssetIdentifier: pickRepresentative(from: clusterPoints)?.id,
                significance: significance(for: chronological),
                spreadMeters: spread
            )
        }
    }

    /// Distance under which two stays are the same place.
    ///
    /// Derived from the evidence rather than fixed: the spatial extent of the
    /// photos themselves says whether this is a point venue or a sprawling one.
    /// Two visits whose photos each sit inside 20 m are a cafe and must stay
    /// apart from the bar next door; two visits whose photos scatter over 170 m
    /// are a temple complex or a park and must not be split down the middle.
    func mergeThreshold(visitSpread: Double, clusterSpread: Double) -> Double {
        let adaptive = configuration.placeMergeRadiusMeters
            + configuration.spreadMergeCoefficient * (visitSpread + clusterSpread)
        return min(adaptive, configuration.maxMergeRadiusMeters)
    }

    // MARK: - Stage 3: Outlier Rejection

    /// Drop clusters far from the body of the trip — home, a distant layover.
    ///
    /// Anchored on the MEDIAN of all located photos, not the mean and not the
    /// trip's declared coordinate. The median is robust: a hundred photos at
    /// home cannot move it if the trip itself has more, and it works for a
    /// multi-city trip whose declared destination is only one of the cities.
    ///
    /// Safety valve: if the filter would remove everything, keep everything.
    /// A blank deck is always worse than a slightly wrong one.
    private func rejectOutliers(_ clusters: [PlaceCluster], points: [PhotoPoint]) -> [PlaceCluster] {
        guard clusters.count > 1 else { return clusters }
        let lats = points.compactMap(\.latitude).sorted()
        let lngs = points.compactMap(\.longitude).sorted()
        guard !lats.isEmpty, !lngs.isEmpty else { return clusters }

        let medianLat = lats[lats.count / 2]
        let medianLng = lngs[lngs.count / 2]

        let kept = clusters.filter {
            GeoMath.distance(lat1: medianLat, lng1: medianLng, lat2: $0.latitude, lng2: $0.longitude)
                <= configuration.outlierRadiusMeters
        }

        if kept.isEmpty {
            print("⚠️ PlaceClusterer: Outlier filter would drop every cluster — keeping all")
            return clusters
        }
        if kept.count != clusters.count {
            print("🔄 PlaceClusterer: Dropped \(clusters.count - kept.count) outlier cluster(s)")
        }
        return kept
    }

    // MARK: - Significance

    /// How much this place deserves a card.
    ///
    ///   photoCount        — you shot it, you cared
    ///   2 × visitCount    — you went BACK, which is the strongest signal there is
    ///   dwell, capped     — capped at 4 h so one long lazy afternoon cannot
    ///                       outrank three deliberate stops
    func significance(for visits: [PhotoVisitSession]) -> Double {
        let photos = Double(visits.reduce(0) { $0 + $1.photoCount })
        let returns = 2.0 * Double(visits.count)
        let dwellHours = visits.reduce(0.0) { $0 + $1.dwell } / 3600.0
        return photos + returns + min(dwellHours, 4.0)
    }

    // MARK: - Representative Photo

    /// Pick the hero image for a cluster. Deterministic, cheap, explainable —
    /// no ML, no image decoding. The ranking below is the whole heuristic:
    ///
    ///   favourite            +100   an explicit signal from the user, unbeatable
    ///   screenshot          -1000   never a photo of a place
    ///   burst density       + 10×n  the moment you shot most is the moment you
    ///                               were most engaged; n = photos within ±7.5 min
    ///   portrait mode        +  5   a deliberately composed shot
    ///   panorama             -  8   crops badly into a card
    ///   extreme aspect       -  5   very tall/wide images letterbox in the deck
    func pickRepresentative(from points: [PhotoPoint]) -> PhotoPoint? {
        let candidates = points.filter { !$0.isScreenshot }
        let pool = candidates.isEmpty ? points : candidates
        guard !pool.isEmpty else { return nil }

        let window: TimeInterval = 7.5 * 60

        func score(_ point: PhotoPoint) -> Double {
            var s = 0.0
            if point.isFavorite { s += 100 }
            if point.isScreenshot { s -= 1000 }
            let neighbours = pool.filter { abs($0.timestamp.timeIntervalSince(point.timestamp)) <= window }.count
            s += 10.0 * Double(neighbours)
            if point.isDepthEffect { s += 5 }
            if point.isPanorama { s -= 8 }
            let ratio = point.aspectRatio
            if ratio > 2.2 || ratio < 0.45 { s -= 5 }
            return s
        }

        return pool
            .map { (point: $0, score: score($0)) }
            .sorted {
                // Stable tie-break on timestamp then id so the hero image does
                // not shuffle between runs.
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.point.timestamp != $1.point.timestamp { return $0.point.timestamp < $1.point.timestamp }
                return $0.point.id < $1.point.id
            }
            .first?.point
    }

    // MARK: - Time-Only Fallback

    /// Cluster by time alone, for the case where NOTHING has GPS.
    /// Produces the shape of the trip: "23 photos on Tue afternoon".
    /// Every returned visit has a representative photo but no coordinate —
    /// the caller turns each into a `.photoTimeOnly` place awaiting user input.
    func segmentByTimeOnly(points: [PhotoPoint]) -> [PhotoVisitSession] {
        let usable = points
            .filter { !$0.isScreenshot }
            .sorted { $0.timestamp < $1.timestamp }
        guard !usable.isEmpty else { return [] }

        var visits: [PhotoVisitSession] = []
        var current: [PhotoPoint] = [usable[0]]

        for point in usable.dropFirst() {
            let gap = point.timestamp.timeIntervalSince(current.last!.timestamp)
            if gap > configuration.visitGapSeconds {
                visits.append(
                    PhotoVisitSession(
                        startDate: current.first!.timestamp,
                        endDate: current.last!.timestamp,
                        assetIdentifiers: current.map(\.id),
                        latitude: 0, longitude: 0,    // unknown — never rendered as a coordinate
                        spreadMeters: 0
                    )
                )
                current = [point]
            } else {
                current.append(point)
            }
        }
        visits.append(
            PhotoVisitSession(
                startDate: current.first!.timestamp,
                endDate: current.last!.timestamp,
                assetIdentifiers: current.map(\.id),
                latitude: 0, longitude: 0,
                spreadMeters: 0
            )
        )

        // A session of one or two photos is usually a passing snap, not a stop.
        // Keep the substantial ones, ordered by size, so the deck stays short.
        return visits
            .filter { $0.photoCount >= 3 || $0.dwell >= 10 * 60 }
            .sorted { $0.photoCount > $1.photoCount }
    }
}

// MARK: - Geo Math

/// Haversine on raw Doubles. Deliberately not `CLLocation.distance(from:)` —
/// clustering makes O(n·k) distance calls and allocating a CLLocation per call
/// dominates the runtime on a 5,000-photo library.
enum GeoMath {
    static let earthRadiusMeters = 6_371_000.0

    static func distance(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Circular mean of longitudes, so a cluster straddling the antimeridian
    /// (Fiji, Kiribati, the Chukotka coast) does not average to 0° in the
    /// Atlantic. A plain arithmetic mean of -179 and +179 gives 0.
    static func meanLongitude(_ longitudes: [Double]) -> Double {
        guard !longitudes.isEmpty else { return 0 }
        var x = 0.0, y = 0.0
        for lng in longitudes {
            let r = lng * .pi / 180
            x += cos(r)
            y += sin(r)
        }
        guard abs(x) > 1e-12 || abs(y) > 1e-12 else { return longitudes[0] }
        return atan2(y / Double(longitudes.count), x / Double(longitudes.count)) * 180 / .pi
    }
}
