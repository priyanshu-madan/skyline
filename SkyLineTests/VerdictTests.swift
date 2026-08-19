//
//  VerdictTests.swift
//  SkyLineTests
//
//  Verdict decoding has a specific, expensive failure mode behind it. In
//  commit d962e9e two DataSource cases were removed and the synthesised
//  Codable conformance began throwing on the old raw values still sitting in
//  CloudKit. A throw inside a [Flight] blob discarded the entire blob, so the
//  app silently showed an empty flight list and an empty globe.
//
//  Verdict carries the same risk - it is stored per visit, inside arrays, and
//  its raw values may drift. These tests exist to keep that from happening a
//  second time.
//

import Testing
import Foundation
@testable import SkyLine

@Suite("Verdict decoding")
struct VerdictDecodingTests {

    private func decode(_ json: String) throws -> Verdict {
        try JSONDecoder().decode(Verdict.self, from: Data(json.utf8))
    }

    @Test("Round-trips its own encoding", arguments: Verdict.allCases)
    func roundTrip(verdict: Verdict) throws {
        let data = try JSONEncoder().encode(verdict)
        #expect(try JSONDecoder().decode(Verdict.self, from: data) == verdict)
    }

    @Test("An unknown raw value decodes instead of throwing")
    func unknownRawValueDoesNotThrow() throws {
        // The whole point. If this ever throws, one drifted string takes every
        // visit in the enclosing array with it.
        let decoded = try decode("\"enthusiastically_ambivalent\"")
        #expect(decoded == .fine)
    }

    @Test("A verdict inside an array survives a corrupt sibling")
    func corruptSiblingDoesNotDestroyTheArray() throws {
        // This models the real failure: not one bad value, but one bad value
        // costing you all the good ones next to it.
        let json = "[\"worth_it\", \"not_a_verdict\", \"skip\"]"
        let decoded = try JSONDecoder().decode([Verdict].self, from: Data(json.utf8))

        #expect(decoded.count == 3)
        #expect(decoded[0] == .worthIt)
        #expect(decoded[2] == .skip, "a good value after a bad one must survive")
    }

    @Test("Wrong JSON types degrade instead of throwing")
    func wrongTypeDegrades() throws {
        #expect(try decode("123") == .fine)
        #expect(try decode("null") == .fine)
        #expect(try decode("true") == .fine)
    }

    @Test("Lenient parsing accepts the spellings that actually occur")
    func lenientAcceptsRealVariants() {
        #expect(Verdict.lenient("worth_it") == .worthIt)
        #expect(Verdict.lenient("worthIt") == .worthIt)
        #expect(Verdict.lenient("  WORTH IT  ") == .worthIt)
        #expect(Verdict.lenient("Great") == .worthIt)
        #expect(Verdict.lenient("okay") == .fine)
        #expect(Verdict.lenient("AVOID") == .skip)
    }

    @Test("Lenient parsing reports absence as nil, not as a verdict")
    func lenientDistinguishesUnratedFromRated() {
        // nil means "not rated yet", which is a real state in the deck - the
        // user is allowed to defer. It must never silently become .fine.
        #expect(Verdict.lenient(nil) == nil)
        #expect(Verdict.lenient("") == nil)
        #expect(Verdict.lenient("   ") == nil)
        #expect(Verdict.lenient("completely unrecognised") == nil)
    }
}

@Suite("Verdict presentation")
struct VerdictPresentationTests {

    @Test("Every verdict has a distinct symbol silhouette")
    func distinctSilhouettes() {
        // Colour alone fails for roughly 8% of men, and fails entirely in a
        // greyscale screenshot - which is exactly how a shared guide often
        // gets passed around.
        let symbols = Set(Verdict.allCases.map(\.systemImage))
        #expect(symbols.count == Verdict.allCases.count)

        let outlines = Set(Verdict.allCases.map(\.systemImageOutline))
        #expect(outlines.count == Verdict.allCases.count)
    }

    @Test("Every verdict has a distinct globe colour")
    func distinctGlobeColors() {
        let colors = Set(Verdict.allCases.map(\.globeHexColor))
        #expect(colors.count == Verdict.allCases.count)
        #expect(!colors.contains(Verdict.unratedGlobeHexColor),
                "unrated places must be visually separable from rated ones")
    }

    @Test("An unrated place gets the neutral globe colour")
    func unratedGlobeColor() {
        #expect(Verdict.globeHexColor(for: nil) == Verdict.unratedGlobeHexColor)
        #expect(Verdict.globeHexColor(for: .worthIt) == Verdict.worthIt.globeHexColor)
    }

    @Test("Sort order puts the recommendable first")
    func sortRankOrdersBestFirst() {
        let sorted = Verdict.allCases.sorted { $0.sortRank < $1.sortRank }
        #expect(sorted == [.worthIt, .fine, .skip])
    }

    @Test("Accessibility labels are distinct and non-empty")
    func accessibilityLabels() {
        let labels = Set(Verdict.allCases.map(\.accessibilityLabel))
        #expect(labels.count == Verdict.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }
}
