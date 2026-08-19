//
//  PlaceReviewViewModel.swift
//  SkyLine
//
//  The deck state machine behind PlaceReviewView — step 3 of the loop.
//
//  Everything the swipe deck knows lives here so the logic is testable without
//  a photo library, a CloudKit account, or a rendered view: hand it a `Trip`
//  and an array of `DetectedPlace` and drive it with `decide` / `undo` /
//  `rename` / `reviewDeferred`.
//
//  Two rules shape the design:
//
//  1. A judgement is never lost. Every `decide` pushes an undo step, and undo
//     works whether or not the CloudKit write has landed yet — a swipe undone
//     mid-flight is cleaned up when the write completes (see `cancelledSteps`).
//  2. "Decide later" is not a verdict. `.later` writes nothing at all. Forcing
//     a verdict onto a place the user barely remembers is how a place log
//     fills with noise, so the deferral is a first-class outcome that simply
//     re-queues.
//

import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Review Decision

/// What the user did with one card.
///
/// `.later` is deliberately outside `Verdict`: "I don't remember this" and
/// "this was not worth it" are different facts, and collapsing them would
/// poison the one thing this product records that a saved-places list cannot.
enum ReviewDecision: Equatable, Hashable {
    case verdict(Verdict)
    case later

    var verdict: Verdict? {
        if case .verdict(let value) = self { return value }
        return nil
    }

    var isLater: Bool { self == .later }

    /// Past-tense confirmation used by the undo toast.
    var confirmationText: String {
        switch self {
        case .verdict(let value): return "Marked \(value.displayName)"
        case .later: return "Left for later"
        }
    }

    var systemImage: String {
        switch self {
        case .verdict(let value): return value.systemImage
        case .later: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - View Model

@MainActor
final class PlaceReviewViewModel: ObservableObject {

    // MARK: - Types

    /// One entry on the undo stack.
    ///
    /// `visitIds` / `storedPlaceId` are filled in *after* the write lands, which
    /// is why undo also consults `cancelledSteps` — the user can undo faster
    /// than CloudKit can answer.
    struct Step: Identifiable, Equatable {
        let id: UUID
        /// `DetectedPlace.id`, not the stored `Place.id`.
        let detectedPlaceId: String
        let queueIndex: Int
        let decision: ReviewDecision
        var visitIds: [String] = []
        var storedPlaceId: String?
        /// True when this swipe is what created the `Place` record, so undo
        /// knows it is safe to take the place back out again.
        var didCreatePlace: Bool = false
    }

    /// What the user just logged, for the end-of-deck screen.
    struct Summary: Equatable {
        struct Highlight: Identifiable, Equatable {
            let id: String
            let name: String
            let assetIdentifier: String?
            let verdict: Verdict
        }

        var counts: [Verdict: Int] = [:]
        var laterCount: Int = 0
        var total: Int = 0
        /// Places whose verdict is recorded locally but that have no coordinate
        /// to pin, so they cannot land on the map yet.
        var needsLocationCount: Int = 0
        var highlights: [Highlight] = []

        var decidedCount: Int { counts.values.reduce(0, +) }

        func count(for verdict: Verdict) -> Int { counts[verdict] ?? 0 }
    }

    // MARK: - Published State

    /// The working set. Renames are applied here, so this is the source of
    /// truth for names — not the array handed to `init`.
    @Published private(set) var places: [DetectedPlace]

    /// `DetectedPlace.id`s in the current pass. A second pass over the deferred
    /// places replaces this rather than mutating `places`.
    @Published private(set) var queue: [String]

    @Published private(set) var index: Int = 0

    /// Keyed by `DetectedPlace.id`. Survives a re-queue.
    @Published private(set) var decisions: [String: ReviewDecision] = [:]

    /// The undo stack, oldest first.
    @Published private(set) var history: [Step] = []

    /// The step the undo affordance is currently offering to reverse.
    @Published private(set) var lastStep: Step?

    @Published private(set) var isWriting: Bool = false

    /// Places recorded locally that had no coordinate to pin.
    @Published private(set) var needsLocation: Set<String> = []

    @Published var errorMessage: String?

    // MARK: - Dependencies

    let trip: Trip
    private let store: PlaceStore

    /// Steps undone before their write finished. The write cleans up after
    /// itself when it sees its own id in here.
    private var cancelledSteps: Set<UUID> = []

    // MARK: - Init

    /// `store` is injectable so the deck logic can be driven in a test without
    /// a CloudKit account. It defaults to the shared store, resolved inside the
    /// isolated body rather than in a (nonisolated) default argument.
    init(trip: Trip, places: [DetectedPlace], store: PlaceStore? = nil) {
        self.trip = trip
        self.places = places
        self.queue = places.map(\.id)
        self.store = store ?? PlaceStore.shared
    }

    // MARK: - Deck Position

    var isEmpty: Bool { queue.isEmpty }

    /// True once every card in this pass has been answered. Reverses on undo,
    /// because it is derived from the index rather than latched.
    var isFinished: Bool { !queue.isEmpty && index >= queue.count }

    var currentPlace: DetectedPlace? { place(atQueueOffset: 0) }

    /// The card `offset` positions further down the deck, for the peek behind
    /// the top card.
    func place(atQueueOffset offset: Int) -> DetectedPlace? {
        let target = index + offset
        guard target >= 0, target < queue.count else { return nil }
        return place(withId: queue[target])
    }

    func place(withId id: String) -> DetectedPlace? {
        places.first { $0.id == id }
    }

    /// 1-based, for "4 of 13".
    var position: Int { min(index + 1, max(queue.count, 1)) }

    var total: Int { queue.count }

    var progressText: String { "\(position) of \(total)" }

    var canUndo: Bool { !history.isEmpty }

    var deferredPlaces: [DetectedPlace] {
        places.filter { decisions[$0.id]?.isLater == true }
    }

    var deferredCount: Int { deferredPlaces.count }

    // MARK: - Deciding

    /// Records a decision for the top card and advances.
    ///
    /// The local state moves immediately and synchronously — the write is fired
    /// afterwards and never gates the UI, because a slow CloudKit round trip
    /// must not stall a deck the user is flicking through.
    func decide(_ decision: ReviewDecision) {
        guard let detected = currentPlace else { return }

        let step = Step(
            id: UUID(),
            detectedPlaceId: detected.id,
            queueIndex: index,
            decision: decision
        )

        decisions[detected.id] = decision
        history.append(step)
        lastStep = step
        index += 1

        print("🎯 PlaceReview: \(detected.name) → \(decision.confirmationText)")

        // `.later` is a deliberate non-write. Nothing to persist, nothing to
        // clean up, and the place stays available for a second pass.
        guard case .verdict(let verdict) = decision else { return }

        Task { await self.persist(detected, verdict: verdict, stepId: step.id) }
    }

    func decide(_ verdict: Verdict) {
        decide(.verdict(verdict))
    }

    /// "Decide later" — skips the judgement, not the place.
    func deferCurrent() {
        decide(.later)
    }

    // MARK: - Undo

    /// Reverses the most recent decision and puts its card back on top.
    func undo() {
        guard let step = history.popLast() else { return }

        decisions.removeValue(forKey: step.detectedPlaceId)
        needsLocation.remove(step.detectedPlaceId)
        index = min(step.queueIndex, max(queue.count - 1, 0))
        if lastStep?.id == step.id { lastStep = nil }

        // Flag first, then roll back. If the write is still in flight it will
        // see the flag and undo itself; if it already landed, `step` carries
        // the ids and the rollback below removes them.
        cancelledSteps.insert(step.id)

        print("↩️ PlaceReview: undid \(step.decision.confirmationText)")

        Task { await self.rollback(step) }
    }

    func clearLastStep() {
        lastStep = nil
    }

    // MARK: - Renaming

    /// The user is ground truth for a name.
    ///
    /// Reverse geocoding regularly hands back a street address where the user
    /// remembers a restaurant, so this both rewrites the deck entry and, when
    /// the place is already in the log, pushes the new name to the stored
    /// record — `Place.merged` keeps the *stored* name on upsert, so a rename
    /// after the fact has to be an explicit update.
    func rename(_ rawName: String, forPlaceWithId id: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let slot = places.firstIndex(where: { $0.id == id }),
              places[slot].name != trimmed else { return }

        places[slot] = places[slot].with(name: trimmed, isNameUserEdited: true)
        let updated = places[slot]

        print("✏️ PlaceReview: renamed \(id) → \(trimmed)")

        Task { await self.pushRename(updated) }
    }

    // MARK: - Second Pass

    /// Re-queues everything the user left for later. Their deferrals are
    /// cleared so the second pass is a genuine re-ask, not a replay.
    func reviewDeferred() {
        let ids = places.filter { decisions[$0.id]?.isLater == true }.map(\.id)
        guard !ids.isEmpty else { return }

        for id in ids { decisions.removeValue(forKey: id) }
        queue = ids
        index = 0
        history.removeAll()
        lastStep = nil

        print("🔁 PlaceReview: second pass over \(ids.count) deferred places")
    }

    // MARK: - Summary

    var summary: Summary {
        var counts: [Verdict: Int] = [:]
        var laterCount = 0
        var highlights: [Summary.Highlight] = []

        for detected in places {
            switch decisions[detected.id] {
            case .verdict(let verdict):
                counts[verdict, default: 0] += 1
                highlights.append(
                    Summary.Highlight(
                        id: detected.id,
                        name: detected.name,
                        assetIdentifier: detected.representativeAssetIdentifier,
                        verdict: verdict
                    )
                )
            case .later:
                laterCount += 1
            case nil:
                break
            }
        }

        highlights.sort { lhs, rhs in
            if lhs.verdict.sortRank != rhs.verdict.sortRank {
                return lhs.verdict.sortRank < rhs.verdict.sortRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return Summary(
            counts: counts,
            laterCount: laterCount,
            total: places.count,
            needsLocationCount: needsLocation.count,
            highlights: highlights
        )
    }

    // MARK: - Card Copy

    /// "Tue 4 Mar · 2 visits · 12 photos", in the destination's time zone —
    /// the photos were taken on local time, not the reader's.
    func subtitle(for detected: DetectedPlace) -> String {
        detected.subtitle(in: trip.destinationTimeZone)
    }

    /// "about 2h 10m there". Nil below five minutes, where a dwell derived from
    /// photo timestamps says nothing the photo count does not.
    func dwellText(for detected: DetectedPlace) -> String? {
        let total = detected.totalDwell
        guard total >= 300 else { return nil }

        let minutes = Int((total / 60).rounded())
        if minutes < 60 { return "\(minutes)m there" }

        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h there" : "\(hours)h \(remainder)m there"
    }

    /// Every place needs a coordinate before it can be pinned. Time-only
    /// clustering produces places without one, and the trip is the fallback.
    func canBePinned(_ detected: DetectedPlace) -> Bool {
        candidatePlace(for: detected) != nil
    }

    // MARK: - Image Prefetch

    /// Keeps a window of full-width images warm around the top card.
    /// Called from the view, never from `decide`, so pure deck-logic tests
    /// never touch PhotoKit.
    func prefetchImages() {
        let identifiers = queue.compactMap { place(withId: $0)?.representativeAssetIdentifier }
        guard !identifiers.isEmpty else { return }
        PhotoAssetImageLoader.shared.updateDeckWindow(
            identifiers: identifiers,
            currentIndex: min(index, identifiers.count - 1)
        )
    }

    // MARK: - Persistence

    private struct PersistableVisit {
        let date: Date
        let assetIdentifiers: [String]
    }

    private func persist(_ detected: DetectedPlace, verdict: Verdict, stepId: UUID) async {
        guard let candidate = candidatePlace(for: detected) else {
            // The verdict is real, we just have nowhere to pin it. Keep it in
            // the session and tell the truth in the summary.
            needsLocation.insert(detected.id)
            print("⚠️ PlaceReview: \(detected.name) has no coordinate — verdict held locally")
            return
        }

        isWriting = true
        defer { isWriting = false }

        let existingBefore = store.existingPlace(matching: candidate)
        let didCreatePlace = existingBefore == nil

        // A rename made before the swipe has to be forced onto an existing
        // record; `upsertPlace` merges and keeps the stored name.
        if detected.isNameUserEdited, let existing = existingBefore, existing.name != candidate.name {
            _ = await store.updatePlace(renamed(existing, to: candidate.name))
        }

        var visitIds: [String] = []
        var storedPlaceId: String?
        var failure: PlaceStoreError?

        for (offset, session) in persistableVisits(for: detected).enumerated() {
            // Deterministic ids: re-reviewing a trip updates the same visits
            // instead of stacking duplicates on the same place.
            let visitId = PlaceImportService.sanitizedRecordName("visit-\(detected.id)-\(offset)")

            let result = await store.recordVisit(
                to: candidate,
                id: visitId,
                date: session.date,
                verdict: verdict,
                note: detected.note,
                photoLocalIdentifiers: session.assetIdentifiers,
                tripId: trip.id,
                source: .photoCluster
            )

            switch result {
            case .success(let visit):
                visitIds.append(visit.id)
                storedPlaceId = visit.placeId
            case .failure(let error):
                failure = error
            }
        }

        // Undone while the write was in flight — take it straight back out.
        if cancelledSteps.contains(stepId) {
            cancelledSteps.remove(stepId)
            await removeRecords(visitIds: visitIds, placeId: storedPlaceId, didCreatePlace: didCreatePlace)
            return
        }

        if let slot = history.firstIndex(where: { $0.id == stepId }) {
            history[slot].visitIds = visitIds
            history[slot].storedPlaceId = storedPlaceId
            history[slot].didCreatePlace = didCreatePlace
        }

        if let failure {
            // The swipe is not lost — PlaceStore keeps a local copy — so this
            // is a note, not a modal.
            errorMessage = failure.errorDescription ?? "Could not sync \(detected.name)"
            print("❌ PlaceReview: write failed for \(detected.name): \(failure)")
        } else {
            print("✅ PlaceReview: saved \(detected.name) as \(verdict.rawValue) (\(visitIds.count) visits)")
        }
    }

    private func rollback(_ step: Step) async {
        guard !step.visitIds.isEmpty || step.storedPlaceId != nil else {
            // Nothing written yet. `cancelledSteps` still holds the flag, and
            // the in-flight write will clean up after itself.
            return
        }

        cancelledSteps.remove(step.id)
        await removeRecords(
            visitIds: step.visitIds,
            placeId: step.storedPlaceId,
            didCreatePlace: step.didCreatePlace
        )
    }

    private func removeRecords(visitIds: [String], placeId: String?, didCreatePlace: Bool) async {
        for visitId in visitIds {
            _ = await store.deleteVisit(visitId)
        }

        // Only reclaim the place if this session created it and nothing else
        // is hanging off it — an older visit from a previous trip must survive.
        guard didCreatePlace, let placeId, store.visits(for: placeId).isEmpty else { return }
        _ = await store.deletePlace(placeId)
    }

    private func pushRename(_ detected: DetectedPlace) async {
        guard decisions[detected.id]?.verdict != nil,
              let candidate = candidatePlace(for: detected),
              let existing = store.existingPlace(matching: candidate),
              existing.name != detected.name else { return }

        _ = await store.updatePlace(renamed(existing, to: detected.name))
    }

    // MARK: - Model Mapping

    private func candidatePlace(for detected: DetectedPlace) -> Place? {
        // Time-only clusters carry no coordinate; the trip is the only honest
        // fallback. Null Island is not a place anyone went.
        guard let coordinate = detected.coordinate ?? trip.coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return nil }

        return Place(
            id: PlaceImportService.sanitizedRecordName("place-\(detected.id)"),
            name: detected.name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: PlaceCategory(mapKitCategory: detected.category.map(MKPointOfInterestCategory.init(rawValue:))),
            city: trip.destination,
            state: trip.state,
            country: trip.country,
            externalIdentifier: detected.id,
            externalIdentifierSource: .photoCluster,
            timeZoneIdentifier: trip.timeZoneIdentifier
        )
    }

    /// One `Visit` per detected session, so "you went back twice" survives.
    private func persistableVisits(for detected: DetectedPlace) -> [PersistableVisit] {
        guard !detected.visits.isEmpty else {
            return [
                PersistableVisit(
                    date: detected.firstVisitAt ?? trip.startDate,
                    assetIdentifiers: detected.allAssetIdentifiers
                )
            ]
        }

        return detected.visits.map {
            PersistableVisit(date: $0.startDate, assetIdentifiers: $0.assetIdentifiers)
        }
    }

    private func renamed(_ place: Place, to name: String) -> Place {
        Place(
            id: place.id,
            name: name,
            latitude: place.latitude,
            longitude: place.longitude,
            category: place.category,
            address: place.address,
            city: place.city,
            state: place.state,
            country: place.country,
            countryCode: place.countryCode,
            externalIdentifier: place.externalIdentifier,
            externalIdentifierSource: place.externalIdentifierSource,
            timeZoneIdentifier: place.timeZoneIdentifier,
            createdAt: place.createdAt,
            updatedAt: Date()
        )
    }
}
