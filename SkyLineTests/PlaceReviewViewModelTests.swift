//
//  PlaceReviewViewModelTests.swift
//  SkyLineTests
//
//  The verdict deck is the only real interaction in the app - everything else
//  is either capture (automatic) or display. Its state machine lives apart
//  from the view precisely so it can be tested without a photo library, a
//  simulator or a CloudKit account.
//
//  The behaviours worth guarding are the ones that lose user input: a mis-swipe
//  that cannot be taken back, a deferred place that silently disappears, or a
//  rename that does not stick.
//

import Testing
import Foundation
@testable import SkyLine

// MARK: - Fixtures

private func makeTrip() -> Trip {
    Trip(
        title: "Tokyo",
        destination: "Tokyo",
        startDate: Date(timeIntervalSince1970: 1_759_708_800),
        endDate: Date(timeIntervalSince1970: 1_760_140_800))
}

private func makeDetected(
    _ name: String,
    id: String,
    tripId: String,
    lat: Double? = 35.6595,
    lon: Double? = 139.7005
) -> DetectedPlace {
    DetectedPlace(
        id: id,
        tripId: tripId,
        name: name,
        latitude: lat,
        longitude: lon,
        category: nil,
        visits: [],
        representativeAssetIdentifier: "asset-\(id)",
        allAssetIdentifiers: ["asset-\(id)"],
        source: .photoGPS,
        significance: 10)
}

@MainActor
private func makeModel(placeCount: Int = 3) -> (PlaceReviewViewModel, Trip, [DetectedPlace]) {
    let trip = makeTrip()
    let places = (0..<placeCount).map {
        makeDetected("Place \($0)", id: "p\($0)", tripId: trip.id)
    }
    return (PlaceReviewViewModel(trip: trip, places: places), trip, places)
}

// MARK: - Tests

@MainActor
@Suite("Verdict deck")
struct PlaceReviewViewModelTests {

    @Test("A fresh deck starts on the first place and is not finished")
    func initialState() {
        let (model, _, places) = makeModel()
        #expect(model.isEmpty == false)
        #expect(model.isFinished == false)
        #expect(model.currentPlace?.id == places[0].id)
    }

    @Test("Deciding advances through the deck in order")
    func decidingAdvances() {
        let (model, _, places) = makeModel()

        model.decide(.worthIt)
        #expect(model.currentPlace?.id == places[1].id)

        model.decide(.skip)
        #expect(model.currentPlace?.id == places[2].id)
    }

    @Test("The deck reports finished only after the last card")
    func finishesAtEnd() {
        let (model, _, _) = makeModel(placeCount: 2)
        model.decide(.worthIt)
        #expect(model.isFinished == false)
        model.decide(.fine)
        #expect(model.isFinished == true)
        #expect(model.currentPlace == nil)
    }

    @Test("Undo restores the previous card and clears its decision")
    func undoRestoresPosition() {
        // A mis-swipe is the most likely single failure in this UI, and an
        // unrecoverable one is infuriating.
        let (model, _, places) = makeModel()

        model.decide(.skip)
        #expect(model.currentPlace?.id == places[1].id)

        model.undo()
        #expect(model.currentPlace?.id == places[0].id, "undo must return to the mis-swiped card")
        #expect(model.decisions[places[0].id] == nil, "undo must clear the recorded verdict")
    }

    @Test("Undo at the start of the deck is a no-op, not a crash")
    func undoAtStartIsSafe() {
        let (model, _, places) = makeModel()
        model.undo()
        #expect(model.currentPlace?.id == places[0].id)
        #expect(model.isFinished == false)
    }

    @Test("Undo works after the deck is finished")
    func undoAfterFinishing() {
        // Reaching the summary and realising the last one was wrong is a real
        // sequence; isFinished is derived from the index rather than latched
        // so that it can reverse.
        let (model, _, places) = makeModel(placeCount: 2)
        model.decide(.worthIt)
        model.decide(.skip)
        #expect(model.isFinished == true)

        model.undo()
        #expect(model.isFinished == false)
        #expect(model.currentPlace?.id == places[1].id)
    }

    @Test("Deferring records no verdict but still advances")
    func deferAdvancesWithoutVerdict() {
        // Forcing a verdict onto a place someone barely remembers produces
        // garbage data, so "later" has to be a real answer.
        let (model, _, places) = makeModel()

        model.deferCurrent()
        #expect(model.currentPlace?.id == places[1].id)
        #expect(model.decisions[places[0].id] == .later)
        #expect(model.decisions[places[0].id]?.verdict == nil)
    }

    @Test("Deferred places come back rather than vanishing")
    func deferredPlacesAreRecoverable() {
        let (model, _, places) = makeModel(placeCount: 3)

        model.deferCurrent()          // p0 deferred
        model.decide(.worthIt)        // p1 decided
        model.deferCurrent()          // p2 deferred
        #expect(model.isFinished == true)

        model.reviewDeferred()
        #expect(model.isFinished == false, "a second pass over deferred places must exist")
        let remaining = Set([places[0].id, places[2].id])
        #expect(remaining.contains(model.currentPlace?.id ?? ""))
    }

    @Test("Renaming a place sticks and marks it user-edited")
    func renamePersists() {
        // Reverse geocoding returns a street address often enough that the
        // user is the ground truth here.
        let (model, _, places) = makeModel()

        model.rename("Ichiran Shibuya", forPlaceWithId: places[0].id)

        let renamed = model.place(withId: places[0].id)
        #expect(renamed?.name == "Ichiran Shibuya")
        #expect(renamed?.isNameUserEdited == true)
    }

    @Test("A blank rename is ignored rather than blanking the name")
    func blankRenameIgnored() {
        let (model, _, places) = makeModel()
        let original = model.place(withId: places[0].id)?.name

        model.rename("   ", forPlaceWithId: places[0].id)
        #expect(model.place(withId: places[0].id)?.name == original)
    }

    @Test("An empty deck is finished-safe and reports empty")
    func emptyDeck() {
        let trip = makeTrip()
        let model = PlaceReviewViewModel(trip: trip, places: [])
        #expect(model.isEmpty == true)
        #expect(model.currentPlace == nil)
        // isFinished is false for an empty deck: there is nothing to summarise,
        // and the caller shows the empty state instead.
        #expect(model.isFinished == false)
    }

    @Test("The summary counts every decision exactly once")
    func summaryCounts() {
        let (model, _, _) = makeModel(placeCount: 4)
        model.decide(.worthIt)
        model.decide(.worthIt)
        model.decide(.skip)
        model.deferCurrent()

        let summary = model.summary
        #expect(summary.count(for: .worthIt) == 2)
        #expect(summary.count(for: .skip) == 1)
        #expect(summary.count(for: .fine) == 0)
        #expect(summary.laterCount == 1)
        #expect(summary.decidedCount == 3)
        #expect(summary.total == 4)
    }

    @Test("Peeking past the end of the deck returns nil rather than trapping")
    func peekBeyondEnd() {
        let (model, _, _) = makeModel(placeCount: 2)
        #expect(model.place(atQueueOffset: 0) != nil)
        #expect(model.place(atQueueOffset: 5) == nil)
        #expect(model.place(atQueueOffset: -3) == nil)
    }
}
