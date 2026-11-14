// RecordingTapTests.swift — REC-004-T04: the normalized ring's recording tap (contract C2).
import XCTest
@testable import AudioCore

final class RecordingTapTests: XCTestCase {
    private func frames(_ count: Int, value: Float) -> [Float] { [Float](repeating: value, count: count * 2) }

    private func drain(_ ring: NormalizedPCMRing, max: Int = 22_050) -> ([Float], RecordingTapChunk) {
        var out = [Float](repeating: 0, count: max * 2)
        let chunk = out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> RecordingTapChunk in
            ring.recordingTap.read(into: p.baseAddress!, maxFrames: max)
        }
        return (Array(out.prefix(chunk.frames * 2)), chunk)
    }

    func testADisarmedTapReceivesNothing() {
        let ring = NormalizedPCMRing()
        ring.write(frames(441, value: 0.5), frames: 441)
        XCTAssertFalse(ring.recordingTap.isArmed)
        XCTAssertEqual(drain(ring).1.frames, 0)
    }

    func testAnArmedTapGetsTheSamplesTheMainRingGets() {   // REC-004-R12: the normalized audio itself
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        ring.write(frames(441, value: 0.25), frames: 441)
        let (samples, chunk) = drain(ring)
        XCTAssertEqual(chunk.frames, 441)
        XCTAssertTrue(samples.allSatisfy { (s: Float) -> Bool in s == 0.25 })
        XCTAssertEqual(ring.availableFrames, 441, "projectM's ring is untouched by the tap's reader")
    }

    func testTheChunkIsDatedByItsNewestWrite() {
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        let before = MonotonicClock.nowNanoseconds()
        ring.write(frames(441, value: 0.1), frames: 441)
        let after = MonotonicClock.nowNanoseconds()
        let chunk = drain(ring).1
        let span = UInt64((440.0 * 1e9 / 44_100).rounded())
        XCTAssertGreaterThanOrEqual(chunk.firstSampleNanoseconds + span, before)
        XCTAssertLessThanOrEqual(chunk.firstSampleNanoseconds + span, after)
    }

    func testANewSessionDisarmsBeforeItsAudio() {   // REC-004-R5
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        ring.write(frames(100, value: 0.3), frames: 100)
        ring.reset()
        ring.write(frames(100, value: 0.9), frames: 100)
        XCTAssertFalse(ring.recordingTap.isArmed)
        XCTAssertEqual(drain(ring).1.frames, 0, "the old audio is dropped and the new session's never arrives")

        ring.armRecordingTap()
        ring.resetForHandoff()
        ring.write(frames(100, value: 0.9), frames: 100)
        XCTAssertFalse(ring.recordingTap.isArmed)
        XCTAssertEqual(drain(ring).1.frames, 0)
    }

    func testASeekDrainsButStaysArmed() {
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        ring.write(frames(100, value: 0.3), frames: 100)
        ring.discardBuffered()
        XCTAssertTrue(ring.recordingTap.isArmed)
        ring.write(frames(50, value: 0.4), frames: 50)
        XCTAssertEqual(drain(ring).1.frames, 50)
    }

    func testOverflowDropsOldestAndCounts() {   // REC-004-R8: bounded, never blocks
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        let chunk = frames(1_024, value: 0.2)
        for _ in 0..<24 { ring.write(chunk, frames: 1_024) }   // 24,576 > 22,050
        XCTAssertEqual(ring.recordingTap.droppedFrames, 24_576 - 22_050)
        XCTAssertEqual(drain(ring, max: 30_000).1.frames, 22_050)
        ring.armRecordingTap()
        XCTAssertEqual(ring.recordingTap.droppedFrames, 0, "arming restarts the count")
    }

    func testDisarmEmptiesTheTap() {
        let ring = NormalizedPCMRing()
        ring.armRecordingTap()
        ring.write(frames(100, value: 0.3), frames: 100)
        ring.disarmRecordingTap()
        XCTAssertEqual(drain(ring).1.frames, 0)
    }
}
