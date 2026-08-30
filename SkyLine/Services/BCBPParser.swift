//
//  BCBPParser.swift
//  SkyLine
//
//  Deterministic parser for the IATA Bar Coded Boarding Pass (BCBP) payload -
//  IATA Resolution 792, the string encoded in the PDF417 (or Aztec) barcode
//  printed on every IATA boarding pass.
//
//  Why this exists: the app previously photographed a boarding pass, uploaded
//  it to a third-party router and asked a vision LLM to read fields that were
//  already sitting in the barcode as fixed-width, machine-readable text. This
//  file reads them instead. No network, no model, no guessing.
//
//  The file is deliberately free of Vision, UIKit and any I/O so that the whole
//  format can be exercised from unit tests with synthetic payloads.
//

import Foundation

// MARK: - Errors

/// Why a payload was rejected.
///
/// Every case names the offending field and leg. A scan that fails needs to say
/// *what* failed: the alternative is a silent fall-through to an LLM that
/// invents a plausible-looking flight.
enum BCBPParseError: Error, Equatable {

    /// Nothing left to parse after normalisation.
    case empty

    /// The first character was not `M`. Anything else means this is not a
    /// boarding pass barcode at all - a URL QR code, a bag tag, a loyalty card.
    case unsupportedFormatCode(String)

    /// The leg-count character was not `1`...`9`.
    case invalidLegCount(String)

    /// Fewer characters than the declared number of legs requires.
    ///
    /// Refusing is the whole point. Returning the two legs that happened to fit
    /// would be indistinguishable, to the caller, from a genuine two-leg pass -
    /// the same class of bug as a `fetchLimit` amputating the end of a trip.
    case tooShort(expected: Int, actual: Int)

    /// A leg declared a conditional block longer than the characters that remain.
    case truncatedConditionalSection(leg: Int, declared: Int, available: Int)

    /// A mandatory field did not match its documented shape.
    case invalidField(name: String, value: String, leg: Int)

    /// A Julian day that no candidate year could turn into a real calendar date.
    case unresolvableFlightDate(julianDay: Int, leg: Int)
}

extension BCBPParseError: CustomStringConvertible {
    var description: String {
        switch self {
        case .empty:
            return "Empty barcode payload"
        case .unsupportedFormatCode(let code):
            return "Not a BCBP payload: format code '\(code)', expected 'M'"
        case .invalidLegCount(let raw):
            return "Invalid leg count '\(raw)', expected 1-9"
        case .tooShort(let expected, let actual):
            return "Payload too short: needs \(expected) characters, has \(actual)"
        case .truncatedConditionalSection(let leg, let declared, let available):
            return "Leg \(leg) declares a \(declared)-character conditional section but only \(available) remain"
        case .invalidField(let name, let value, let leg):
            return "Leg \(leg): field '\(name)' has invalid value '\(value)'"
        case .unresolvableFlightDate(let julianDay, let leg):
            return "Leg \(leg): Julian day \(julianDay) is not a real date in any candidate year"
        }
    }
}

// MARK: - Model

/// One flight coupon from the barcode.
///
/// Every value here is checksummed print on the pass itself. Nothing on this
/// type may be overwritten by a text-recognition or LLM guess.
struct BCBPLeg: Equatable {

    /// Item 7. The airline's own record locator - what the app calls the
    /// confirmation code. Six characters in practice, seven in the field.
    let operatingCarrierPNR: String?

    /// Item 26. Three-letter IATA code.
    let origin: String

    /// Item 38. Three-letter IATA code.
    let destination: String

    /// Item 42. Two- or three-character IATA carrier designator, e.g. `WY`.
    let operatingCarrier: String

    /// Item 43, numeric part, as encoded: right-justified and zero-padded,
    /// e.g. `0153`.
    let flightNumberDigits: String

    /// Item 43, the optional trailing operational suffix, e.g. the `A` in
    /// `0153A`. Kept apart from `flightDesignator` because the app's own
    /// flight-number validation pattern (`^[A-Z]{2,3}[0-9]{1,4}$`) rejects it.
    let flightNumberSuffix: String?

    /// Item 46. Day of year, 1...366. Carries no year - see `flightDate`.
    let julianDayOfFlight: Int

    /// Item 71, e.g. `Y`, `J`, `F`.
    let compartmentCode: String?

    /// Item 104, zero-padding removed, e.g. `12A`. `INF` for a lap infant.
    let seatNumber: String?

    /// Item 107.
    let checkInSequenceNumber: String?

    /// Item 113.
    let passengerStatus: String?

    /// The Julian day resolved to a real calendar date. See
    /// `BCBPParser.resolveFlightDate` for exactly how the year was chosen.
    ///
    /// Midnight UTC. BCBP dates are local to the departure airport, and the
    /// barcode does not carry a timezone, so any other instant would be an
    /// invention. Callers that need airport-local time should re-anchor it.
    let flightDate: Date

    /// `true` when the year came from "which year puts this flight nearest to
    /// now", `false` when it was derived from the encoded date of issue.
    ///
    /// Surfaced rather than hidden: an inferred year is a guess with a
    /// one-year failure mode, and a caller may want to ask the user.
    let flightDateWasInferred: Bool

    // Conditional (optional) items. Absent on a mandatory-only pass.

    /// Item 142.
    let airlineNumericCode: String?
    /// Item 143.
    let documentFormSerialNumber: String?
    /// Item 18.
    let selecteeIndicator: String?
    /// Item 19. The carrier that sold the seat, when it differs from the
    /// operating carrier - i.e. a codeshare.
    let marketingCarrier: String?
    /// Item 20.
    let frequentFlyerAirline: String?
    /// Item 236.
    let frequentFlyerNumber: String?
    /// Item 118.
    let freeBaggageAllowance: String?
    /// Item 254. Present from version 5 onwards.
    let fastTrack: String?
    /// Item 4. Unstructured, carrier-specific.
    let airlineUseSection: String?

    /// `WY153` - carrier designator plus the flight number with its encoding
    /// zero-padding stripped. The operational suffix is deliberately excluded;
    /// it lives in `flightNumberSuffix`.
    var flightDesignator: String {
        let trimmed = String(flightNumberDigits.drop(while: { $0 == "0" }))
        return operatingCarrier + (trimmed.isEmpty ? "0" : trimmed)
    }
}

/// A whole boarding pass barcode.
struct BCBPBoardingPass: Equatable {

    /// Item 1. Always `M` - the only format code this parser accepts.
    let formatCode: String

    /// Item 5, as declared in the payload. Always equal to `legs.count`: the
    /// parser throws rather than returning fewer legs than were declared.
    let declaredLegCount: Int

    /// Item 11 exactly as encoded, e.g. `DESMARAIS/LUC`.
    let passengerNameRaw: String?

    /// The same name in reading order, e.g. `LUC DESMARAIS`.
    ///
    /// Case is left alone. Boarding passes are upper case and title-casing them
    /// turns `MCDONALD` into `Mcdonald`. Any honorific suffix the airline glued
    /// on is also left alone - stripping a trailing `MS` would eat real names.
    let passengerName: String?

    /// Item 253.
    let isElectronicTicket: Bool

    /// Item 9, e.g. `6`.
    let versionNumber: String?

    /// Item 22, resolved to a real date. Nil when the pass carries no
    /// conditional section, which is common on mobile passes.
    let dateOfIssue: Date?

    /// Item 21.
    let issuingCarrier: String?

    /// Item 15.
    let passengerDescription: String?
    /// Item 12.
    let sourceOfCheckIn: String?
    /// Item 14.
    let sourceOfBoardingPassIssuance: String?
    /// Item 16.
    let documentType: String?
    /// Item 23.
    let baggageTagLicencePlate: String?

    /// One entry per flight coupon, in itinerary order.
    let legs: [BCBPLeg]

    /// Item 25 was present. The signature bytes themselves are not retained -
    /// nothing in this app can verify them, and they are of no use unverified.
    let hasSecurityData: Bool

    /// Content-derived, stable across processes and rescans.
    ///
    /// `UUID()` would hand the same physical pass a new identity on every scan,
    /// which breaks SwiftUI diffing and any later correlation. Swift's `Hasher`
    /// is seeded per process and is equally unusable, so this is FNV-1a.
    let stableID: String

    /// The first coupon. Every consumer in the app today books one flight.
    var primaryLeg: BCBPLeg? { legs.first }
}

// MARK: - Parser

/// IATA Resolution 792 mandatory + conditional item parser.
///
/// The mandatory section is a fixed-offset parse and is validated field by
/// field. A parse that does not check its own shape is worse than no parse:
/// it hands the rest of the app a confident, wrong flight.
enum BCBPParser {

    // MARK: Field widths (Resolution 792)

    private enum Width {
        // Unique mandatory header.
        static let formatCode = 1
        static let legCount = 1
        static let passengerName = 20
        static let electronicTicketIndicator = 1
        /// 1 + 1 + 20 + 1
        static let uniqueHeader = 23

        // Repeated mandatory section, once per leg.
        static let pnr = 7
        static let origin = 3
        static let destination = 3
        static let carrier = 3
        static let flightNumber = 5
        static let julianDate = 3
        static let compartment = 1
        static let seat = 4
        static let checkInSequence = 5
        static let passengerStatus = 1
        static let conditionalSizeField = 2
        /// 7 + 3 + 3 + 3 + 5 + 3 + 1 + 4 + 5 + 1 + 2
        static let perLegMandatory = 37

        // Conditional, unique (leg 1 only).
        static let versionMarker = 1
        static let versionNumber = 1
        static let uniqueConditionalSizeField = 2
        static let repeatedConditionalSizeField = 2
    }

    /// Marks the start of the version number, item 8.
    private static let versionMarker: Character = ">"
    /// Marks the start of the security section, item 25.
    private static let securityMarker: Character = "^"

    /// UTC so that a parse is reproducible on any device in any timezone.
    /// See `BCBPLeg.flightDate` for why UTC and not something cleverer.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    // MARK: Entry point

    /// Parse a barcode payload.
    ///
    /// - Parameters:
    ///   - payload: the decoded barcode string, exactly as Vision returned it.
    ///   - referenceDate: "now". Injected so that Julian-date resolution is
    ///     testable and so a rescan of the same photo months later can be made
    ///     to agree with the original scan by passing the photo's own date.
    static func parse(_ payload: String, referenceDate: Date = Date()) throws -> BCBPBoardingPass {
        let normalised = normalisePayload(payload)
        guard !normalised.isEmpty else { throw BCBPParseError.empty }

        let chars = Array(normalised)

        guard chars.count >= Width.uniqueHeader + Width.perLegMandatory else {
            throw BCBPParseError.tooShort(
                expected: Width.uniqueHeader + Width.perLegMandatory,
                actual: chars.count
            )
        }

        let formatCode = String(chars[0])
        guard formatCode == "M" else {
            throw BCBPParseError.unsupportedFormatCode(formatCode)
        }

        let legCountRaw = String(chars[1])
        guard let declaredLegCount = Int(legCountRaw), (1...9).contains(declaredLegCount) else {
            throw BCBPParseError.invalidLegCount(legCountRaw)
        }

        let minimumLength = Width.uniqueHeader + declaredLegCount * Width.perLegMandatory
        guard chars.count >= minimumLength else {
            throw BCBPParseError.tooShort(expected: minimumLength, actual: chars.count)
        }

        let rawName = String(chars[2..<22])
        let electronicTicketIndicator = String(chars[22])

        // Pass 1: read every leg's mandatory block and whatever conditional
        // block it declares. The date of issue lives inside leg 1's CONDITIONAL
        // section, which sits after leg 1's Julian day, so no flight date can be
        // resolved until the whole payload has been walked.
        var cursor = Width.uniqueHeader
        var rawLegs: [RawLeg] = []
        var unique: UniqueConditional?

        for legIndex in 0..<declaredLegCount {
            let (rawLeg, uniqueForThisLeg, nextCursor) = try parseLeg(
                chars: chars,
                start: cursor,
                legIndex: legIndex,
                isFirstLeg: legIndex == 0
            )
            if legIndex == 0 { unique = uniqueForThisLeg }
            rawLegs.append(rawLeg)
            cursor = nextCursor
        }

        // Item 25 sits after the last leg. Some issuers park it inside the last
        // leg's airline-use section instead, so check both.
        let trailing = cursor < chars.count ? String(chars[cursor...]) : ""
        let hasSecurityData = trailing.first == securityMarker
            || (rawLegs.last?.airlineUseSection?.contains(securityMarker) ?? false)

        // Pass 2: resolve dates now that the date of issue, if any, is known.
        let dateOfIssue = unique.flatMap { issue -> Date? in
            guard let julian = issue.dateOfIssueJulian else { return nil }
            return resolveYearDigitDate(
                yearDigit: julian.yearDigit,
                dayOfYear: julian.dayOfYear,
                referenceDate: referenceDate
            )
        }

        var legs: [BCBPLeg] = []
        var previousDate: Date?
        // Once a leg's year is a guess, every leg anchored to it is a guess too.
        var previousInferred = false

        for (legIndex, rawLeg) in rawLegs.enumerated() {
            let resolution: (date: Date, wasInferred: Bool)

            if let previousDate {
                // A later coupon is never before an earlier one. Anchoring to
                // the previous leg is what makes a 30 Dec -> 2 Jan itinerary
                // land in two different years instead of collapsing into one.
                guard let date = earliestDate(
                    dayOfYear: rawLeg.julianDayOfFlight,
                    onOrAfter: previousDate
                ) else {
                    throw BCBPParseError.unresolvableFlightDate(
                        julianDay: rawLeg.julianDayOfFlight,
                        leg: legIndex
                    )
                }
                resolution = (date, previousInferred)
            } else if let dateOfIssue {
                // A pass is issued on or before the day of travel, so the
                // flight is the first occurrence of this day of year on or
                // after the issue date.
                guard let date = earliestDate(
                    dayOfYear: rawLeg.julianDayOfFlight,
                    onOrAfter: dateOfIssue
                ) else {
                    throw BCBPParseError.unresolvableFlightDate(
                        julianDay: rawLeg.julianDayOfFlight,
                        leg: legIndex
                    )
                }
                resolution = (date, false)
            } else {
                // No encoded year anywhere. Pick the year that puts the flight
                // nearest to `referenceDate` - a boarding pass being scanned is
                // overwhelmingly a recent or imminent one - and flag it as a
                // guess so a caller can say so.
                guard let date = nearestDate(
                    dayOfYear: rawLeg.julianDayOfFlight,
                    to: referenceDate
                ) else {
                    throw BCBPParseError.unresolvableFlightDate(
                        julianDay: rawLeg.julianDayOfFlight,
                        leg: legIndex
                    )
                }
                resolution = (date, true)
            }

            previousInferred = resolution.wasInferred
            previousDate = resolution.date

            legs.append(rawLeg.finalised(flightDate: resolution.date, wasInferred: resolution.wasInferred))
        }

        let trimmedName = rawName.trimmingCharacters(in: .whitespaces)

        return BCBPBoardingPass(
            formatCode: formatCode,
            declaredLegCount: declaredLegCount,
            passengerNameRaw: blankToNil(trimmedName),
            passengerName: displayName(from: trimmedName),
            isElectronicTicket: electronicTicketIndicator.uppercased() == "E",
            versionNumber: unique?.versionNumber,
            dateOfIssue: dateOfIssue,
            issuingCarrier: unique?.issuingCarrier,
            passengerDescription: unique?.passengerDescription,
            sourceOfCheckIn: unique?.sourceOfCheckIn,
            sourceOfBoardingPassIssuance: unique?.sourceOfBoardingPassIssuance,
            documentType: unique?.documentType,
            baggageTagLicencePlate: unique?.baggageTagLicencePlate,
            legs: legs,
            hasSecurityData: hasSecurityData,
            stableID: "bcbp-" + PlaceClusterer.stableHash(normalised)
        )
    }

    /// Whether a string even looks like it might be a BCBP payload.
    ///
    /// Cheap enough to run over every barcode in a photo before committing to a
    /// full parse, and specific enough that a Wi-Fi QR code never reaches it.
    static func looksLikeBCBP(_ payload: String) -> Bool {
        let chars = Array(normalisePayload(payload))
        guard chars.count >= Width.uniqueHeader + Width.perLegMandatory else { return false }
        guard chars[0] == "M" else { return false }
        guard let legs = Int(String(chars[1])), (1...9).contains(legs) else { return false }
        return true
    }

    // MARK: - Leg parsing

    /// Everything about a leg except its resolved date.
    private struct RawLeg {
        var operatingCarrierPNR: String?
        var origin: String
        var destination: String
        var operatingCarrier: String
        var flightNumberDigits: String
        var flightNumberSuffix: String?
        var julianDayOfFlight: Int
        var compartmentCode: String?
        var seatNumber: String?
        var checkInSequenceNumber: String?
        var passengerStatus: String?
        var airlineNumericCode: String?
        var documentFormSerialNumber: String?
        var selecteeIndicator: String?
        var marketingCarrier: String?
        var frequentFlyerAirline: String?
        var frequentFlyerNumber: String?
        var freeBaggageAllowance: String?
        var fastTrack: String?
        var airlineUseSection: String?

        func finalised(flightDate: Date, wasInferred: Bool) -> BCBPLeg {
            BCBPLeg(
                operatingCarrierPNR: operatingCarrierPNR,
                origin: origin,
                destination: destination,
                operatingCarrier: operatingCarrier,
                flightNumberDigits: flightNumberDigits,
                flightNumberSuffix: flightNumberSuffix,
                julianDayOfFlight: julianDayOfFlight,
                compartmentCode: compartmentCode,
                seatNumber: seatNumber,
                checkInSequenceNumber: checkInSequenceNumber,
                passengerStatus: passengerStatus,
                flightDate: flightDate,
                flightDateWasInferred: wasInferred,
                airlineNumericCode: airlineNumericCode,
                documentFormSerialNumber: documentFormSerialNumber,
                selecteeIndicator: selecteeIndicator,
                marketingCarrier: marketingCarrier,
                frequentFlyerAirline: frequentFlyerAirline,
                frequentFlyerNumber: frequentFlyerNumber,
                freeBaggageAllowance: freeBaggageAllowance,
                fastTrack: fastTrack,
                airlineUseSection: airlineUseSection
            )
        }
    }

    /// The conditional items that appear once per pass, on leg 1 only.
    private struct UniqueConditional {
        var versionNumber: String?
        var passengerDescription: String?
        var sourceOfCheckIn: String?
        var sourceOfBoardingPassIssuance: String?
        var dateOfIssueJulian: (yearDigit: Int, dayOfYear: Int)?
        var documentType: String?
        var issuingCarrier: String?
        var baggageTagLicencePlate: String?
    }

    private static func parseLeg(
        chars: [Character],
        start: Int,
        legIndex: Int,
        isFirstLeg: Bool
    ) throws -> (RawLeg, UniqueConditional?, Int) {

        var cursor = start

        func take(_ count: Int) throws -> String {
            guard cursor + count <= chars.count else {
                throw BCBPParseError.tooShort(expected: cursor + count, actual: chars.count)
            }
            let value = String(chars[cursor..<(cursor + count)])
            cursor += count
            return value
        }

        let pnr = try take(Width.pnr)
        let origin = try take(Width.origin)
        let destination = try take(Width.destination)
        let carrier = try take(Width.carrier)
        let flightNumber = try take(Width.flightNumber)
        let julian = try take(Width.julianDate)
        let compartment = try take(Width.compartment)
        let seat = try take(Width.seat)
        let sequence = try take(Width.checkInSequence)
        let status = try take(Width.passengerStatus)
        let conditionalSizeRaw = try take(Width.conditionalSizeField)

        // --- Shape validation. Everything below rejects rather than coerces.

        let originCode = origin.trimmingCharacters(in: .whitespaces).uppercased()
        guard isAirportCode(originCode) else {
            throw BCBPParseError.invalidField(name: "origin", value: origin, leg: legIndex)
        }

        let destinationCode = destination.trimmingCharacters(in: .whitespaces).uppercased()
        guard isAirportCode(destinationCode) else {
            throw BCBPParseError.invalidField(name: "destination", value: destination, leg: legIndex)
        }

        let carrierCode = carrier.trimmingCharacters(in: .whitespaces).uppercased()
        guard isCarrierDesignator(carrierCode) else {
            throw BCBPParseError.invalidField(name: "operatingCarrier", value: carrier, leg: legIndex)
        }

        guard let flight = splitFlightNumber(flightNumber) else {
            throw BCBPParseError.invalidField(name: "flightNumber", value: flightNumber, leg: legIndex)
        }

        let julianTrimmed = julian.trimmingCharacters(in: .whitespaces)
        guard julianTrimmed.count == Width.julianDate,
              julianTrimmed.allSatisfy(\.isNumber),
              let julianDay = Int(julianTrimmed),
              (1...366).contains(julianDay) else {
            throw BCBPParseError.invalidField(name: "julianDateOfFlight", value: julian, leg: legIndex)
        }

        // Blank is legal here (an unassigned compartment on a standby coupon),
        // a non-letter is not.
        let compartmentCode = blankToNil(compartment)
        if let compartmentCode, !compartmentCode.allSatisfy({ $0.isLetter || $0.isNumber }) {
            throw BCBPParseError.invalidField(name: "compartmentCode", value: compartment, leg: legIndex)
        }

        var raw = RawLeg(
            operatingCarrierPNR: blankToNil(pnr.trimmingCharacters(in: .whitespaces)),
            origin: originCode,
            destination: destinationCode,
            operatingCarrier: carrierCode,
            flightNumberDigits: flight.digits,
            flightNumberSuffix: flight.suffix,
            julianDayOfFlight: julianDay,
            compartmentCode: compartmentCode?.uppercased(),
            seatNumber: normaliseSeat(seat),
            checkInSequenceNumber: blankToNil(sequence.trimmingCharacters(in: .whitespaces)),
            passengerStatus: blankToNil(status)
        )

        // --- Conditional section, length declared by item 6.

        let conditionalSizeTrimmed = conditionalSizeRaw.trimmingCharacters(in: .whitespaces)
        let conditionalSize: Int
        if conditionalSizeTrimmed.isEmpty {
            conditionalSize = 0
        } else if let size = Int(conditionalSizeTrimmed, radix: 16) {
            conditionalSize = size
        } else {
            throw BCBPParseError.invalidField(
                name: "conditionalSectionSize",
                value: conditionalSizeRaw,
                leg: legIndex
            )
        }

        guard cursor + conditionalSize <= chars.count else {
            throw BCBPParseError.truncatedConditionalSection(
                leg: legIndex,
                declared: conditionalSize,
                available: chars.count - cursor
            )
        }

        var unique: UniqueConditional?
        if conditionalSize > 0 {
            let (parsedUnique, repeated, airlineUse) = parseConditionalSection(
                chars: chars,
                start: cursor,
                length: conditionalSize,
                isFirstLeg: isFirstLeg
            )
            unique = parsedUnique
            raw.airlineNumericCode = repeated.airlineNumericCode
            raw.documentFormSerialNumber = repeated.documentFormSerialNumber
            raw.selecteeIndicator = repeated.selecteeIndicator
            raw.marketingCarrier = repeated.marketingCarrier
            raw.frequentFlyerAirline = repeated.frequentFlyerAirline
            raw.frequentFlyerNumber = repeated.frequentFlyerNumber
            raw.freeBaggageAllowance = repeated.freeBaggageAllowance
            raw.fastTrack = repeated.fastTrack
            raw.airlineUseSection = airlineUse
            cursor += conditionalSize
        }

        return (raw, unique, cursor)
    }

    /// The conditional items that repeat for every leg.
    private struct RepeatedConditional {
        var airlineNumericCode: String?
        var documentFormSerialNumber: String?
        var selecteeIndicator: String?
        var marketingCarrier: String?
        var frequentFlyerAirline: String?
        var frequentFlyerNumber: String?
        var freeBaggageAllowance: String?
        var fastTrack: String?
    }

    /// Reads the variable-length conditional block.
    ///
    /// Nothing in here throws. The conditional section is optional by design and
    /// carriers truncate it at whatever length they care about, so a short or
    /// nonsensical block means "these extras are absent", not "this pass is
    /// invalid". The mandatory section above is where strictness belongs.
    private static func parseConditionalSection(
        chars: [Character],
        start: Int,
        length: Int,
        isFirstLeg: Bool
    ) -> (UniqueConditional?, RepeatedConditional, String?) {

        var reader = FieldReader(chars, from: start, to: start + length)
        var unique: UniqueConditional?
        var repeated = RepeatedConditional()

        if isFirstLeg {
            var parsed = UniqueConditional()

            // Item 8 then item 9. Absent on some carriers' passes; if the
            // marker is missing there is no version and no unique block.
            if reader.peek() == versionMarker {
                _ = reader.take(Width.versionMarker)
                parsed.versionNumber = reader.take(Width.versionNumber).flatMap(blankToNil)

                if let uniqueSize = reader.takeHex(Width.uniqueConditionalSizeField), uniqueSize > 0 {
                    var block = reader.subReader(length: uniqueSize)
                    parsed.passengerDescription = block.take(1).flatMap(blankToNil)
                    parsed.sourceOfCheckIn = block.take(1).flatMap(blankToNil)
                    parsed.sourceOfBoardingPassIssuance = block.take(1).flatMap(blankToNil)
                    parsed.dateOfIssueJulian = block.take(4).flatMap(parseDateOfIssue)
                    parsed.documentType = block.take(1).flatMap(blankToNil)
                    parsed.issuingCarrier = block.take(3).flatMap(blankToNil).map { $0.uppercased() }
                    parsed.baggageTagLicencePlate = block.take(13).flatMap(blankToNil)
                    reader.skip(uniqueSize)
                }
            }
            unique = parsed
        }

        if let repeatedSize = reader.takeHex(Width.repeatedConditionalSizeField), repeatedSize > 0 {
            var block = reader.subReader(length: repeatedSize)
            repeated.airlineNumericCode = block.take(3).flatMap(blankToNil)
            repeated.documentFormSerialNumber = block.take(10).flatMap(blankToNil)
            repeated.selecteeIndicator = block.take(1).flatMap(blankToNil)
            _ = block.take(1) // Item 108, international documentation verification.
            repeated.marketingCarrier = block.take(3).flatMap(blankToNil).map { $0.uppercased() }
            repeated.frequentFlyerAirline = block.take(3).flatMap(blankToNil).map { $0.uppercased() }
            repeated.frequentFlyerNumber = block.take(16).flatMap(blankToNil)
            _ = block.take(1) // Item 89, ID/AD indicator.
            repeated.freeBaggageAllowance = block.take(3).flatMap(blankToNil)
            repeated.fastTrack = block.take(1).flatMap(blankToNil)
            reader.skip(repeatedSize)
        }

        let airlineUse = reader.takeRest().flatMap(blankToNil)
        return (unique, repeated, airlineUse)
    }

    // MARK: - Julian date resolution

    /// The window used to turn a single year digit into a year.
    ///
    /// Ten consecutive years contain exactly one year per last digit, so this
    /// window makes the resolution unambiguous rather than "nearest, and hope".
    /// It is skewed to the past because a boarding pass is issued before it is
    /// scanned: at most a year ahead, up to eight years behind.
    private static let issueYearPastWindow = 8
    private static let issueYearFutureWindow = 1

    /// Resolves item 22, `YDDD`: one digit of year plus day of year.
    static func resolveYearDigitDate(
        yearDigit: Int,
        dayOfYear: Int,
        referenceDate: Date
    ) -> Date? {
        guard (0...9).contains(yearDigit), (1...366).contains(dayOfYear) else { return nil }

        let referenceYear = calendar.component(.year, from: referenceDate)
        let lowerBound = referenceYear - issueYearPastWindow
        let upperBound = referenceYear + issueYearFutureWindow

        for year in lowerBound...upperBound where year % 10 == yearDigit {
            if let date = date(year: year, dayOfYear: dayOfYear) {
                return date
            }
            // Day 366 in a non-leap year. The digit is unambiguous inside the
            // window, so there is no other candidate: the field is wrong.
            return nil
        }
        return nil
    }

    /// The first date with this day of year that falls on or after `anchor`.
    ///
    /// This is the branch used whenever a real year is known from somewhere -
    /// the encoded date of issue, or the previous leg. It is what makes a pass
    /// issued on 28 December for a 5 January flight land in the following year.
    static func earliestDate(dayOfYear: Int, onOrAfter anchor: Date) -> Date? {
        guard (1...366).contains(dayOfYear) else { return nil }
        let anchorYear = calendar.component(.year, from: anchor)

        // Four years covers the worst case: day 366 needs the next leap year.
        for year in anchorYear...(anchorYear + 4) {
            guard let candidate = date(year: year, dayOfYear: dayOfYear) else { continue }
            if candidate >= calendar.startOfDay(for: anchor) {
                return candidate
            }
        }
        return nil
    }

    /// The year that puts this day of year closest to `reference`.
    ///
    /// Used only when the barcode carries no year at all. A December flight
    /// scanned in January resolves to the December just gone, not the one
    /// eleven months away, because the previous year is the nearer candidate.
    static func nearestDate(dayOfYear: Int, to reference: Date) -> Date? {
        guard (1...366).contains(dayOfYear) else { return nil }
        let referenceYear = calendar.component(.year, from: reference)

        // A leap-day-only pass needs a wider net than +/-1 year.
        let candidateYears = [
            referenceYear, referenceYear - 1, referenceYear + 1,
            referenceYear - 2, referenceYear + 2,
            referenceYear - 3, referenceYear + 3,
            referenceYear - 4, referenceYear + 4
        ]

        var best: (date: Date, distance: TimeInterval)?
        for year in candidateYears {
            guard let candidate = date(year: year, dayOfYear: dayOfYear) else { continue }
            let distance = abs(candidate.timeIntervalSince(reference))
            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }
        return best?.date
    }

    /// Midnight UTC on the given day of year, or nil when that day does not
    /// exist in that year (366 outside a leap year).
    static func date(year: Int, dayOfYear: Int) -> Date? {
        guard let january1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let candidate = calendar.date(byAdding: .day, value: dayOfYear - 1, to: january1) else {
            return nil
        }
        // Adding 365 days to 1 January of a non-leap year lands in the next
        // year. Catching that is how day 366 is rejected.
        guard calendar.component(.year, from: candidate) == year else { return nil }
        return candidate
    }

    /// Item 22, `YDDD`.
    private static func parseDateOfIssue(_ raw: String) -> (yearDigit: Int, dayOfYear: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(trimmed)
        guard let yearDigit = Int(String(chars[0])),
              let dayOfYear = Int(String(chars[1...3])),
              (1...366).contains(dayOfYear) else { return nil }
        return (yearDigit, dayOfYear)
    }

    // MARK: - Field helpers

    /// Vision hands back the payload with the odd trailing newline, and some
    /// scanners insert carriage returns. Nothing else is touched: every offset
    /// in this format is counted from character zero, so stripping spaces here
    /// would shift every field after it.
    static func normalisePayload(_ payload: String) -> String {
        String(payload.unicodeScalars.filter { $0 != "\n" && $0 != "\r" && $0 != "\0" })
    }

    private static func isAirportCode(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isLetter && $0.isASCII }
    }

    private static func isCarrierDesignator(_ code: String) -> Bool {
        (2...3).contains(code.count)
            && code.allSatisfy { ($0.isLetter || $0.isNumber) && $0.isASCII }
            && code.contains(where: \.isLetter)
    }

    /// Item 43 is four numerics, right-justified and zero-padded, plus an
    /// optional alpha suffix. Space padding shows up in the wild, so it is
    /// tolerated; anything else is rejected.
    private static func splitFlightNumber(_ raw: String) -> (digits: String, suffix: String?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }

        var digits = ""
        var suffix: String?
        for character in trimmed {
            if character.isNumber, suffix == nil {
                digits.append(character)
            } else if character.isLetter, !digits.isEmpty, suffix == nil {
                suffix = String(character)
            } else {
                return nil
            }
        }
        guard (1...4).contains(digits.count) else { return nil }
        return (digits, suffix)
    }

    /// `012A` -> `12A`, `INF ` -> `INF`, blank -> nil.
    private static func normaliseSeat(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let unpadded = String(trimmed.drop(while: { $0 == "0" }))
        return unpadded.isEmpty ? trimmed : unpadded
    }

    /// `DESMARAIS/LUC` -> `LUC DESMARAIS`.
    private static func displayName(from raw: String) -> String? {
        guard let trimmed = blankToNil(raw) else { return nil }
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return trimmed }

        let surname = parts[0].trimmingCharacters(in: .whitespaces)
        let given = parts[1].trimmingCharacters(in: .whitespaces)
        if surname.isEmpty { return blankToNil(given) }
        if given.isEmpty { return blankToNil(surname) }
        return "\(given) \(surname)"
    }

    /// The `""` versus `nil` trap: a stored empty string defeats every
    /// `?? fallback` downstream because it is not nil.
    private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Fixed-width reader

/// A bounded cursor over the payload characters.
///
/// Every read is bounds-checked and returns nil past the end, which is what
/// lets the conditional section be parsed as far as the carrier chose to encode
/// it without ever reading into the next leg.
private struct FieldReader {
    private let chars: [Character]
    private var offset: Int
    private let end: Int

    init(_ chars: [Character], from: Int, to: Int) {
        self.chars = chars
        self.offset = max(0, from)
        self.end = min(to, chars.count)
    }

    var remaining: Int { max(0, end - offset) }

    func peek() -> Character? {
        offset < end ? chars[offset] : nil
    }

    mutating func take(_ count: Int) -> String? {
        guard count > 0, offset + count <= end else { return nil }
        defer { offset += count }
        return String(chars[offset..<(offset + count)])
    }

    mutating func takeHex(_ count: Int) -> Int? {
        guard let raw = take(count) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        return Int(trimmed, radix: 16)
    }

    mutating func takeRest() -> String? {
        guard remaining > 0 else { return nil }
        defer { offset = end }
        return String(chars[offset..<end])
    }

    mutating func skip(_ count: Int) {
        offset = min(end, offset + count)
    }

    /// A reader over the next `length` characters that does NOT advance this
    /// one - the caller skips explicitly, so a carrier that over-declares a
    /// block size still leaves the outer cursor where the format says it is.
    func subReader(length: Int) -> FieldReader {
        FieldReader(chars, from: offset, to: min(end, offset + length))
    }
}
