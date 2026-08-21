//
//  PhotoSamplingTests.swift
//  SkyLineTests
//
//  The fetch cap used to combine `fetchLimit` with an ascending sort, which
//  keeps the EARLIEST n assets. A trip over the cap therefore lost its final
//  days outright, and lost them silently — the caller could not tell a complete
//  result from an amputated one.
//
//  These tests pin the two properties that fix has to hold: coverage spans the
//  whole window, and the caller is told when it is looking at a sample.
//

import Testing
import Foundation
@testable import SkyLine

@Suite("Photo sampling")
struct PhotoSamplingTests {

    /// Mirrors the stride arithmetic in `PhotoAssetFetcher.fetchPoints`.
    private func stride(forCount count: Int, limit: Int) -> Int {
        count > limit ? Int(ceil(Double(count) / Double(limit))) : 1
    }

    private func sampledIndices(count: Int, limit: Int) -> [Int] {
        let s = stride(forCount: count, limit: limit)
        return (0..<count).filter { s == 1 || $0 % s == 0 }
    }

    @Test("Under the cap, nothing is dropped")
    func underCapKeepsEverything() {
        #expect(stride(forCount: 500, limit: 6000) == 1)
        #expect(sampledIndices(count: 500, limit: 6000).count == 500)
    }

    @Test("Over the cap, the result stays within it")
    func overCapRespectsLimit() {
        for count in [6001, 9000, 20_000, 60_000] {
            let kept = sampledIndices(count: count, limit: 6000).count
            #expect(kept <= 6000, "\(count) assets sampled to \(kept), over the cap")
        }
    }

    @Test("Sampling spans the whole window rather than one end")
    func samplingSpansTheWindow() {
        // The actual regression: with a fetch limit the kept set was 0..<6000,
        // so the last days of a long trip vanished. An even stride must keep
        // something from the final decile.
        let count = 20_000
        let kept = sampledIndices(count: count, limit: 6000)

        let lastDecile = Int(Double(count) * 0.9)
        #expect(kept.contains { $0 >= lastDecile },
                "nothing kept from the end of the window - the old truncation bug")

        let firstDecile = Int(Double(count) * 0.1)
        #expect(kept.contains { $0 <= firstDecile })

        // Coverage should be roughly uniform, not clumped at either end.
        let firstHalf = kept.filter { $0 < count / 2 }.count
        let secondHalf = kept.count - firstHalf
        let skew = Double(abs(firstHalf - secondHalf)) / Double(kept.count)
        #expect(skew < 0.05, "sampling is skewed to one half of the window")
    }

    @Test("A sampled result reports that it was sampled")
    func outcomeAdvertisesSampling() {
        // Silent sampling reads identically to complete coverage, which is what
        // made the original bug invisible.
        let complete = PhotoFetchOutcome(
            points: [], totalInRange: 0, screenshotsExcluded: 0,
            recoveredFromEXIF: 0, sampledOut: 0)
        #expect(complete.wasSampled == false)

        let sampled = PhotoFetchOutcome(
            points: [], totalInRange: 6000, screenshotsExcluded: 0,
            recoveredFromEXIF: 0, sampledOut: 14_000)
        #expect(sampled.wasSampled == true)
        #expect(sampled.sampledOut == 14_000)
    }

    @Test("Edge counts do not trap")
    func edgeCounts() {
        #expect(sampledIndices(count: 0, limit: 6000).isEmpty)
        #expect(sampledIndices(count: 1, limit: 6000).count == 1)
        #expect(sampledIndices(count: 6000, limit: 6000).count == 6000)
        #expect(sampledIndices(count: 6001, limit: 6000).count <= 6000)
    }
}
