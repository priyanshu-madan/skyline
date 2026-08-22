//
//  PendingReviewStoreTests.swift
//  SkyLineTests
//
//  A library scan is a minutes-long pass that routinely finds more than anyone
//  will judge in one sitting — 120 places across 21 trips on the library this
//  was built against. Onboarding reviewed the newest trip and dropped the rest
//  on the floor, so the only way back to them was to run the whole pass again.
//
//  These tests pin the three properties the fix has to hold: the remainder
//  survives the process that found it, an episode already reviewed is never
//  offered twice, and a verdict recorded somewhere else retires the work it
//  covers.
//

import Testing
import Foundation
@testable import SkyLine

@MainActor
@Suite("Pending review store")
struct PendingReviewStoreTests {

    // MARK: - Fixtures

    private static let day: TimeInterval = 86_400

    private func episode(_ id: String, title: String, dayOffset: Double) -> LibraryEpisode {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + dayOffset * Self.day)
        return LibraryEpisode(
            id: id,
            title: title,
            startDate: start,
            endDate: start + 3 * Self.day,
            latitude: 35.68,
            longitude: 139.76,
            dayCount: 3,
            photoCount: 90,
            placeCount: 2
        )
    }

    private func place(_ id: String, in episodeId: String) -> DetectedPlace {
        DetectedPlace(
            id: id,
            tripId: episodeId,
            name: id,
            latitude: 35.68,
            longitude: 139.76,
            source: .photoGPS
        )
    }

    /// Two episodes, two places each.
    private func result() -> LibraryDetectionResult {
        let a = episode("ep-a", title: "Kyoto", dayOffset: 0)
        let b = episode("ep-b", title: "Lisbon", dayOffset: 30)
        return LibraryDetectionResult(
            outcome: .places,
            episodes: [a, b],
            places: [
                place("a1", in: "ep-a"), place("a2", in: "ep-a"),
                place("b1", in: "ep-b"), place("b2", in: "ep-b")
            ],
            diagnostics: LibraryDetectionDiagnostics()
        )
    }

    /// Every case gets its own file, or one case's leftovers decide the next.
    private func makeStore(_ name: String) -> PendingReviewStore {
        let store = PendingReviewStore(fileName: "test-\(name).json")
        store.clear()
        return store
    }

    // MARK: - Storing

    @Test("The episode being reviewed now is not also queued for later")
    func reviewedEpisodeIsExcluded() {
        let store = makeStore("excluded")
        let result = self.result()

        store.store(result, reviewed: result.episodes[0])

        #expect(store.pendingEpisodes.map(\.id) == ["ep-b"])
        #expect(store.hasPending)
    }

    @Test("An episode with no places is not offered as work")
    func emptyEpisodesAreDropped() {
        let store = makeStore("empty-episodes")
        let withEmpty = LibraryDetectionResult(
            outcome: .places,
            episodes: [
                episode("ep-a", title: "Kyoto", dayOffset: 0),
                episode("ep-empty", title: "Nowhere", dayOffset: 10)
            ],
            places: [place("a1", in: "ep-a")],
            diagnostics: LibraryDetectionDiagnostics()
        )

        store.store(withEmpty)

        // "2 trips waiting" that opens an empty deck is the bug.
        #expect(store.pendingEpisodes.map(\.id) == ["ep-a"])
    }

    // MARK: - Persistence

    @Test("The remainder survives the process that found it")
    func remainderIsPersisted() {
        let name = "persisted"
        let original = makeStore(name)
        original.store(result(), reviewed: result().episodes[0])

        // A second instance reads only what was written to disk — the whole
        // point, since the scan that produced it is minutes the user does not
        // get back.
        let reloaded = PendingReviewStore(fileName: "test-\(name).json")

        #expect(reloaded.pendingEpisodes.map(\.id) == ["ep-b"])
        #expect(reloaded.places(in: reloaded.pendingEpisodes[0]).map(\.id) == ["b1", "b2"])

        reloaded.clear()
    }

    @Test("Clearing removes the file, not just the memory")
    func clearingIsPersisted() {
        let name = "cleared"
        let original = makeStore(name)
        original.store(result())
        original.clear()

        let reloaded = PendingReviewStore(fileName: "test-\(name).json")
        #expect(reloaded.hasPending == false)
        #expect(reloaded.pendingPlaceCount(decided: []) == 0)
    }

    @Test("The last episode reviewed clears the queue outright")
    func lastReviewClears() {
        let name = "last-review"
        let store = makeStore(name)
        let result = self.result()
        store.store(result)

        store.markReviewed(result.episodes[0])
        #expect(store.pendingEpisodes.map(\.id) == ["ep-b"])

        store.markReviewed(result.episodes[1])
        #expect(store.hasPending == false)

        let reloaded = PendingReviewStore(fileName: "test-\(name).json")
        #expect(reloaded.hasPending == false)
    }

    // MARK: - Reconciliation

    @Test("Places already judged elsewhere are not dealt again")
    func decidedPlacesAreNotReplayed() {
        let store = makeStore("decided")
        let result = self.result()
        store.store(result)

        // The user reached "b1" through the trip's own detection run.
        let undecided = store.undecidedPlaces(in: result.episodes[1], decided: ["b1"])

        #expect(undecided.map(\.id) == ["b2"])
    }

    @Test("A fully decided episode stops being offered")
    func fullyDecidedEpisodeIsPruned() {
        let store = makeStore("pruned")
        let result = self.result()
        store.store(result)
        #expect(store.pendingEpisodes.count == 2)

        store.pruneDecided(decided: ["a1", "a2"])

        // Offering "Kyoto — 0 places" would open an empty deck.
        #expect(store.pendingEpisodes.map(\.id) == ["ep-b"])
    }

    @Test("Deciding everything empties the queue")
    func pruningEverythingClears() {
        let name = "pruned-all"
        let store = makeStore(name)
        store.store(result())

        store.pruneDecided(decided: ["a1", "a2", "b1", "b2"])

        #expect(store.hasPending == false)
        let reloaded = PendingReviewStore(fileName: "test-\(name).json")
        #expect(reloaded.hasPending == false)
    }

    @Test("Pruning nothing leaves the queue and its file alone")
    func pruningNothingIsInert() {
        let store = makeStore("prune-inert")
        store.store(result())

        store.pruneDecided(decided: ["unrelated-id"])

        #expect(store.pendingEpisodes.count == 2)
        #expect(store.pendingPlaceCount(decided: []) == 4)
    }

    @Test("The count advertised is the work remaining, not the work found")
    func countReflectsRemainingWork() {
        let store = makeStore("count")
        let result = self.result()
        store.store(result, reviewed: result.episodes[0])

        // ep-b holds two places; one is already decided.
        #expect(store.pendingPlaceCount(decided: []) == 2)
        #expect(store.pendingPlaceCount(decided: ["b1"]) == 1)
        #expect(store.pendingPlaceCount(decided: ["b1", "b2"]) == 0)
    }

    @Test("Newest first — the trip the user remembers best is offered first")
    func nextEpisodeIsTheNewest() {
        let store = makeStore("ordering")
        store.store(result())

        // `episodes` arrives newest-first from the service and the store must
        // not reorder it; asking someone to judge a trip from four years ago
        // before last month's is the wrong first question.
        #expect(store.nextEpisode?.id == "ep-a")
    }
}
