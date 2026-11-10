// Task T058: the normalized ring (research R-06): capacity 22,050 stereo frames (0.5 s at
// 44.1 kHz) with drop-oldest overflow, the freshness rule (a backlog over 50 ms is skipped to the
// newest 50 ms and counted as dropped), and the underrun policy (an empty ring reads 0 frames).
import XCTest
@testable import AudioCore

final class NormalizedReaderTests: XCTestCase {
    /// Writes `frames` stereo frames numbered from `first`: L = n, R = -n.
    private func write(_ ring: NormalizedPCMRing, frames: Int, first: Int = 0) {
        var samples = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            samples[2 * f] = Float(first + f)
            samples[2 * f + 1] = -Float(first + f)
        }
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: frames) }
    }

    private func read(_ reader: some NormalizedPCMReader, maxFrames: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: maxFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { reader.read(into: $0.baseAddress!, maxFrames: maxFrames) }
        return Array(out.prefix(n * 2))
    }

    func testFormatConstants() {
        XCTAssertEqual(NormalizedPCMRing.sampleRate, 44_100)
        XCTAssertEqual(NormalizedPCMRing.channelCount, 2)
        XCTAssertEqual(NormalizedPCMRing.capacityFrames, 22_050)   // 0.5 s
        XCTAssertEqual(NormalizedPCMRing.freshnessFrames, 2_205)   // 50 ms
    }

    func testCapacityIs22050StereoFramesAndOverflowDropsOldest() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 30_000)
        XCTAssertEqual(ring.availableFrames, 22_050)
        XCTAssertEqual(ring.overflowDroppedFrames, 30_000 - 22_050)
        XCTAssertEqual(ring.freshnessDroppedFrames, 0)
    }

    func testEmptyRingReadsZero() {
        let ring = NormalizedPCMRing()
        XCTAssertEqual(read(ring, maxFrames: 1024), [])
        XCTAssertEqual(ring.droppedFrames, 0)
    }

    func testBacklogOver50msSkipsToNewest50msAndCountsDropped() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 10_000)
        let out = read(ring, maxFrames: 4_096)
        XCTAssertEqual(out.count, 2_205 * 2, "only the newest 50 ms remain")
        XCTAssertEqual(out.first, Float(10_000 - 2_205), "the oldest frames were skipped")
        XCTAssertEqual(out[1], -Float(10_000 - 2_205), "frames stay aligned (L, R)")
        XCTAssertEqual(out.last, -Float(9_999))
        XCTAssertEqual(ring.freshnessDroppedFrames, 10_000 - 2_205)
        XCTAssertEqual(ring.droppedFrames, 10_000 - 2_205)
        XCTAssertEqual(read(ring, maxFrames: 4_096), [])
    }

    func testBacklogOfExactly50msIsNotSkipped() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 2_205)
        let out = read(ring, maxFrames: 4_096)
        XCTAssertEqual(out.count, 2_205 * 2)
        XCTAssertEqual(out.first, 0)
        XCTAssertEqual(ring.freshnessDroppedFrames, 0)
    }

    func testReadHonorsMaxFramesAndKeepsOrder() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 1_000)
        XCTAssertEqual(read(ring, maxFrames: 3), [0, 0, 1, -1, 2, -2])
        let rest = read(ring, maxFrames: 2_000)
        XCTAssertEqual(rest.count, 997 * 2)
        XCTAssertEqual(rest.first, 3)
        XCTAssertEqual(ring.droppedFrames, 0)
    }

    func testFreshnessIsCheckedAtEachRead() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 2_000)
        _ = read(ring, maxFrames: 1_000)                  // 1,000 left: under 50 ms
        write(ring, frames: 3_000, first: 2_000)          // backlog 4,000 frames
        let out = read(ring, maxFrames: 10)
        XCTAssertEqual(out.first, Float(5_000 - 2_205))
        XCTAssertEqual(ring.freshnessDroppedFrames, 4_000 - 2_205)
    }

    func testResetEmptiesTheRingAndCounters() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 30_000)
        _ = read(ring, maxFrames: 10)
        ring.reset()
        XCTAssertEqual(ring.availableFrames, 0)
        XCTAssertEqual(ring.droppedFrames, 0)
        XCTAssertEqual(read(ring, maxFrames: 10), [])
    }

    func testReaderIsUsableThroughTheProtocol() {
        let ring = NormalizedPCMRing()
        write(ring, frames: 4)
        let reader: any NormalizedPCMReader = ring
        XCTAssertEqual(read(reader, maxFrames: 2), [0, 0, 1, -1])
    }
}
