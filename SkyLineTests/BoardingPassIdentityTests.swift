//
//  BoardingPassIdentityTests.swift
//  SkyLineTests
//
//  Two bugs that corrupted a flight quietly, in the one flow that works.
//
//  A scanned pass prints its time as a bare "21:30". That was stamped onto
//  `Date()`, so a November flight scanned in August was saved at the right time
//  on the day it was scanned. Nothing failed; the flight was simply wrong.
//
//  And `BoardingPassData.id` was `UUID()`, minted per instance — so scanning the
//  same pass twice produced two flights instead of one updated flight.
//

import Testing
import Foundation
@testable import SkyLine

@Suite("Boarding pass identity and times")
struct BoardingPassIdentityTests {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func parts(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - Times land on the flight's own day

    @Test("A bare clock time lands on the flight's date, not today")
    func timeAnchorsToFlightDate() throws {
        let flightDay = date(2026, 11, 26)
        let combined = try #require(CloudKitService.combining(time: "21:30", withDayOf: flightDay))
        let got = parts(combined)

        #expect(got.year == 2026)
        #expect(got.month == 11)
        #expect(got.day == 26)
        #expect(got.hour == 21)
        #expect(got.minute == 30)
    }

    @Test("Common printed time formats all parse", arguments: [
        ("19:45", 19, 45),
        ("9:05", 9, 5),
        ("07:05 AM", 7, 5),
        ("7:05 PM", 19, 5),
        ("22:56:00", 22, 56)
    ])
    func timeFormats(input: String, hour: Int, minute: Int) throws {
        let combined = try #require(
            CloudKitService.combining(time: input, withDayOf: date(2026, 3, 4)))
        let got = parts(combined)
        #expect(got.hour == hour)
        #expect(got.minute == minute)
        #expect(got.day == 4, "the day must come from the flight, never from the clock string")
    }

    @Test("Junk is rejected rather than silently placed at midnight")
    func rejectsJunk() {
        #expect(CloudKitService.combining(time: "N/A", withDayOf: date(2026, 3, 4)) == nil)
        #expect(CloudKitService.combining(time: "", withDayOf: date(2026, 3, 4)) == nil)
        #expect(CloudKitService.combining(time: "boarding", withDayOf: date(2026, 3, 4)) == nil)
    }

    // MARK: - One pass is one flight

    private func pass(flight: String?, from: String?, to: String?, on day: Date?) -> BoardingPassData {
        var data = BoardingPassData()
        data.flightNumber = flight
        data.departureCode = from
        data.arrivalCode = to
        data.departureDate = day
        return data
    }

    @Test("Rescanning the same pass yields the same id")
    func identityIsStableAcrossScans() {
        let first = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26))
        let second = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26))
        // The whole point: this was UUID(), so these were never equal and every
        // rescan wrote a second flight.
        #expect(first.id == second.id)
    }

    @Test("The same time carries no weight; only the day does")
    func identityIgnoresTimeOfDay() {
        let morning = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26, 6, 0))
        let evening = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26, 21, 30))
        #expect(morning.id == evening.id, "a gate change must not fork the flight")
    }

    @Test("A different flight is a different id")
    func differentFlightsDiffer() {
        let base = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26))
        let otherDay = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 27))
        let otherRoute = pass(flight: "UA323", from: "PHL", to: "SFO", on: date(2026, 11, 26))
        let otherNumber = pass(flight: "UA324", from: "PHL", to: "DEN", on: date(2026, 11, 26))

        #expect(base.id != otherDay.id, "the same flight number recurs daily")
        #expect(base.id != otherRoute.id)
        #expect(base.id != otherNumber.id)
    }

    @Test("Spacing and case in a scanned code do not fork the identity")
    func identityIsNormalised() {
        let spaced = pass(flight: "UA 323", from: "phl", to: "den", on: date(2026, 11, 26))
        let clean = pass(flight: "UA323", from: "PHL", to: "DEN", on: date(2026, 11, 26))
        // A confirmation prints "UA 323"; the barcode says "UA323". Same flight.
        #expect(spaced.id == clean.id)
    }

    @Test("A pass with no flight in it does not collide with another")
    func emptyPassesDoNotCollide() {
        let a = pass(flight: nil, from: nil, to: nil, on: nil)
        let b = pass(flight: nil, from: nil, to: nil, on: nil)
        #expect(a.id != b.id, "two unidentifiable passes must not merge into one flight")
    }
}
