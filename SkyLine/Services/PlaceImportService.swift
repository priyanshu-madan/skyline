//
//  PlaceImportService.swift
//  SkyLine
//
//  One-way, additive migration of Trip / TripEntry / Flight into Place + Visit
//

import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - Import Summary
struct PlaceImportSummary: Codable, Hashable {
    var tripsScanned: Int = 0
    var tripEntriesScanned: Int = 0
    var flightsScanned: Int = 0
    var placesCreated: Int = 0
    var placesMatchedExisting: Int = 0
    var visitsCreated: Int = 0
    var skippedNoCoordinates: Int = 0
    var failures: Int = 0

    static let empty = PlaceImportSummary()

    var didImportAnything: Bool { visitsCreated > 0 || placesCreated > 0 }

    var logLine: String {
        "trips: \(tripsScanned), entries: \(tripEntriesScanned), flights: \(flightsScanned) -> " +
        "places: \(placesCreated) new / \(placesMatchedExisting) matched, visits: \(visitsCreated), " +
        "skipped: \(skippedNoCoordinates), failures: \(failures)"
    }
}

// MARK: - Place Import Service
/// Reads the user's existing records and projects them into the new model.
///
/// ADDITIVE ONLY. Nothing here deletes, rewrites, or migrates a Flight, Trip or
/// TripEntry record - the old data keeps working exactly as it does today.
///
/// Idempotent: every derived record gets a deterministic id ("visit-entry-<id>"),
/// so re-running overwrites the same rows instead of duplicating them. The
/// version gate below is belt-and-braces on top of that.
@MainActor
class PlaceImportService: ObservableObject {
    static let shared = PlaceImportService()

    @Published var isImporting = false
    @Published var lastSummary: PlaceImportSummary?
    @Published var error: String?

    private let placeStore = PlaceStore.shared
    private let tripStore = TripStore.shared

    private let importVersionKey = "PlaceImportVersion"
    /// Bump to re-run the import after changing the mapping rules.
    /// Bump when the import produces materially different rows, so existing
    /// installs re-derive rather than keeping stale data.
    ///   1: initial import
    ///   2: country / countryCode resolved from coordinates via CountryLocator
    ///   3: repair pass - backfills country on places imported before v2
    ///   4: re-run after fixing the race that imported flights before they loaded
    ///   5: treat a blank trip.country as absent so the resolved one is used
    private let currentImportVersion = 5

    private init() {}

    // MARK: - Entry Points

    /// Runs once per import version. `flights` comes from the caller because
    /// `FlightStore` is a `@StateObject` in `SkyLineApp`, not a singleton -
    /// pass `flightStore.flights`.
    @discardableResult
    func runIfNeeded(flights: [Flight]) async -> Result<PlaceImportSummary, PlaceStoreError> {
        let completedVersion = UserDefaults.standard.integer(forKey: importVersionKey)
        guard completedVersion < currentImportVersion else {
            print("🔄 PlaceImport: Already ran (version \(completedVersion)) - skipping")
            return .success(.empty)
        }

        let result = await runImport(flights: flights)
        if case .success = result {
            UserDefaults.standard.set(currentImportVersion, forKey: importVersionKey)
        }
        return result
    }

    /// Force a re-run (Settings / debug menu). Safe: deterministic ids mean this
    /// updates existing derived rows rather than duplicating them.
    @discardableResult
    func runImport(flights: [Flight]) async -> Result<PlaceImportSummary, PlaceStoreError> {
        guard !isImporting else {
            print("⚠️ PlaceImport: Already running")
            return .success(.empty)
        }

        isImporting = true
        error = nil
        var summary = PlaceImportSummary()

        print("🔄 PlaceImport: Starting import...")

        // Make sure the legacy stores actually have data before reading them.
        if tripStore.trips.isEmpty {
            let _ = await tripStore.fetchTrips()
        }

        await importTripEntries(into: &summary)
        await importTrips(into: &summary)
        await importFlights(flights, into: &summary)

        lastSummary = summary
        isImporting = false

        print("✅ PlaceImport: Finished - \(summary.logLine)")
        return .success(summary)
    }

    // MARK: - TripEntry -> Place + Visit

    /// Journal entries are the richest source: they already carry a coordinate,
    /// a place name and a note.
    private func importTripEntries(into summary: inout PlaceImportSummary) async {
        for trip in tripStore.trips {
            var entries = tripStore.getEntries(for: trip.id)
            if entries.isEmpty {
                let _ = await tripStore.fetchEntriesForTrip(trip.id)
                entries = tripStore.getEntries(for: trip.id)
            }

            for entry in entries {
                summary.tripEntriesScanned += 1

                // AI previews the user never accepted are not visits.
                guard !entry.isPreview else { continue }
                // Flight entries are covered by the Flight import below.
                guard entry.entryType != .flight else { continue }

                guard let latitude = entry.latitude, let longitude = entry.longitude else {
                    summary.skippedNoCoordinates += 1
                    continue
                }

                let rawName = (entry.locationName?.isEmpty == false) ? entry.locationName! : entry.title
                let resolved = CountryLocator.shared.country(latitude: latitude, longitude: longitude)
                let candidate = Place(
                    id: "place-entry-\(PlaceImportService.sanitizedRecordName(entry.id))",
                    name: rawName,
                    latitude: latitude,
                    longitude: longitude,
                    category: PlaceCategory(tripEntryType: entry.entryType),
                    address: nil,
                    city: entry.regionName ?? trip.destination,
                    state: trip.state,
                    country: trip.country?.nilIfBlank ?? resolved?.name,
                    countryCode: resolved?.code,
                    // No stable external id exists for legacy rows; dedup falls
                    // back to name + proximity inside PlaceStore.
                    externalIdentifier: nil,
                    externalIdentifierSource: .none,
                    timeZoneIdentifier: trip.timeZoneIdentifier
                )

                let note = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
                await record(
                    candidate: candidate,
                    visitId: "visit-entry-\(PlaceImportService.sanitizedRecordName(entry.id))",
                    date: entry.timestamp,
                    note: note.isEmpty ? nil : note,
                    tripId: entry.tripId,
                    source: .importedTripEntry,
                    into: &summary
                )
            }
        }
    }

    // MARK: - Trip -> Place + Visit

    /// A destination is a coarse place ("Tokyo"), which is still worth a dot on
    /// the map for trips that never got journal entries.
    private func importTrips(into summary: inout PlaceImportSummary) async {
        for trip in tripStore.trips {
            summary.tripsScanned += 1

            // A trip that has not happened yet is not a visit.
            guard !trip.isUpcoming else { continue }

            guard let latitude = trip.latitude, let longitude = trip.longitude else {
                summary.skippedNoCoordinates += 1
                continue
            }

            let tripKey = PlaceImportService.sanitizedRecordName(trip.id)
            let resolved = CountryLocator.shared.country(latitude: latitude, longitude: longitude)
            let candidate = Place(
                id: "place-trip-\(tripKey)",
                name: trip.destination,
                latitude: latitude,
                longitude: longitude,
                category: .city,
                address: nil,
                city: trip.destination,
                state: trip.state,
                country: trip.country?.nilIfBlank ?? resolved?.name,
                countryCode: resolved?.code,
                externalIdentifier: "skyline-trip:\(trip.id)",
                externalIdentifierSource: .skylineTrip,
                timeZoneIdentifier: trip.timeZoneIdentifier
            )

            let note = trip.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            await record(
                candidate: candidate,
                visitId: "visit-trip-\(tripKey)",
                date: trip.startDate,
                note: (note?.isEmpty ?? true) ? nil : note,
                tripId: trip.id,
                source: .importedTrip,
                into: &summary
            )
        }
    }

    // MARK: - Flight -> Place + Visit

    /// Airports the user actually stood in. Both endpoints become places; the
    /// IATA code is a genuinely stable external identifier, so 31 flights
    /// collapse into a small set of airports.
    private func importFlights(_ flights: [Flight], into summary: inout PlaceImportSummary) async {
        for flight in flights {
            summary.flightsScanned += 1

            // Schema-init leftovers, seen in FlightStore.performInitialSync.
            guard flight.flightNumber != "SCHEMA_INIT" else { continue }

            let flightKey = PlaceImportService.sanitizedRecordName(flight.id)

            await importAirport(
                flight.departure,
                visitId: "visit-flight-\(flightKey)-dep",
                date: flight.departureDate ?? flight.date,
                into: &summary
            )

            await importAirport(
                flight.arrival,
                visitId: "visit-flight-\(flightKey)-arr",
                date: flight.arrivalDate ?? flight.date,
                into: &summary
            )
        }
    }

    private func importAirport(
        _ airport: Airport,
        visitId: String,
        date: Date,
        into summary: inout PlaceImportSummary
    ) async {
        let code = airport.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            summary.skippedNoCoordinates += 1
            return
        }

        // The Flight record's own coordinates win; the local airport table is
        // the fallback. No network lookup here - the import must work offline.
        var coordinate = airport.coordinate
        if coordinate == nil {
            coordinate = AirportService.shared.getCoordinates(for: code)
        }

        guard let coordinate = coordinate else {
            summary.skippedNoCoordinates += 1
            print("⚠️ PlaceImport: No coordinates for airport \(code) - skipped")
            return
        }

        let name: String
        if !airport.airport.isEmpty {
            name = airport.airport
        } else if let known = AirportService.shared.getName(for: code) {
            name = known
        } else {
            name = "\(code) Airport"
        }

        let resolvedCountry = CountryLocator.shared.country(at: coordinate)
        let candidate = Place(
            id: "place-iata-\(code)",
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: .airport,
            address: nil,
            city: airport.city.isEmpty ? nil : airport.city,
            state: nil,
            country: resolvedCountry?.name,
            countryCode: resolvedCountry?.code,
            externalIdentifier: "iata:\(code)",
            externalIdentifierSource: .airportCode,
            timeZoneIdentifier: AirportService.shared.getTimezone(for: code)?.identifier
        )

        await record(
            candidate: candidate,
            visitId: visitId,
            date: date,
            note: nil,
            tripId: nil,
            source: .importedFlight,
            into: &summary
        )
    }

    // MARK: - Shared Write Path

    /// Upserts the place, then writes a visit with a deterministic id.
    /// `verdict` is always nil: an import must never invent an opinion.
    private func record(
        candidate: Place,
        visitId: String,
        date: Date,
        note: String?,
        tripId: String?,
        source: VisitSource,
        into summary: inout PlaceImportSummary
    ) async {
        let existing = placeStore.existingPlace(matching: candidate)

        let result = await placeStore.recordVisit(
            to: candidate,
            id: visitId,
            date: date,
            verdict: nil,
            note: note,
            photoLocalIdentifiers: [],
            tripId: tripId,
            source: source
        )

        switch result {
        case .success:
            if existing == nil {
                summary.placesCreated += 1
            } else {
                summary.placesMatchedExisting += 1
            }
            summary.visitsCreated += 1
        case .failure(let storeError):
            summary.failures += 1
            error = storeError.errorDescription
            print("❌ PlaceImport: Failed to import \(candidate.name): \(storeError)")
        }
    }

    // MARK: - Helpers

    /// CloudKit record names allow ASCII letters, digits, `-`, `_` and `.`, and
    /// must not start with `_`. Legacy flight ids are not always UUIDs.
    static func sanitizedRecordName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scrubbed = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let trimmed = scrubbed.hasPrefix("_") ? String(scrubbed.dropFirst()) : scrubbed
        return trimmed.isEmpty ? UUID().uuidString : String(trimmed.prefix(200))
    }
}
