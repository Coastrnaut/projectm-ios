// ShuffleGeneratorTests.swift — the documented generator behind the shuffled order (AUD-005-T02;
// research AUD-005-D1). Golden values come from the published SplitMix64 and FNV-1a 64 algorithms,
// computed independently (`.build/scratch/oracle.py` during AUD-005). Foundation only, Linux too.
import Foundation
import XCTest
@testable import CaptureKit

final class ShuffleGeneratorTests: XCTestCase {
    func testSplitMix64MatchesThePublishedAlgorithm() {
        var generator = SplitMix64(seed: 42)
        XCTAssertEqual(generator.next(), 0xbdd7_3226_2feb_6e95)
        XCTAssertEqual(generator.next(), 0x28ef_e333_b266_f103)
        XCTAssertEqual(generator.next(), 0x4752_6757_130f_9f52)
    }

    func testBoundedStaysInRange() {
        var generator = SplitMix64(seed: 7)
        for bound in [1, 2, 3, 5, 1000] {
            for _ in 0..<50 { XCTAssertLessThan(generator.bounded(bound), bound) }
        }
    }

    func testShuffleIsAReproduciblePermutation() {
        let ids = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(ShuffleGenerator.shuffle([String](), seed: 1), [])
        XCTAssertEqual(ShuffleGenerator.shuffle(["a"], seed: 1), ["a"])
        let first = ShuffleGenerator.shuffle(ids, seed: 1)
        XCTAssertEqual(first.sorted(), ids)
        XCTAssertEqual(ShuffleGenerator.shuffle(ids, seed: 1), first, "the same seed gives the same order")
        XCTAssertNotEqual(ShuffleGenerator.shuffle(ids, seed: 2), first)
    }

    func testCycleSeedsDiffer() {
        let seeds = Set((0..<10).map { ShuffleGenerator.cycleSeed(42, cycle: $0) })
        XCTAssertEqual(seeds.count, 10)
        XCTAssertEqual(ShuffleGenerator.cycleSeed(42, cycle: 3), ShuffleGenerator.cycleSeed(42, cycle: 3))
    }

    func testFNV1a64MatchesThePublishedValue() {
        XCTAssertEqual(ShuffleGenerator.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(ShuffleGenerator.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
    }
}
