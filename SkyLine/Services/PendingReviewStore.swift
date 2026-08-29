//
//  PendingReviewStore.swift
//  SkyLine
//
//  Keeps a library scan's unreviewed episodes so the work survives the session
//  that produced it.
//
//  WHY THIS EXISTS. Scanning a real library is expensive: on a 25,982-photo
//  library the pass ran for minutes, and reverse-geocoding the names dominated
//  it. It produced 120 places across 21 trips. Onboarding then reviewed the
//  newest trip — correctly, because twenty decks back to back is not an
//  onboarding — and discarded the other ~114 places along with every second of
//  the scan that found them. Nothing persisted `LibraryDetectionResult`, and
//  nothing offered to continue, so recovering them meant re-running the whole
//  pass.
//
//  Detection is a discovery step, not a transaction. What it finds is worth
//  keeping even when the user is not ready to judge it yet.
//

import Foundation

// MARK: - Pending Review Store

/// Persists the unreviewed remainder of a library scan.
///
/// Deliberately a FILE rather than UserDefaults: a heavy library produces a few
/// hundred KB of JSON, and UserDefaults is loaded wholesale into memory at
/// launch for every process that touches it.
@MainActor
final class PendingReviewStore: ObservableObject {

    static let shared = PendingReviewStore()

    /// Episodes still awaiting a verdict pass, newest first.
    @Published private(set) var pendingEpisodes: [LibraryEpisode] = []

    /// The stored scan, or nil when there is nothing outstanding.
    private(set) var result: LibraryDetectionResult?

    private let fileName: String

    /// The file `shared` reads at launch.
    ///
    /// Exposed - along with the URL below - so a caller that has to guarantee
    /// this store is empty can reach the file itself. `DebugDataWipe` is the
    /// one that needs it: clearing the live instance without removing the file
    /// leaves a scan's remainder to reload on the next launch, and removing the
    /// file without clearing the instance leaves it publishing places the
    /// account no longer has. Both halves, or neither.
    nonisolated static let defaultFileName = "pending-review.json"

    nonisolated static var defaultFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(defaultFileName)
    }

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    private init() {
        self.fileName = Self.defaultFileName
        load()
    }

    /// Test seam. A store under test needs its own file, or one case's
    /// leftovers decide the next one's result.
    init(fileName: String) {
        self.fileName = fileName
        load()
    }

    // MARK: - Queries

    var hasPending: Bool { !pendingEpisodes.isEmpty }

    /// Places still awaiting a verdict — NOT every place the scan found.
    ///
    /// The two diverge as soon as the user judges anything: they may reach the
    /// same spot through a trip's own detection run, or leave a deck half way
    /// through. Counting the raw total would have the log advertising work that
    /// no longer exists.
    var pendingPlaceCount: Int { pendingPlaceCount(decided: decidedIdentifiers()) }

    func pendingPlaceCount(decided: Set<String>) -> Int {
        guard result != nil else { return 0 }
        return pendingEpisodes.reduce(0) { total, episode in
            total + places(in: episode).count { !decided.contains($0.id) }
        }
    }

    /// The next episode to review, newest first — the one the user remembers best.
    var nextEpisode: LibraryEpisode? { pendingEpisodes.first }

    func places(in episode: LibraryEpisode) -> [DetectedPlace] {
        result?.places(in: episode) ?? []
    }

    /// The places in `episode` that still need a verdict.
    ///
    /// A resume that replays cards the user already ruled on is not a resume.
    /// Detected places are persisted with `externalIdentifier == detected.id`
    /// and cluster ids are content-derived rather than random, so one
    /// identifier lookup is enough to tell what has already been decided.
    func undecidedPlaces(in episode: LibraryEpisode) -> [DetectedPlace] {
        undecidedPlaces(in: episode, decided: decidedIdentifiers())
    }

    /// The set is a parameter so the reconciliation rule can be exercised
    /// without a synced `PlaceStore` behind it.
    func undecidedPlaces(in episode: LibraryEpisode, decided: Set<String>) -> [DetectedPlace] {
        places(in: episode).filter { !decided.contains($0.id) }
    }

    private func decidedIdentifiers() -> Set<String> {
        Set(
            PlaceStore.shared.placeSummaries
                .filter(\.isRated)
                .compactMap { $0.place.externalIdentifier }
        )
    }

    // MARK: - Mutations

    /// Stores a completed scan, minus any episode already reviewed in this flow.
    func store(_ result: LibraryDetectionResult, reviewed: LibraryEpisode? = nil) {
        self.result = result
        pendingEpisodes = result.episodes
            .filter { episode in
                guard episode.id != reviewed?.id else { return false }
                // An episode with nothing in it is not work; dropping it here
                // keeps "3 trips left" from counting empties the deck would skip.
                return !result.places(in: episode).isEmpty
            }
        save()
        print("📋 PendingReview: stored \(pendingEpisodes.count) episodes, \(pendingPlaceCount) places")
    }

    /// Marks one episode reviewed. Called when its deck finishes.
    func markReviewed(_ episode: LibraryEpisode) {
        pendingEpisodes.removeAll { $0.id == episode.id }
        if pendingEpisodes.isEmpty {
            clear()
        } else {
            save()
        }
        print("📋 PendingReview: \(pendingEpisodes.count) episodes still pending")
    }

    /// Drops episodes whose places have all been decided somewhere else — a
    /// trip's own detection run, or a deck the user got through without
    /// reaching the end. Cheap to run and worth running on every appearance:
    /// without it the log offers "1 trip waiting" that opens an empty deck.
    func pruneDecided() { pruneDecided(decided: decidedIdentifiers()) }

    func pruneDecided(decided: Set<String>) {
        guard !pendingEpisodes.isEmpty, let result else { return }
        let before = pendingEpisodes.count
        pendingEpisodes = pendingEpisodes.filter { episode in
            result.places(in: episode).contains { !decided.contains($0.id) }
        }
        guard pendingEpisodes.count != before else { return }
        if pendingEpisodes.isEmpty { clear() } else { save() }
    }

    /// Drops everything. Used when the user declines the remainder outright, and
    /// when a fresh scan supersedes an old one.
    func clear() {
        pendingEpisodes = []
        result = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        print("📋 PendingReview: cleared")
    }

    // MARK: - Persistence

    private func save() {
        guard let fileURL, let result else { return }
        let payload = StoredPayload(result: result, pendingEpisodeIds: pendingEpisodes.map(\.id))
        do {
            let data = try JSONEncoder().encode(payload)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing the remainder is a degraded experience, not a failure: the
            // user can always rescan. Never surface this.
            print("⚠️ PendingReview: could not save - \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(StoredPayload.self, from: data) else {
            return
        }
        result = payload.result
        let ids = Set(payload.pendingEpisodeIds)
        pendingEpisodes = payload.result.episodes.filter { ids.contains($0.id) }
        print("📋 PendingReview: loaded \(pendingEpisodes.count) pending episodes")
    }

    private struct StoredPayload: Codable {
        let result: LibraryDetectionResult
        let pendingEpisodeIds: [String]
    }
}
