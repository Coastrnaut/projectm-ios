// MED-002-T06: the playback clock, the bounded decode queue and the limits with a fake reader and a
// fake clock (MED-002-R9 to R11, S1, S2). Plain Swift: runs in the Linux shape too. No wall-clock
// assertion: waits are ceilings for a slow shared Mac.
import CameraLayer
import Foundation
import VideoLayer
import XCTest

/// 60 pictures at 30 fps (2 s); each picture is its index in the file.
final class FakeVideoReader: VideoFrameReading {
    static let frameCount = 60
    static let duration: Int64 = 2_000_000_000
    static func pts(_ k: Int) -> Int64 { Int64(k) * 1_000_000_000 / 30 }

    let failAt: Int?
    let openError: VideoImportError?
    let empty: Bool
    private var position = 0
    private var isOpen = false

    init(failAt: Int? = nil, openError: VideoImportError? = nil, empty: Bool = false) {
        self.failAt = failAt
        self.openError = openError
        self.empty = empty
    }

    func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo {
        if let openError { throw openError }
        position = Int(startNanoseconds * 30 / 1_000_000_000)
        isOpen = true
        return VideoTrackInfo(width: 64, height: 48, rotation: .none, frameRate: 30, durationNanoseconds: Self.duration, codec: .h264)
    }

    func next() throws(VideoImportError) -> (pts: Int64, frame: Int)? {
        guard isOpen, !empty, position < Self.frameCount else { return nil }
        if position == failAt { throw .damaged }
        defer { position += 1 }
        return (Self.pts(position), position)
    }

    func close() { isOpen = false }
}

final class VideoPipelineTests: XCTestCase {
    private func pipeline(_ make: @escaping @Sendable () -> FakeVideoReader = { FakeVideoReader() }) -> VideoDecodePipeline<FakeVideoReader> {
        VideoDecodePipeline<FakeVideoReader>(capacity: 3, makeReader: make)
    }

    /// The global picture index (loops × 60 + index) a taken frame stands for.
    private func globalIndex(_ frame: TimedFrame<Int>) -> Int {
        Int(frame.presentationNanoseconds / FakeVideoReader.duration) * FakeVideoReader.frameCount + frame.frame
    }

    // MARK: Clock (R9)

    func testClockStartsAtZeroAndAdvancesByPresentationSteps() {
        var clock = VideoPlaybackClock()
        XCTAssertEqual(clock.advance(to: 5_000_000_000), 0, "the first frame is playback time 0")
        XCTAssertEqual(clock.advance(to: 5_016_666_667), 16_666_667)
        XCTAssertEqual(clock.advance(to: 5_216_666_667), 216_666_667, "a 200 ms hitch is kept in full (intended rate)")
        XCTAssertEqual(clock.advance(to: 5_100_000_000), 216_666_667, "time never runs backwards")
        XCTAssertEqual(clock.advance(to: 5_233_333_334), 233_333_334, "a backwards time is not the new base")
        XCTAssertEqual(clock.advance(to: 15_000_000_000), 233_333_334, "a gap over 1 s (pause, background) adds nothing")
        XCTAssertEqual(clock.advance(to: 15_033_333_333), 266_666_667, "and playback continues from there")
        XCTAssertEqual(clock.advance(to: 16_033_333_333), 1_266_666_667, "exactly 1 s still advances")
        clock.forgetPresentation()
        XCTAssertEqual(clock.advance(to: 1), 1_266_666_667, "after a stop, the next frame continues at the same time")
        clock.reset()
        XCTAssertEqual(clock.playbackNanoseconds, 0)
    }

    // MARK: Frame for time (S1)

    func testFrameForTimeIsExactOverTwoLoops() {
        let p = pipeline()
        p.start(atNanoseconds: 0)
        var clock = VideoPlaybackClock()
        let start: UInt64 = 7_000_000_000
        for i in 0..<130 {
            // 5 ms into picture i's slot; the clock turns presentation time into playback time.
            let t = Int64(i) * 1_000_000_000 / 30 + 5_000_000
            let playback = clock.advance(to: start + UInt64(i == 0 ? 0 : t))
            XCTAssertTrue(p.waitUntilIdle(timeout: 5))
            if i == 0 { XCTAssertEqual(playback, 0) } else { XCTAssertEqual(playback, t) }
            guard let frame = p.take(upTo: playback) else { return XCTFail("no picture at step \(i)") }
            XCTAssertEqual(globalIndex(frame), i, "playback \(playback) ns shows picture ⌊t × 30⌋")
            XCTAssertEqual(frame.frame, i % 60)
            XCTAssertLessThanOrEqual(frame.presentationNanoseconds, playback, "never a later picture")
        }
        let s = p.statistics
        XCTAssertEqual(s.dropped, 0, "keeping up drops nothing")
        XCTAssertEqual(s.loops, 2, "two ends of file passed (pictures 60 and 120)")
        XCTAssertLessThanOrEqual(s.maxDepth, 3)
        XCTAssertEqual(p.state, .running)
        p.stop()
    }

    // MARK: Bound, stall, jump, drop (S2, R10)

    func testQueueStaysBoundedThroughStallJumpAndStop() {
        let p = pipeline()
        p.start(atNanoseconds: 0)
        for i in 0..<10 {
            XCTAssertTrue(p.waitUntilIdle())
            XCTAssertEqual(p.take(upTo: FakeVideoReader.pts(i)).map(globalIndex), i)
        }
        // Stall: nothing renders; the decoder fills the queue and stops.
        XCTAssertTrue(p.waitUntilIdle())
        let decodedAtStall = p.statistics.decoded
        usleep(50_000)
        XCTAssertEqual(p.statistics.decoded, decodedAtStall, "a full queue stops the decoder")
        XCTAssertEqual(p.statistics.depth, 3)
        XCTAssertLessThanOrEqual(p.statistics.maxDepth, 3)

        // Jump 10 s ahead (playback time 10.3 s → loop 5, picture 9).
        let jump: Int64 = 10_300_000_000
        let first = p.take(upTo: jump)
        XCTAssertNotNil(first, "the newest due picture is shown at once")
        XCTAssertLessThanOrEqual(first!.presentationNanoseconds, jump)
        XCTAssertGreaterThanOrEqual(p.statistics.dropped, 2, "the two older due pictures were late and dropped")
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertEqual(p.statistics.seeks, 1, "more than 1 s behind: the decoder jumps instead of decoding 10 s")
        let caughtUp = p.take(upTo: jump)
        XCTAssertEqual(caughtUp.map(globalIndex), 5 * 60 + 9, "after the seek the picture matches the time")
        XCTAssertLessThan(p.statistics.decoded, 30, "the 300 pictures in between were never decoded")
        XCTAssertLessThanOrEqual(p.statistics.maxDepth, 3)

        // Late pictures: skip 0.2 s (6 pictures) with the queue holding 3: 2 dropped, newest shown.
        XCTAssertTrue(p.waitUntilIdle())
        let droppedBefore = p.statistics.dropped
        let later = p.take(upTo: jump + 200_000_000)
        XCTAssertGreaterThanOrEqual(p.statistics.dropped - droppedBefore, 2, "older due pictures dropped, not queued")
        XCTAssertNotNil(later)
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertEqual(p.take(upTo: jump + 200_000_000).map(globalIndex), 5 * 60 + 15, "the decoder caught up without a seek")
        XCTAssertEqual(p.statistics.seeks, 1)
        XCTAssertLessThanOrEqual(p.statistics.maxDepth, 3)

        p.stop()
        XCTAssertFalse(p.hasSession)
        XCTAssertEqual(p.state, .idle)
        XCTAssertNil(p.take(upTo: jump + 300_000_000), "nothing after stop")
    }

    func testStartAtAPlaybackTimeResumesThere() {
        let p = pipeline()
        p.start(atNanoseconds: 2_500_000_000)   // loop 1, 0.5 s in
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertEqual(p.take(upTo: 2_500_000_000).map(globalIndex), 60 + 15)
        XCTAssertEqual(p.statistics.seeks, 0)
        XCTAssertEqual(p.info?.durationNanoseconds, FakeVideoReader.duration)
        p.stop()
    }

    func testTakeBeforeTheFirstPictureIsDueReturnsNothing() {
        let p = pipeline()
        p.start(atNanoseconds: 0)
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertNil(p.take(upTo: -1))
        XCTAssertEqual(p.take(upTo: 0).map(globalIndex), 0)
        p.stop()
    }

    // MARK: Failures

    func testReaderErrorsEndTheSessionWithTheirType() {
        let failing = pipeline { FakeVideoReader(failAt: 5) }
        failing.start(atNanoseconds: 0)
        for i in 0..<5 {
            XCTAssertTrue(failing.waitUntilIdle())
            _ = failing.take(upTo: FakeVideoReader.pts(i))
        }
        XCTAssertTrue(failing.waitUntilIdle())
        XCTAssertEqual(failing.state, .failed(.damaged))

        let empty = pipeline { FakeVideoReader(empty: true) }
        empty.start(atNanoseconds: 0)
        XCTAssertTrue(empty.waitUntilIdle())
        XCTAssertEqual(empty.state, .failed(.damaged), "a pass with no picture is damage, not a busy loop")

        let refused = pipeline { FakeVideoReader(openError: .notAVideo) }
        refused.start(atNanoseconds: 0)
        XCTAssertTrue(refused.waitUntilIdle())
        XCTAssertEqual(refused.state, .failed(.notAVideo))
        XCTAssertNil(refused.take(upTo: 0))
    }

    func testRestartReplacesTheSession() {
        let p = pipeline()
        p.start(atNanoseconds: 0)
        XCTAssertTrue(p.waitUntilIdle())
        p.start(atNanoseconds: 1_000_000_000)
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertEqual(p.take(upTo: 1_000_000_000).map(globalIndex), 30)
        XCTAssertEqual(p.statistics.taken, 1, "a fresh session's counters")
        p.stop()
    }

    // MARK: Limits (R5)

    func testLimitsCodecsAndMessages() throws {
        XCTAssertEqual(VideoCodec(fourCharacterCode: 0x6176_6331), .h264)   // avc1
        XCTAssertEqual(VideoCodec(fourCharacterCode: 0x6876_6331), .hevc)   // hvc1
        XCTAssertEqual(VideoCodec(fourCharacterCode: 0x6865_7631), .hevc)   // hev1
        XCTAssertNil(VideoCodec(fourCharacterCode: 0x6170_6368))            // apch (ProRes)
        let limits = VideoImportLimits.standard
        XCTAssertEqual(limits.maxFileBytes, 500 * 1024 * 1024)
        var info = VideoTrackInfo(width: 3840, height: 2160, rotation: .clockwise90, frameRate: 59.94, durationNanoseconds: 1, codec: .hevc)
        XCTAssertNoThrow(try info.check(limits))
        XCTAssertEqual(info.uprightWidth, 2160)
        XCTAssertEqual(info.uprightHeight, 3840)
        info.width = 7680
        XCTAssertThrowsError(try info.check(limits)) { XCTAssertEqual($0 as? VideoImportError, .pictureTooLarge) }
        info.width = 3840
        info.frameRate = 120
        XCTAssertThrowsError(try info.check(limits)) { XCTAssertEqual($0 as? VideoImportError, .frameRateTooHigh) }
        info.frameRate = 60.0001
        XCTAssertNoThrow(try info.check(limits), "a header that rounds 60 up passes")
        info.durationNanoseconds = 0
        XCTAssertThrowsError(try info.check(limits)) { XCTAssertEqual($0 as? VideoImportError, .damaged) }
        let all: [VideoImportError] = [.notAVideo, .tooLarge, .unsupportedCodec, .pictureTooLarge, .frameRateTooHigh, .damaged, .unreadable, .saveFailed]
        XCTAssertEqual(Set(all.map(\.message)).count, all.count, "every reason has its own plain message")
    }
}
