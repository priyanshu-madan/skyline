//
//  BoardingPassPrintedFields.swift
//  SkyLine
//
//  Reads the handful of boarding pass fields that the IATA barcode does NOT
//  encode, out of on-device text recognition.
//
//  BCBP (see `BCBPParser`) carries passenger, PNR, route, carrier, flight
//  number, date, cabin, seat, sequence and status. It carries no gate, no
//  terminal, no clock times and no display names - those are printed on the
//  card and nowhere else. Everything in this file is therefore a heuristic over
//  OCR output, and it is kept strictly separate from the barcode parse so that
//  a guess can never be mistaken for a checksummed value.
//
//  Pure string work, no Vision types, so the whole thing is unit-testable.
//

import Foundation

/// The printed-only fields, all optional, all heuristic.
struct BoardingPassPrintedFields: Equatable {
    var gate: String?
    var terminal: String?
    /// `HH:mm`, 24-hour.
    var boardingTime: String?
    /// `HH:mm`, 24-hour.
    var departureTime: String?
    /// `HH:mm`, 24-hour.
    var arrivalTime: String?
    var airlineName: String?
    var departureCity: String?
    var arrivalCity: String?

    var isEmpty: Bool {
        gate == nil && terminal == nil && boardingTime == nil && departureTime == nil
            && arrivalTime == nil && airlineName == nil && departureCity == nil && arrivalCity == nil
    }
}

enum BoardingPassPrintedFieldReader {

    // MARK: - Labels
    //
    // Ordered most specific first. `GATE CLOSES` has to beat `GATE`, and
    // `BOARDING TIME` has to beat `TIME`, or the wrong value wins the field.

    private static let boardingTimeLabels = [
        "BOARDING TIME", "GATE CLOSES", "GATE CLOSE", "BOARDING", "BOARDS", "BRDG"
    ]
    private static let departureTimeLabels = [
        "DEPARTURE TIME", "DEPARTS", "DEPARTURE", "DEPART", "ETD", "DEP TIME", "DEP"
    ]
    private static let arrivalTimeLabels = [
        "ARRIVAL TIME", "ARRIVES", "ARRIVAL", "ARRIVE", "ETA", "ARR TIME", "ARR"
    ]
    private static let gateLabels = ["BOARDING GATE", "GATE", "GTE"]
    private static let terminalLabels = ["TERMINAL", "TERM"]

    /// Words that make a short line an airline name rather than a city or a
    /// piece of furniture on the card.
    private static let airlineTokens: Set<String> = [
        "AIRLINES", "AIRLINE", "AIRWAYS", "AIR", "AVIATION", "JET", "JETS",
        "EXPRESS", "WINGS", "AEROLINEAS", "AIRLINK"
    ]

    /// Lines carrying one of these never describe the operating carrier.
    private static let airlineExclusions = [
        "AIRPORT", "AIRSIDE", "AIR MILES", "MAINTAIN", "AIRLINE USE"
    ]

    private static let terminalWords: Set<String> = [
        "NORTH", "SOUTH", "EAST", "WEST", "MAIN", "INTERNATIONAL", "DOMESTIC", "CENTRAL"
    ]

    // MARK: - Entry point

    /// Pull the printed-only fields out of recognised text.
    ///
    /// - Parameters:
    ///   - lines: recognised text, one entry per line, in reading order.
    ///   - originCode: the IATA origin from the barcode, when known. Supplying
    ///     it is what makes city extraction reliable: the city is looked up
    ///     next to its own code instead of guessed from line position.
    ///   - destinationCode: as above, for the arrival city.
    static func extract(
        from lines: [String],
        originCode: String? = nil,
        destinationCode: String? = nil
    ) -> BoardingPassPrintedFields {

        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fields = BoardingPassPrintedFields()

        for (index, line) in cleaned.enumerated() {
            let upper = line.uppercased()

            // Times first. `GATE CLOSES 14:05` must not be read as gate "14".
            if fields.boardingTime == nil,
               let value = value(forAnyLabel: boardingTimeLabels, at: index, in: cleaned, validate: time) {
                fields.boardingTime = value
                continue
            }
            if fields.departureTime == nil,
               let value = value(forAnyLabel: departureTimeLabels, at: index, in: cleaned, validate: time) {
                fields.departureTime = value
                continue
            }
            if fields.arrivalTime == nil,
               let value = value(forAnyLabel: arrivalTimeLabels, at: index, in: cleaned, validate: time) {
                fields.arrivalTime = value
                continue
            }
            if fields.gate == nil,
               !upper.contains("CLOSE"),
               let value = value(forAnyLabel: gateLabels, at: index, in: cleaned, validate: gate) {
                fields.gate = value
                continue
            }
            if fields.terminal == nil,
               let value = value(forAnyLabel: terminalLabels, at: index, in: cleaned, validate: terminal) {
                fields.terminal = value
                continue
            }
            if fields.airlineName == nil, let value = airlineName(in: line) {
                fields.airlineName = value
                continue
            }
        }

        if let originCode {
            fields.departureCity = city(forCode: originCode, in: cleaned)
        }
        if let destinationCode {
            fields.arrivalCity = city(forCode: destinationCode, in: cleaned)
        }

        return fields
    }

    // MARK: - Label matching

    /// Looks for `label` on `lines[index]` and returns the first candidate that
    /// `validate` accepts, checking the rest of the same line before the line
    /// below it. Boarding passes print labels both ways round.
    private static func value(
        forAnyLabel labels: [String],
        at index: Int,
        in lines: [String],
        validate: (String) -> String?
    ) -> String? {
        let upper = lines[index].uppercased()

        for label in labels {
            guard let range = upper.range(of: label) else { continue }

            // The label has to be a whole word, or `ARR` fires on `ARRANGE`
            // and `DEP` on `DEPOSIT`.
            guard isWordBoundary(upper, range: range) else { continue }

            let remainder = String(upper[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :.-\u{2013}\u{2014}"))
            if let value = validate(remainder) { return value }

            if index + 1 < lines.count, let value = validate(lines[index + 1].uppercased()) {
                return value
            }
        }
        return nil
    }

    private static func isWordBoundary(_ string: String, range: Range<String.Index>) -> Bool {
        if range.lowerBound > string.startIndex {
            let before = string[string.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < string.endIndex {
            let after = string[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }

    // MARK: - Value validators

    /// Accepts `14:25`, `14.25`, `1425`, `2:25 PM`. Returns `HH:mm`.
    ///
    /// Bare four-digit times are only reached through a time label, never by
    /// scanning the card, because `1425` is also a flight number and a fare
    /// basis and a sequence number.
    static func time(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let meridiem: String?
        if let match = trimmed.range(of: #"\b(AM|PM)\b"#, options: [.regularExpression, .caseInsensitive]) {
            meridiem = trimmed[match].uppercased()
        } else {
            meridiem = nil
        }

        var hour: Int?
        var minute: Int?

        if let match = trimmed.range(of: #"\b([01]?[0-9]|2[0-3])[:.]([0-5][0-9])\b"#, options: .regularExpression) {
            let parts = trimmed[match].split(whereSeparator: { $0 == ":" || $0 == "." })
            hour = Int(parts[0])
            minute = Int(parts[1])
        } else if let match = trimmed.range(of: #"(?<![0-9])([01][0-9]|2[0-3])([0-5][0-9])(?![0-9])"#, options: .regularExpression) {
            let digits = Array(trimmed[match])
            hour = Int(String(digits[0...1]))
            minute = Int(String(digits[2...3]))
        }

        guard var resolvedHour = hour, let resolvedMinute = minute else { return nil }

        if meridiem == "PM", resolvedHour < 12 { resolvedHour += 12 }
        if meridiem == "AM", resolvedHour == 12 { resolvedHour = 0 }
        guard (0...23).contains(resolvedHour) else { return nil }

        return String(format: "%02d:%02d", resolvedHour, resolvedMinute)
    }

    /// Matches the app's own `gatePattern`, `^[A-Z]?[0-9]{1,3}[A-Z]?$`, so a
    /// scanned value never fails the edit form's validation.
    static func gate(_ candidate: String) -> String? {
        let token = firstToken(in: candidate)
        guard let token, token.count <= 4 else { return nil }
        guard token.range(of: #"^[A-Z]?[0-9]{1,3}[A-Z]?$"#, options: .regularExpression) != nil else { return nil }
        guard token.contains(where: \.isNumber) else { return nil }
        return token
    }

    static func terminal(_ candidate: String) -> String? {
        guard let token = firstToken(in: candidate) else { return nil }
        if terminalWords.contains(token) { return token }
        guard token.count <= 3, token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        // `T` alone, or `TERMINAL` split badly by OCR, is not a terminal.
        guard token.contains(where: \.isNumber) || token.count > 1 else { return nil }
        return token
    }

    private static func firstToken(in candidate: String) -> String? {
        let separators = CharacterSet(charactersIn: " \t:,-\u{2013}\u{2014}/|")
        let token = candidate
            .uppercased()
            .components(separatedBy: separators)
            .first(where: { !$0.isEmpty })
        return token
    }

    // MARK: - Display names

    /// A short, digit-free line carrying an airline word.
    ///
    /// Deliberately conservative. Getting this wrong writes a wrong airline
    /// onto a saved flight; getting nothing leaves the caller free to fall back
    /// to the barcode's carrier designator, which is always correct.
    static func airlineName(in line: String) -> String? {
        let upper = line.uppercased()
        guard upper.count <= 30 else { return nil }
        guard !upper.contains(where: \.isNumber) else { return nil }
        for exclusion in airlineExclusions where upper.contains(exclusion) { return nil }

        let words = upper
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard words.count >= 1, words.count <= 4 else { return nil }
        guard words.contains(where: { airlineTokens.contains($0) }) else { return nil }

        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The city printed next to a known IATA code.
    ///
    /// Anchoring on the code from the barcode is what keeps this honest: it
    /// never has to decide which of two city names is the origin.
    static func city(forCode code: String, in lines: [String]) -> String? {
        let target = code.uppercased()
        guard target.count == 3 else { return nil }

        for (index, line) in lines.enumerated() {
            let upper = line.uppercased()
            guard let range = upper.range(of: target), isWordBoundary(upper, range: range) else { continue }

            var remainder = upper
            remainder.removeSubrange(range)
            let candidate = remainder.trimmingCharacters(
                in: CharacterSet(charactersIn: " ()[]:-\u{2013}\u{2014}\u{2192}>/,.")
            )

            if let city = cityName(candidate, excluding: target) {
                // Preserve the original casing of the source line where possible.
                return originalCasing(of: city, in: line) ?? city
            }

            // `MCT` on its own line, city on the line below it.
            if candidate.isEmpty, index + 1 < lines.count,
               let city = cityName(lines[index + 1].uppercased(), excluding: target) {
                return originalCasing(of: city, in: lines[index + 1]) ?? city
            }
        }
        return nil
    }

    private static func cityName(_ candidate: String, excluding code: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard (2...30).contains(trimmed.count) else { return nil }
        guard !trimmed.contains(where: \.isNumber) else { return nil }
        guard trimmed != code else { return nil }

        // A remainder that still holds another three-letter code is a route
        // line - `MCT -> ZRH` - not a city name.
        if trimmed.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) != nil,
           trimmed.count <= 3 {
            return nil
        }
        let words = trimmed.components(separatedBy: CharacterSet(charactersIn: " -"))
            .filter { !$0.isEmpty }
        guard words.count <= 4 else { return nil }
        guard words.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "'" || $0 == "." } }) else { return nil }
        // Reject the case where the "city" is just a second airport code.
        if words.count == 1, words[0].count == 3, words[0] == words[0].uppercased(),
           trimmed.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil {
            return nil
        }
        return trimmed
    }

    /// Finds the upper-cased match back in the source line so `Muscat` is not
    /// returned as `MUSCAT`.
    private static func originalCasing(of value: String, in source: String) -> String? {
        // Searched case-insensitively in the SOURCE rather than by offsetting
        // into an uppercased copy: uppercasing can change a string's length
        // (German sharp s becomes two characters) and shift every index after it.
        guard let range = source.range(of: value, options: [.caseInsensitive]) else { return nil }
        return String(source[range])
    }
}
