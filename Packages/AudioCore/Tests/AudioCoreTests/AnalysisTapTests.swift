// AnalysisTapTests.swift — the optional analysis tap on the normalized ring (ANL-001-T15;
// ANL-001-R9; research ANL-001-D7). projectM's reads must not change whether the tap exists, is
// read, or is never read.
import XCTest
@testable import AudioCore

final class AnalysisTapTests: XCTestCase {
    private func ramp(frames: Int, start: Int = 0) -> [Float] {
        (0..<(frames * 2)).map { Float(start * 2 + $0) }
    }

    private func readAll(_ reader: some NormalizedPCMReader, maxFrames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: maxFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { reader.read(into: $0.baseAddress!, maxFrames: maxFrames) }
        return Array(out[0..<(n * 2)])
    }

    func testDefaultRingHasNoTap() {
        let ring = NormalizedPCMRing()
        XCTAssertNil(ring.analysisTap)
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
        XCTAssertEqual(ring.analysisTapDroppedFrames, 0)
        let data = ramp(frames: 100)
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 100) }
        XCTAssertEqual(ring.availableFrames, 100)
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
        XCTAssertEqual(readAll(ring, maxFrames: 100), data)
        XCTAssertEqual(NormalizedPCMRing.analysisTapDefaultCapacityFrames, 22_050)
    }

    func testTapMirrorsEveryWriteWithoutChangingTheMainRing() throws {
        let tapped = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let plain = NormalizedPCMRing()
        let tap = try XCTUnwrap(tapped.analysisTap)
        var expectedTap: [Float] = []
        for block in 0..<5 {
            let data = ramp(frames: 300, start: block * 300)
            data.withUnsafeBufferPointer {
                tapped.write($0.baseAddress!, frames: 300)
                plain.write($0.baseAddress!, frames: 300)
            }
            expectedTap += data
            // Read the main rings each block (as the renderer does) and only sometimes the tap.
            XCTAssertEqual(readAll(tapped, maxFrames: 4_096), readAll(plain, maxFrames: 4_096), "block \(block)")
        }
        XCTAssertEqual(tapped.analysisTapAvailableFrames, 1_500)
        XCTAssertEqual(readAll(tap, maxFrames: 4_096), expectedTap)
        XCTAssertEqual(tapped.droppedFrames, plain.droppedFrames)
    }

    func testTapHasNoFreshnessRule() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 10_000)
        let tap = try XCTUnwrap(ring.analysisTap)
        let data = ramp(frames: 5_000)
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 5_000) }
        XCTAssertEqual(readAll(tap, maxFrames: 5_000), data, "all 5,000 frames, none skipped")
        XCTAssertEqual(readAll(ring, maxFrames: 5_000).count, NormalizedPCMRing.freshnessFrames * 2, "main ring keeps its rule")
    }

    func testTapOverflowDropsOldestAndLeavesTheMainRingAlone() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 1_000)
        let tap = try XCTUnwrap(ring.analysisTap)
        let first = ramp(frames: 800)
        let second = ramp(frames: 800, start: 800)
        first.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 800) }
        second.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 800) }
        XCTAssertEqual(ring.analysisTapDroppedFrames, 600)
        XCTAssertEqual(readAll(tap, maxFrames: 2_000), Array((first + second)[(600 * 2)...]))
        XCTAssertEqual(ring.overflowDroppedFrames, 0, "the main ring holds 0.5 s and dropped nothing")
        XCTAssertEqual(ring.availableFrames, 1_600)
    }

    func testDiscardAndResetCoverTheTap() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 500)
        let data = ramp(frames: 700)
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 700) }
        XCTAssertEqual(ring.analysisTapDroppedFrames, 200)
        ring.discardBuffered()
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
        XCTAssertEqual(ring.availableFrames, 0)
        XCTAssertEqual(ring.analysisTapDroppedFrames, 200, "discard keeps counters")
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 700) }
        XCTAssertEqual(ring.analysisTapDroppedFrames, 400)
        ring.reset()
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
        XCTAssertEqual(ring.analysisTapDroppedFrames, 0, "reset restarts counters")
        let tail = ramp(frames: 10, start: 7)
        tail.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 10) }
        let tap = try XCTUnwrap(ring.analysisTap)
        XCTAssertEqual(readAll(tap, maxFrames: 100), tail)
    }

    func testNonPositiveCapacityMeansNoTap() {
        XCTAssertNil(NormalizedPCMRing(analysisTapCapacityFrames: 0).analysisTap)
        XCTAssertNil(NormalizedPCMRing(analysisTapCapacityFrames: -5).analysisTap)
    }
}
