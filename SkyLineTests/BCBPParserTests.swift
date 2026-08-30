//
//  BCBPParserTests.swift
//  SkyLineTests
//
//  Exercises the IATA BCBP parse against synthetic payloads built field by
//  field from the spec.
//
//  Every payload here is assembled by `Payload` below rather than pasted in, so
//  the test states the field widths it is relying on and a wrong width fails
//  loudly instead of silently shifting every field after it. No real boarding
//  pass string appears in this repository: a genuine payload carries a real
//  person's name, record locator and frequent flyer number.
//

import Foundation
import Testing
@testable import SkyLine

// MARK: - Payload construction

/// Builds BCBP payloads from named parts.
///
/// The widths are the ones in IATA Resolution 792. They are repeated here on
/// purpose: if the parser's constants ever drift, these tests are the other
/// copy of the truth and the two will disagree.
private enum Payload {

    /// Pads to exactly `width` with spaces, the way an airline encoder does.
    static func field(_ value: String, _ width: Int) -> String {
        precondition(value.count <= width, "'\(value)' does not fit in \(width) characters")
        return value.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    static func hex2(_ value: Int) -> String {
        String(format: "%02X", value)
    }

    /// Items 1, 5, 11, 253.
    static func header(legs: Int, name: String = "TESTER/ALEX", electronicTicket: Bool = true) -> String {
        "M" + String(legs) + field(name, 20) + (electronicTicket ? "E" : " ")
    }

    /// The 37-character repeated mandatory block, items 7 through 6.
    static func leg(
        pnr: String = "ABC123",
        origin: String = "MCT",
        destination: String = "ZRH",
        carrier: String = "WY",
        flightNumber: String = "0153",
        julianDay: String = "153",
        compartment: String = "Y",
        seat: String = "012A",
        sequence: String = "0025",
        status: String = "3",
        conditionalSize: Int = 0
    ) -> String {
        field(pnr, 7)
            + field(origin, 3)
            + field(destination, 3)
            + field(carrier, 3)
            + field(flightNumber, 5)
            + field(julianDay, 3)
            + field(compartment, 1)
            + field(seat, 4)
            + field(sequence, 5)
            + field(status, 1)
            + hex2(conditionalSize)
    }

    /// The unique conditional block, items 15, 12, 14, 22, 16, 21, 23.
    /// 1 + 1 + 1 + 4 + 1 + 3 + 13 = 24 characters.
    static func uniqueConditional(
        passengerDescription: String = "0",
        sourceOfCheckIn: String = "W",
        sourceOfIssuance: String = "W",
        dateOfIssue: String = "6362",
        documentType: String = "B",
        issuingCarrier: String = "WY",
        baggageTag: String = ""
    ) -> String {
        field(passengerDescription, 1)
            + field(sourceOfCheckIn, 1)
            + field(sourceOfIssuance, 1)
            + field(dateOfIssue, 4)
            + field(documentType, 1)
            + field(issuingCarrier, 3)
            + field(baggageTag, 13)
    }

    /// The repeated conditional block, items 142, 143, 18, 108, 19, 20, 236,
    /// 89, 118, 254. 3 + 10 + 1 + 1 + 3 + 3 + 16 + 1 + 3 + 1 = 42 characters.
    static func repeatedConditional(
        airlineNumericCode: String = "910",
        documentSerial: String = "1234567890",
        selectee: String = "0",
        internationalDocumentation: String = "0",
        marketingCarrier: String = "WY",
        frequentFlyerAirline: String = "WY",
        frequentFlyerNumber: String = "WY9876543",
        idAdIndicator: String = " ",
        baggageAllowance: String = "2PC",
        fastTrack: String = "N"
    ) -> String {
        field(airlineNumericCode, 3)
            + field(documentSerial, 10)
            + field(selectee, 1)
            + field(internationalDocumentation, 1)
            + field(marketingCarrier, 3)
            + field(frequentFlyerAirline, 3)
            + field(frequentFlyerNumber, 16)
            + field(idAdIndicator, 1)
            + field(baggageAllowance, 3)
            + field(fastTrack, 1)
    }

    /// Wraps the two blocks in items 8, 9, 10 and 17.
    /// 1 + 1 + 2 + 24 + 2 + 42 = 72 characters, plus item 4.
    static func firstLegConditional(
        version: String = "6",
        unique: String = uniqueConditional(),
        repeatedBlock: String = repeatedConditional(),
        airlineUse: String = ""
    ) -> String {
        ">" + version + hex2(unique.count) + unique + hex2(repeatedBlock.count) + repeatedBlock + airlineUse
    }

    /// Legs after the first carry no version marker and no unique block.
    static func laterLegConditional(
        repeatedBlock: String = repeatedConditional(),
        airlineUse: String = ""
    ) -> String {
        hex2(repeatedBlock.count) + repeatedBlock + airlineUse
    }
}

// MARK: - Dates

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}

private func parseError(_ payload: String, referenceDate: Date = day(2026, 6, 1)) -> BCBPParseError? {
    do {
        _ = try BCBPParser.parse(payload, referenceDate: referenceDate)
        return nil
    } catch let error as BCBPParseError {
        return error
    } catch {
        return nil
    }
}

// MARK: - Mandatory section

@Suite("BCBP mandatory section")
struct BCBPMandatorySectionTests {

    @Test("A mandatory-only payload yields every encoded field")
    func mandatoryOnly() throws {
        // 23 header + 37 leg = the shortest legal boarding pass barcode.
        let payload = Payload.header(legs: 1) + Payload.leg()
        #expect(payload.count == 60)

        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))

        #expect(pass.formatCode == "M")
        #expect(pass.declaredLegCount == 1)
        #expect(pass.legs.count == 1)
        #expect(pass.passengerNameRaw == "TESTER/ALEX")
        #expect(pass.passengerName == "ALEX TESTER")
        #expect(pass.isElectronicTicket)
        // No conditional section at all, so no version and no issue date.
        #expect(pass.versionNumber == nil)
        #expect(pass.dateOfIssue == nil)
        #expect(pass.hasSecurityData == false)

        let leg = try #require(pass.primaryLeg)
        #expect(leg.operatingCarrierPNR == "ABC123")
        #expect(leg.origin == "MCT")
        #expect(leg.destination == "ZRH")
        #expect(leg.operatingCarrier == "WY")
        #expect(leg.flightNumberDigits == "0153")
        #expect(leg.flightNumberSuffix == nil)
        #expect(leg.flightDesignator == "WY153")
        #expect(leg.julianDayOfFlight == 153)
        #expect(leg.compartmentCode == "Y")
        // Encoded as `012A`; the app's seat pattern is `^[0-9]{1,3}[A-Z]$`.
        #expect(leg.seatNumber == "12A")
        #expect(leg.checkInSequenceNumber == "0025")
        #expect(leg.passengerStatus == "3")
    }

    @Test("Blank optional fields become nil, never empty strings")
    func blanksBecomeNil() throws {
        // `trip.country ?? resolved?.name` never fires when the stored value is
        // "", so a blank field has to arrive as nil.
        let payload = Payload.header(legs: 1)
            + Payload.leg(pnr: "", seat: "", sequence: "", status: "")

        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))
        let leg = try #require(pass.primaryLeg)

        #expect(leg.operatingCarrierPNR == nil)
        #expect(leg.seatNumber == nil)
        #expect(leg.checkInSequenceNumber == nil)
        #expect(leg.passengerStatus == nil)
    }

    @Test("A flight number's operational suffix is kept out of the designator")
    func flightNumberSuffix() throws {
        let payload = Payload.header(legs: 1) + Payload.leg(flightNumber: "0153A")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))
        let leg = try #require(pass.primaryLeg)

        #expect(leg.flightNumberDigits == "0153")
        #expect(leg.flightNumberSuffix == "A")
        // `^[A-Z]{2,3}[0-9]{1,4}$` is the app's own validation pattern.
        #expect(leg.flightDesignator == "WY153")
    }

    @Test("A three-character carrier designator is accepted")
    func threeCharacterCarrier() throws {
        let payload = Payload.header(legs: 1) + Payload.leg(carrier: "EZS")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))
        #expect(pass.primaryLeg?.operatingCarrier == "EZS")
    }

    @Test("The same payload always produces the same id")
    func stableIdentity() throws {
        let payload = Payload.header(legs: 1) + Payload.leg()
        let first = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))
        let second = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 9))
        let other = try BCBPParser.parse(
            Payload.header(legs: 1) + Payload.leg(pnr: "ZZZ999"),
            referenceDate: day(2026, 6, 1)
        )

        // A rescan of the same pass must not mint a new identity: `UUID()`
        // here would break SwiftUI diffing and any later correlation.
        #expect(first.stableID == second.stableID)
        #expect(first.stableID != other.stableID)
    }
}

// MARK: - Multi-leg

@Suite("BCBP multiple legs")
struct BCBPMultiLegTests {

    @Test("A two-leg payload yields both legs in itinerary order")
    func twoLegs() throws {
        let payload = Payload.header(legs: 2)
            + Payload.leg(origin: "MCT", destination: "DXB", flightNumber: "0641", julianDay: "153")
            + Payload.leg(origin: "DXB", destination: "LHR", carrier: "EK", flightNumber: "0007", julianDay: "154")

        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))

        #expect(pass.declaredLegCount == 2)
        #expect(pass.legs.count == 2)
        #expect(pass.legs[0].origin == "MCT")
        #expect(pass.legs[0].destination == "DXB")
        #expect(pass.legs[0].flightDesignator == "WY641")
        #expect(pass.legs[1].origin == "DXB")
        #expect(pass.legs[1].destination == "LHR")
        #expect(pass.legs[1].flightDesignator == "EK7")
    }

    @Test("A multi-leg payload with conditional sections on every leg")
    func multiLegWithConditionalSections() throws {
        let firstConditional = Payload.firstLegConditional()
        let laterConditional = Payload.laterLegConditional()

        let payload = Payload.header(legs: 2)
            + Payload.leg(origin: "MCT", destination: "DXB", conditionalSize: firstConditional.count)
            + firstConditional
            + Payload.leg(origin: "DXB", destination: "LHR", carrier: "EK", julianDay: "154",
                          conditionalSize: laterConditional.count)
            + laterConditional

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 5))

        #expect(pass.legs.count == 2)
        #expect(pass.versionNumber == "6")
        #expect(pass.issuingCarrier == "WY")
        // The unique block appears once, on leg one only.
        #expect(pass.legs[0].frequentFlyerNumber == "WY9876543")
        #expect(pass.legs[1].frequentFlyerNumber == "WY9876543")
        #expect(pass.legs[1].marketingCarrier == "WY")
    }

    @Test("Declaring more legs than the payload holds is rejected, not truncated")
    func shortPayloadForDeclaredLegs() {
        // The bug this guards against: returning the legs that happened to fit
        // and letting the caller believe it read a complete itinerary.
        let payload = Payload.header(legs: 2) + Payload.leg()
        #expect(payload.count == 60)

        let error = parseError(payload)
        #expect(error == .tooShort(expected: 97, actual: 60))
    }

    @Test("A later leg on a lower Julian day rolls into the next year")
    func multiLegAcrossNewYear() throws {
        let conditional = Payload.firstLegConditional(
            unique: Payload.uniqueConditional(dateOfIssue: "6362")  // 28 Dec 2026
        )
        let payload = Payload.header(legs: 2)
            + Payload.leg(julianDay: "362", conditionalSize: conditional.count)
            + conditional
            + Payload.leg(origin: "ZRH", destination: "MCT", julianDay: "005")

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 9))

        #expect(pass.legs[0].flightDate == day(2026, 12, 28))
        // Day 5 is BEFORE day 362 in the same year, so the outbound-year answer
        // would be 5 Jan 2026 - eleven months before the flight was booked.
        #expect(pass.legs[1].flightDate == day(2027, 1, 5))
        #expect(pass.legs[0].flightDateWasInferred == false)
        #expect(pass.legs[1].flightDateWasInferred == false)
    }
}

// MARK: - Conditional section

@Suite("BCBP conditional section")
struct BCBPConditionalSectionTests {

    @Test("The conditional items are read and the issue date resolved")
    func conditionalSection() throws {
        let conditional = Payload.firstLegConditional()
        let payload = Payload.header(legs: 1)
            + Payload.leg(conditionalSize: conditional.count)
            + conditional

        #expect(conditional.count == 72)

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 5))

        #expect(pass.versionNumber == "6")
        #expect(pass.passengerDescription == "0")
        #expect(pass.sourceOfCheckIn == "W")
        #expect(pass.sourceOfBoardingPassIssuance == "W")
        #expect(pass.documentType == "B")
        #expect(pass.issuingCarrier == "WY")
        #expect(pass.baggageTagLicencePlate == nil)  // blank, not ""
        #expect(pass.dateOfIssue == day(2026, 12, 28))

        let leg = try #require(pass.primaryLeg)
        #expect(leg.airlineNumericCode == "910")
        #expect(leg.documentFormSerialNumber == "1234567890")
        #expect(leg.marketingCarrier == "WY")
        #expect(leg.frequentFlyerAirline == "WY")
        #expect(leg.frequentFlyerNumber == "WY9876543")
        #expect(leg.freeBaggageAllowance == "2PC")
        #expect(leg.fastTrack == "N")
    }

    @Test("A carrier-specific airline-use tail is kept and does not shift fields")
    func airlineUseSection() throws {
        let conditional = Payload.firstLegConditional(airlineUse: "LX*1AB")
        let payload = Payload.header(legs: 1)
            + Payload.leg(conditionalSize: conditional.count)
            + conditional

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 5))
        #expect(pass.primaryLeg?.airlineUseSection == "LX*1AB")
        #expect(pass.primaryLeg?.frequentFlyerNumber == "WY9876543")
    }

    @Test("A security section after the last leg is noticed, not parsed")
    func securitySection() throws {
        let conditional = Payload.firstLegConditional()
        let payload = Payload.header(legs: 1)
            + Payload.leg(conditionalSize: conditional.count)
            + conditional
            + "^164GIWVC5EH7JNT684FVNJ91W2QA4DVN5J8K4F0L0GEQ3DF5TGBN8709HKT5D3DW3GBHFCVHMY7J5T6HFR41W2QA4DVN5J8K4F0L0GEQ3DF5TGBN8709HKT5D3DW3GBHFCVHMY7J5T6HFR4"

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 5))
        #expect(pass.hasSecurityData)
        #expect(pass.legs.count == 1)
    }

    @Test("A conditional section longer than the payload is rejected")
    func overDeclaredConditionalSection() {
        let payload = Payload.header(legs: 1) + Payload.leg(conditionalSize: 255)
        let error = parseError(payload)
        #expect(error == .truncatedConditionalSection(leg: 0, declared: 255, available: 0))
    }
}

// MARK: - Julian date resolution

@Suite("BCBP Julian date resolution")
struct BCBPJulianDateTests {

    @Test("With no date of issue, the year nearest to now wins")
    func nearestYearWhenNoIssueDate() throws {
        let payload = Payload.header(legs: 1) + Payload.leg(julianDay: "153")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))

        #expect(pass.primaryLeg?.flightDate == day(2026, 6, 2))  // day 153 of 2026
        #expect(pass.primaryLeg?.flightDateWasInferred == true)
    }

    @Test("A December flight scanned in January resolves to the December just gone")
    func decemberFlightScannedInJanuary() throws {
        // The failure mode this exists for: naively using the current year puts
        // a flight taken ten days ago eleven months into the future.
        let payload = Payload.header(legs: 1) + Payload.leg(julianDay: "360")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 5))

        #expect(pass.primaryLeg?.flightDate == day(2026, 12, 26))
        #expect(pass.primaryLeg?.flightDateWasInferred == true)
    }

    @Test("A January flight scanned in December resolves to the January coming")
    func januaryFlightScannedInDecember() throws {
        let payload = Payload.header(legs: 1) + Payload.leg(julianDay: "005")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 12, 28))

        #expect(pass.primaryLeg?.flightDate == day(2027, 1, 5))
    }

    @Test("The encoded date of issue beats the nearest-year guess")
    func issueDateWins() throws {
        // Issued day 362 of a year ending in 6 - 28 December 2026 - for a
        // flight on day 5. Nearest-to-now would answer 5 January 2027 here too,
        // so the test also checks the flag that says which rule fired.
        let conditional = Payload.firstLegConditional(
            unique: Payload.uniqueConditional(dateOfIssue: "6362")
        )
        let payload = Payload.header(legs: 1)
            + Payload.leg(julianDay: "005", conditionalSize: conditional.count)
            + conditional

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 9))

        #expect(pass.dateOfIssue == day(2026, 12, 28))
        #expect(pass.primaryLeg?.flightDate == day(2027, 1, 5))
        #expect(pass.primaryLeg?.flightDateWasInferred == false)
    }

    @Test("An issue date years back still resolves inside the ten-year window")
    func oldIssueDate() throws {
        // Year digit 1, scanned in 2027: the only year ending in 1 inside
        // [2019, 2028] is 2021.
        let conditional = Payload.firstLegConditional(
            unique: Payload.uniqueConditional(dateOfIssue: "1100")
        )
        let payload = Payload.header(legs: 1)
            + Payload.leg(julianDay: "110", conditionalSize: conditional.count)
            + conditional

        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 1, 9))

        #expect(pass.dateOfIssue == day(2021, 4, 10))   // day 100 of 2021
        #expect(pass.primaryLeg?.flightDate == day(2021, 4, 20))  // day 110 of 2021
    }

    @Test("Day 366 exists only in a leap year")
    func leapDayHandling() {
        #expect(BCBPParser.date(year: 2024, dayOfYear: 366) == day(2024, 12, 31))
        #expect(BCBPParser.date(year: 2026, dayOfYear: 366) == nil)
        #expect(BCBPParser.date(year: 2026, dayOfYear: 365) == day(2026, 12, 31))
    }

    @Test("Day 366 with no year encoded lands on the nearest leap year")
    func leapDayNearest() throws {
        let payload = Payload.header(legs: 1) + Payload.leg(julianDay: "366")
        let pass = try BCBPParser.parse(payload, referenceDate: day(2027, 3, 1))

        // 2027 has no day 366. The nearest year that does is 2028.
        #expect(pass.primaryLeg?.flightDate == day(2028, 12, 31))
    }

    @Test("earliestDate never answers before its anchor")
    func earliestDateRespectsAnchor() {
        let anchor = day(2026, 12, 28)
        #expect(BCBPParser.earliestDate(dayOfYear: 5, onOrAfter: anchor) == day(2027, 1, 5))
        #expect(BCBPParser.earliestDate(dayOfYear: 362, onOrAfter: anchor) == day(2026, 12, 28))
        #expect(BCBPParser.earliestDate(dayOfYear: 363, onOrAfter: anchor) == day(2026, 12, 29))
    }

    @Test("The single issue-year digit resolves inside a ten-year window")
    func yearDigitWindow() {
        let reference = day(2026, 6, 1)  // window [2018, 2027]
        #expect(BCBPParser.resolveYearDigitDate(yearDigit: 6, dayOfYear: 1, referenceDate: reference) == day(2026, 1, 1))
        #expect(BCBPParser.resolveYearDigitDate(yearDigit: 7, dayOfYear: 1, referenceDate: reference) == day(2027, 1, 1))
        #expect(BCBPParser.resolveYearDigitDate(yearDigit: 8, dayOfYear: 1, referenceDate: reference) == day(2018, 1, 1))
        // Not a date: day 366 of a non-leap year, and the digit is unambiguous.
        #expect(BCBPParser.resolveYearDigitDate(yearDigit: 6, dayOfYear: 366, referenceDate: reference) == nil)
    }
}

// MARK: - Rejection

@Suite("BCBP rejects malformed input")
struct BCBPRejectionTests {

    @Test("An empty payload is rejected")
    func empty() {
        #expect(parseError("") == .empty)
        #expect(parseError("   \n  ") != nil)
    }

    @Test("A payload that is not a boarding pass is rejected on the format code")
    func notABoardingPass() {
        let url = "https://example.com/check-in?ref=1234567890123456789012345678901234567890"
        #expect(BCBPParser.looksLikeBCBP(url) == false)
        #expect(parseError(url) == .unsupportedFormatCode("h"))
    }

    @Test("A zero leg count is rejected")
    func zeroLegs() {
        let payload = Payload.header(legs: 0) + Payload.leg()
        #expect(parseError(payload) == .invalidLegCount("0"))
    }

    @Test("A payload shorter than one leg is rejected")
    func shorterThanOneLeg() {
        let payload = String((Payload.header(legs: 1) + Payload.leg()).prefix(59))
        #expect(parseError(payload) == .tooShort(expected: 60, actual: 59))
    }

    @Test("An airport code with a digit in it is rejected")
    func badAirportCode() {
        let payload = Payload.header(legs: 1) + Payload.leg(origin: "M1T")
        guard case .invalidField(let name, _, let leg) = parseError(payload) else {
            Issue.record("expected an invalidField error")
            return
        }
        #expect(name == "origin")
        #expect(leg == 0)
    }

    @Test("A two-character destination is rejected")
    func shortDestination() {
        let payload = Payload.header(legs: 1) + Payload.leg(destination: "ZR")
        guard case .invalidField(let name, _, _) = parseError(payload) else {
            Issue.record("expected an invalidField error")
            return
        }
        #expect(name == "destination")
    }

    @Test("A Julian day outside 1...366 is rejected")
    func badJulianDay() {
        for value in ["999", "000", "36A"] {
            let payload = Payload.header(legs: 1) + Payload.leg(julianDay: value)
            guard case .invalidField(let name, _, _) = parseError(payload) else {
                Issue.record("expected an invalidField error for julian day '\(value)'")
                return
            }
            #expect(name == "julianDateOfFlight")
        }
    }

    @Test("A non-numeric flight number is rejected")
    func badFlightNumber() {
        let payload = Payload.header(legs: 1) + Payload.leg(flightNumber: "ABCDE")
        guard case .invalidField(let name, _, _) = parseError(payload) else {
            Issue.record("expected an invalidField error")
            return
        }
        #expect(name == "flightNumber")
    }

    @Test("A carrier designator of digits only is rejected")
    func badCarrier() {
        let payload = Payload.header(legs: 1) + Payload.leg(carrier: "123")
        guard case .invalidField(let name, _, _) = parseError(payload) else {
            Issue.record("expected an invalidField error")
            return
        }
        #expect(name == "operatingCarrier")
    }

    @Test("A malformed payload never half-parses into a usable pass")
    func noPartialResults() {
        // Each of these breaks a different field. None may come back as a
        // pass with the broken field quietly nil - that is exactly how a wrong
        // flight gets saved.
        let broken = [
            Payload.header(legs: 1) + Payload.leg(origin: "??"),
            Payload.header(legs: 1) + Payload.leg(julianDay: "400"),
            Payload.header(legs: 1) + Payload.leg(flightNumber: "12X45"),
            Payload.header(legs: 3) + Payload.leg() + Payload.leg()
        ]
        for payload in broken {
            #expect(parseError(payload) != nil, "expected \(payload.prefix(2)) to be rejected")
        }
    }

    @Test("A leading newline from the scanner does not shift the fields")
    func newlineTolerance() throws {
        let payload = "\n" + Payload.header(legs: 1) + Payload.leg() + "\r\n"
        let pass = try BCBPParser.parse(payload, referenceDate: day(2026, 6, 1))
        #expect(pass.primaryLeg?.origin == "MCT")
        #expect(pass.primaryLeg?.destination == "ZRH")
    }
}
