// RecordingAudioTimelineTests.swift — REC-004-T03: host-timed chunks to file positions (research D3).
@testable import FrameRecording
import XCTest

final class RecordingAudioTimelineTests: XCTestCase {
    private let origin: UInt64 = 5_000_000_000
    /// ns of a sample position relative to the origin.
    private func ns(_ sample: Int64) -> UInt64 { UInt64(Int64(origin) + sample * 1_000_000_000 / 44_100) }

    func testNothingIsPlacedBeforeTheOrigin() {
        var timeline = RecordingAudioTimeline()
        XCTAssertNil(timeline.place(frames: 441, firstSampleNanoseconds: origin))
    }

    func testChunksStartAtTheirHostTimeAndContinueContiguously() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        XCTAssertEqual(timeline.place(frames: 441, firstSampleNanoseconds: ns(44_100)),
                       .init(skipFrames: 0, startSample: 44_100, frames: 441))
        // 3 ms of stamp jitter: still contiguous.
        XCTAssertEqual(timeline.place(frames: 441, firstSampleNanoseconds: ns(44_541) + 3_000_000),
                       .init(skipFrames: 0, startSample: 44_541, frames: 441))
    }

    func testAudioBeforeTheOriginIsTrimmed() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        // Starts 100 samples before the origin.
        let placement = timeline.place(frames: 441, firstSampleNanoseconds: origin - 100 * 1_000_000_000 / 44_100)
        XCTAssertEqual(placement?.startSample, 0)
        XCTAssertEqual(Double(placement?.skipFrames ?? -9), 100, accuracy: 1)
    }

    func testAGapBeyondTheWindowReanchorsAndIsNotPadded() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        _ = timeline.place(frames: 441, firstSampleNanoseconds: ns(0))
        let later = timeline.place(frames: 441, firstSampleNanoseconds: ns(44_100))   // 1 s later
        XCTAssertEqual(later, .init(skipFrames: 0, startSample: 44_100, frames: 441))
        XCTAssertEqual(timeline.placedFrames, 882, "the gap is not filled")
    }

    func testAnOverlapBeyondTheWindowIsTrimmed() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        _ = timeline.place(frames: 22_050, firstSampleNanoseconds: ns(0))   // up to 22,050
        // Claims to start at 10,000 (12,050 samples overlap, beyond the 4,410 window).
        let placement = timeline.place(frames: 13_000, firstSampleNanoseconds: ns(10_000))
        XCTAssertEqual(placement, .init(skipFrames: 12_050, startSample: 22_050, frames: 950))
    }

    func testEndStopsPlacement() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        timeline.end()
        XCTAssertNil(timeline.place(frames: 441, firstSampleNanoseconds: ns(0)))
    }

    func testTheOriginIsSetOnce() {
        var timeline = RecordingAudioTimeline()
        timeline.setOrigin(nanoseconds: origin)
        timeline.setOrigin(nanoseconds: origin + 1_000_000_000)
        XCTAssertEqual(timeline.originNanoseconds, origin)
    }
}
