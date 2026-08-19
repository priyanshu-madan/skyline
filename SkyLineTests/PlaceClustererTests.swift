//
//  PlaceClustererTests.swift
//  SkyLineTests
//
//  The clusterer turns a camera roll into the places someone actually spent
//  time at. Everything downstream - the verdict deck, the map, the shared
//  guide - is built on its output, so it is the single most load-bearing
//  algorithm in the app.
//
//  It is a pure function over [PhotoPoint], which is why these tests need no
//  photo library, no simulator permissions and no fixtures on disk.
//

import Testing
import Foundation
@testable import SkyLine

// MARK: - Fixture

/// Real Tokyo coordinates, matching the synthetic library used for on-device
/// checks so failures can be compared against what the simulator shows.
private enum Tokyo {
    static let sensoji = (lat: 35.7148, lon: 139.7967)
    static let skytree = (lat: 35.7101, lon: 139.8107)   // ~1.3 km from Senso-ji
    static let shibuya = (lat: 35.6595, lon: 139.7005)   // ~10 km away
    static let tsukiji = (lat: 35.6654, lon: 139.7707)

    /// 2025-10-06 00:00 JST, fixed so these tests never depend on today's date.
    static let tripStart: Date = {
        var c = DateComponents()
        c.year = 2025; c.month = 10; c.day = 6
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal.date(from: c)!
    }()
}

private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
    Tokyo.tripStart.addingTimeInterval(
        TimeInterval(day * 86_400 + hour * 3_600 + minute * 60))
}

/// A burst of photos around one coordinate, jittered like a real hand-held set.
private func burst(
    _ place: (lat: Double, lon: Double),
    day: Int,
    hour: Int,
    count: Int,
    idPrefix: String,
    accuracy: Double? = 12
) -> [PhotoPoint] {
    (0..<count).map { i in
        // Deterministic sub-100 m jitter; no randomness, so failures reproduce.
        let dLat = Double((i % 5) - 2) * 0.00018
        let dLon = Double((i % 3) - 1) * 0.00021
        return PhotoPoint(
            id: "\(idPrefix)-\(i)",
            timestamp: at(day: day, hour: hour, minute: i * 7),
            latitude: place.lat + dLat,
            longitude: place.lon + dLon,
            horizontalAccuracy: accuracy)
    }
}

// MARK: - Tests

@Suite("Place clustering")
struct PlaceClustererTests {

    let clusterer = PlaceClusterer()

    @Test("A burst of photos in one spot becomes exactly one place")
    func singleBurstIsOnePlace() {
        let points = burst(Tokyo.sensoji, day: 0, hour: 10, count: 6, idPrefix: "sensoji")
        let clusters = clusterer.cluster(points: points)

        #expect(clusters.count == 1)
        #expect(clusters.first?.photoCount == 6)
        #expect(clusters.first?.visitCount == 1)
    }

    @Test("Places kilometres apart stay separate")
    func distantPlacesDoNotMerge() {
        let points =
            burst(Tokyo.sensoji, day: 0, hour: 10, count: 5, idPrefix: "sensoji") +
            burst(Tokyo.shibuya, day: 0, hour: 19, count: 5, idPrefix: "shibuya")

        let clusters = clusterer.cluster(points: points)
        #expect(clusters.count == 2)
    }

    @Test("The same place on two different days is one place with two visits")
    func repeatVisitCollapsesToOnePlace() {
        // This is the behaviour that makes the map accumulate rather than
        // filling up with duplicate rows for a place you love and revisit.
        let points =
            burst(Tokyo.shibuya, day: 0, hour: 19, count: 5, idPrefix: "shibuya-a") +
            burst(Tokyo.shibuya, day: 3, hour: 21, count: 4, idPrefix: "shibuya-b")

        let clusters = clusterer.cluster(points: points)

        #expect(clusters.count == 1, "a revisited place must not become two places")
        #expect(clusters.first?.visitCount == 2, "each stay is its own visit")
        #expect(clusters.first?.photoCount == 9)
    }

    @Test("A long gap at the same spot splits into separate visits")
    func temporalGapSplitsVisits() {
        // Morning and late evening at the same place is two visits, not one
        // eleven-hour stay.
        let points =
            burst(Tokyo.tsukiji, day: 1, hour: 8, count: 4, idPrefix: "tsukiji-am") +
            burst(Tokyo.tsukiji, day: 1, hour: 20, count: 3, idPrefix: "tsukiji-pm")

        let clusters = clusterer.cluster(points: points)
        #expect(clusters.count == 1)
        #expect(clusters.first?.visitCount == 2)
    }

    @Test("Photos with no location are ignored by the located path")
    func unlocatedPhotosAreExcluded() {
        let located = burst(Tokyo.sensoji, day: 0, hour: 10, count: 4, idPrefix: "located")
        let unlocated = (0..<5).map {
            PhotoPoint(id: "nogps-\($0)", timestamp: at(day: 0, hour: 11, minute: $0 * 5))
        }

        let clusters = clusterer.cluster(points: located + unlocated)
        let ids = Set(clusters.flatMap(\.allAssetIdentifiers))

        #expect(clusters.count == 1)
        #expect(ids.allSatisfy { $0.hasPrefix("located") },
                "a photo with no coordinate cannot be attributed to a place")
    }

    @Test("Wildly inaccurate fixes are rejected rather than dragging a cluster")
    func lowAccuracyFixesAreRejected() {
        let good = burst(Tokyo.sensoji, day: 0, hour: 10, count: 5, idPrefix: "good")
        // A cell-tower fix a kilometre wide would otherwise smear the centroid.
        let vague = burst(Tokyo.sensoji, day: 0, hour: 10, count: 3,
                          idPrefix: "vague", accuracy: 3_000)

        let clusters = clusterer.cluster(points: good + vague)
        let ids = Set(clusters.flatMap(\.allAssetIdentifiers))

        #expect(ids.allSatisfy { $0.hasPrefix("good") })
    }

    @Test("An empty roll produces no places and does not crash")
    func emptyInput() {
        #expect(clusterer.cluster(points: []).isEmpty)
    }

    @Test("Clustering is deterministic for the same input")
    func deterministicOutput() {
        // The deck order is what the user sees; it must not reshuffle between
        // runs of the same trip.
        let points =
            burst(Tokyo.sensoji, day: 0, hour: 10, count: 5, idPrefix: "a") +
            burst(Tokyo.shibuya, day: 1, hour: 14, count: 4, idPrefix: "b") +
            burst(Tokyo.tsukiji, day: 2, hour: 9, count: 6, idPrefix: "c")

        let first = clusterer.cluster(points: points).map(\.id)
        let second = clusterer.cluster(points: points).map(\.id)
        #expect(first == second)
    }

    @Test("A realistic five-day trip yields a reviewable number of places")
    func realisticTripStaysWithinDeckSize() {
        // 13 distinct places over 5 days - the same shape as the synthetic
        // library. The deck has to stay small enough that a person will
        // actually finish it.
        var points: [PhotoPoint] = []
        let spots = [Tokyo.sensoji, Tokyo.skytree, Tokyo.tsukiji, Tokyo.shibuya]
        for day in 0..<5 {
            for (i, spot) in spots.enumerated() {
                points += burst(spot, day: day, hour: 9 + i * 3, count: 3,
                                idPrefix: "d\(day)s\(i)")
            }
        }

        let clusters = clusterer.cluster(points: points)

        #expect(clusters.count == spots.count,
                "four distinct locations revisited daily are still four places")
        #expect(clusters.allSatisfy { $0.visitCount == 5 })
        #expect(clusters.count <= clusterer.configuration.maxPlaces)
    }

    @Test("Time-only segmentation gives the no-GPS path something to show")
    func timeOnlySegmentationProducesSessions() {
        // When nothing has coordinates the app must still produce a deck -
        // the question becomes "here is Tuesday 2pm, where was this?" rather
        // than a blank page.
        let points = (0..<12).map {
            PhotoPoint(id: "nogps-\($0)",
                       timestamp: at(day: 0, hour: $0 < 6 ? 10 : 19, minute: ($0 % 6) * 8))
        }

        let sessions = clusterer.segmentByTimeOnly(points: points)
        #expect(sessions.count == 2, "a morning and an evening are two sessions")
    }
}
