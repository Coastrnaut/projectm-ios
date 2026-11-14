// MED-003-T04, T14, T15: the loop region through the decode pipeline with a recording fake reader
// and injected playback times (MED-003-R1 to R6, R10, R11, S1 to S4). Plain Swift: runs in the Linux
// shape too. No wall-clock assertion: waits are ceilings for a slow shared Mac.
import Foundation
import VideoLayer
import XCTest

/// Opens and preparations seen by fake readers (shared across a session's reader instances).
final class LoopReaderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var opens: [(start: Int64, end: Int64?)] = []
    private var prepares: [(start: Int64, end: Int64?)] = []
    private var passes = 0

    func opened(_ start: Int64, _ end: Int64?) { lock.withLock { opens.append((start, end)); passes += 1 } }
    func prepared(_ start: Int64, _ end: Int64?) { lock.withLock { prepares.append((start, end)) } }
    var openStarts: [Int64] { lock.withLock { opens.map(\.start) } }
    var openEnds: [Int64?] { lock.withLock { opens.map(\.end) } }
    var prepareStarts: [Int64] { lock.withLock { prepares.map(\.start) } }
    /// Opens so far (the first is the probe of the duration).
    var openCount: Int { lock.withLock { passes } }
}

/// `frameCount` pictures at `fps` (each picture is its index), honouring the open's end. Faults:
/// `failAt` throws at that index (on every open, or only on open number `failOnOpen`), `endAt`
/// returns nil from that index (a truncated file).
final class LoopFakeReader: VideoFrameReading {
    let fps: Int64
    let frameCount: Int
    let log: LoopReaderLog
    let failAt: Int?
    let failOnOpen: Int?
    let endAt: Int?
    private var position = 0
    private var end: Int64?
    private var isOpen = false

    init(fps: Int64 = 30, frameCount: Int = 60, log: LoopReaderLog, failAt: Int? = nil, failOnOpen: Int? = nil, endAt: Int? = nil) {
        self.fps = fps
        self.frameCount = frameCount
        self.log = log
        self.failAt = failAt
        self.failOnOpen = failOnOpen
        self.endAt = endAt
    }

    var duration: Int64 { Int64(frameCount) * 1_000_000_000 / fps }
    func pts(_ k: Int) -> Int64 { Int64(k) * 1_000_000_000 / fps }

    func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo {
        try open(startNanoseconds: startNanoseconds, endNanoseconds: nil)
    }

    func open(startNanoseconds: Int64, endNanoseconds: Int64?) throws(VideoImportError) -> VideoTrackInfo {
        log.opened(startNanoseconds, endNanoseconds)
        // The picture shown at the start: the last one whose time is ≤ start.
        let index: Int64 = startNanoseconds * fps / 1_000_000_000
        position = Int(max(index, 0))
        end = endNanoseconds
        isOpen = true
        return VideoTrackInfo(width: 64, height: 48, rotation: .none, frameRate: Double(fps), durationNanoseconds: duration, codec: .h264)
    }

    func prepare(startNanoseconds: Int64, endNanoseconds: Int64?) { log.prepared(startNanoseconds, endNanoseconds) }

    func next() throws(VideoImportError) -> (pts: Int64, frame: Int)? {
        guard isOpen, position < frameCount else { return nil }
        if let endAt, position >= endAt { return nil }
        if let end, pts(position) >= end { return nil }
        if position == failAt, failOnOpen == nil || failOnOpen == log.openCount { throw .damaged }
        defer { position += 1 }
        return (pts(position), position)
    }

    func close() { isOpen = false }
}

final class VideoLoopTests: XCTestCase {
    private static let frame: Int64 = 1_000_000_000 / 30

    private func pipeline(_ make: @escaping @Sendable () -> LoopFakeReader) -> VideoDecodePipeline<LoopFakeReader> {
        VideoDecodePipeline<LoopFakeReader>(capacity: 3, makeReader: make)
    }

    /// Picture index i's slot plus 5 ms.
    private func playback(_ i: Int) -> Int64 { Int64(i) * 1_000_000_000 / 30 + 5_000_000 }

    /// Takes the picture due at each of `steps` playback times (waiting for the decoder each time).
    private func play(_ p: VideoDecodePipeline<LoopFakeReader>, from first: Int, steps: Int) -> [TimedFrame<Int>] {
        var shown: [TimedFrame<Int>] = []
        for i in first..<(first + steps) {
            XCTAssertTrue(p.waitUntilIdle(timeout: 5))
            guard let frame = p.take(upTo: playback(i)) else {
                XCTFail("no picture at step \(i)")
                return shown
            }
            shown.append(frame)
        }
        return shown
    }

    /// As `play`, but a step with no new picture due keeps the held one (as the layer does).
    private func playHolding(_ p: VideoDecodePipeline<LoopFakeReader>, steps: Int) -> [TimedFrame<Int>] {
        var shown: [TimedFrame<Int>] = []
        for i in 0..<steps {
            XCTAssertTrue(p.waitUntilIdle(timeout: 5))
            if let frame = p.take(upTo: playback(i)) {
                shown.append(frame)
            } else if let held = shown.last {
                shown.append(held)
            } else {
                XCTFail("no first picture")
                return shown
            }
        }
        return shown
    }

    // MARK: Clamping (S3, R2)

    func testEffectiveRegionTable() {
        let d: Int64 = 2_000_000_000
        typealias Case = (String, VideoLoopRegion?, Int64, Int64)
        let cases: [Case] = [
            ("none is the whole file", nil, 0, d),
            ("inside stays", VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1500), 500_000_000, 1_500_000_000),
            ("out past the end", VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 9000), 500_000_000, d),
            ("longer than the file", VideoLoopRegion(inMilliseconds: -100, outMilliseconds: 9000), 0, d),
            ("negative in", VideoLoopRegion(inMilliseconds: -300, outMilliseconds: 1000), 0, 1_000_000_000),
            ("inverted grows to the minimum", VideoLoopRegion(inMilliseconds: 1200, outMilliseconds: 800), 1_200_000_000, 1_450_000_000),
            ("too short grows", VideoLoopRegion(inMilliseconds: 1000, outMilliseconds: 1100), 1_000_000_000, 1_250_000_000),
            ("too short at the end moves in back", VideoLoopRegion(inMilliseconds: 1900, outMilliseconds: 2000), 1_750_000_000, d),
            ("in past the end", VideoLoopRegion(inMilliseconds: 5000, outMilliseconds: 6000), 1_750_000_000, d),
        ]
        for (name, region, expectedIn, expectedOut) in cases {
            let e = VideoLoopRegion.effective(region, duration: d)
            XCTAssertEqual(e.inNanoseconds, expectedIn, name)
            XCTAssertEqual(e.outNanoseconds, expectedOut, name)
            XCTAssertGreaterThanOrEqual(e.length, VideoLoopRegion.minimumLengthNanoseconds, name)
        }
        let short = VideoLoopRegion(inMilliseconds: 50, outMilliseconds: 60).effective(duration: 200_000_000)
        XCTAssertEqual(short, VideoLoopRegion.whole(duration: 200_000_000), "a video shorter than the minimum plays whole")
        XCTAssertTrue(VideoLoopRegion(inMilliseconds: 0, outMilliseconds: 9000).isWholeFile(duration: d))
        XCTAssertFalse(VideoLoopRegion(inMilliseconds: 0, outMilliseconds: 1000).isWholeFile(duration: d))
        let r = VideoLoopRegion(inMilliseconds: 1500, outMilliseconds: 3000)
        XCTAssertEqual(r.inMilliseconds, 1500)
        XCTAssertEqual(r.outMilliseconds, 3000)
        XCTAssertTrue(r.contains(1_500_000_000))
        XCTAssertFalse(r.contains(3_000_000_000), "out is not part of the region")
    }

    // MARK: Boundaries (S1, R3, R4)

    func testRegionLoopsAcrossFourBoundariesWithoutAGap() {
        let log = LoopReaderLog()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)   // pictures 15…29
        let p = pipeline { LoopFakeReader(log: log) }
        p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        let shown = play(p, from: 0, steps: 75)   // five passes
        XCTAssertEqual(shown.count, 75)
        var wraps = 0
        for (i, frame) in shown.enumerated() {
            XCTAssertEqual(frame.frame, 15 + i % 15, "step \(i)")
            XCTAssertTrue(region.contains(frame.mediaNanoseconds), "step \(i): \(frame.mediaNanoseconds) inside")
            // Gap 0 frames: the picture shown is the one due now, never one held from an earlier slot.
            let lateness: Int64 = playback(i) - frame.presentationNanoseconds
            XCTAssertGreaterThanOrEqual(lateness, 0, "step \(i): never early")
            XCTAssertLessThan(lateness, Self.frame, "step \(i): not held past its slot")
            if i > 0, frame.frame < shown[i - 1].frame {
                wraps += 1
                XCTAssertEqual(shown[i - 1].frame, 29, "the wrap leaves from out − 1")
                XCTAssertEqual(frame.frame, 15, "and arrives at in")
                XCTAssertGreaterThan(frame.presentationNanoseconds, shown[i - 1].presentationNanoseconds, "the timeline keeps increasing")
            }
        }
        XCTAssertEqual(wraps, 4)
        let s = p.statistics
        XCTAssertEqual(s.dropped, 0)
        XCTAssertGreaterThanOrEqual(s.loops, 4)
        XCTAssertGreaterThanOrEqual(s.prepared, 4, "every pass prepared its successor before out")
        XCTAssertEqual(s.earlyEnds, 0)
        XCTAssertEqual(p.state, .running)
        p.stop()
        for start in log.openStarts { XCTAssertTrue(region.contains(start), "open at \(start) inside the region") }
        for end in log.openEnds { XCTAssertEqual(end, 1_000_000_000, "every open ends at out") }
        XCTAssertTrue(log.prepareStarts.allSatisfy { (s: Int64) -> Bool in s == 500_000_000 }, "pre-roll prepares in")
    }

    func testWholeFileRegionMatchesMED002() {
        let log = LoopReaderLog()
        let p = pipeline { LoopFakeReader(log: log) }
        p.start(atNanoseconds: 0, region: VideoLoopRegion(inMilliseconds: 0, outMilliseconds: 5000), mediaStartNanoseconds: nil)
        let shown = play(p, from: 0, steps: 65)
        XCTAssertEqual(shown.map(\.frame), (0..<65).map { (i: Int) -> Int in i % 60 })
        XCTAssertEqual(p.statistics.earlyEnds, 0, "the end of the file is not early for the whole file")
        p.stop()
        XCTAssertTrue(log.openEnds.allSatisfy { (e: Int64?) -> Bool in e == nil || e! >= 2_000_000_000 })
    }

    func testStartInsideARegionMapsThePlaybackTime() {
        let log = LoopReaderLog()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        let p = pipeline { LoopFakeReader(log: log) }
        p.start(atNanoseconds: playback(20), region: region, mediaStartNanoseconds: nil)   // 20 % 15 = 5 → picture 20
        XCTAssertEqual(play(p, from: 20, steps: 3).map(\.frame), [20, 21, 22])
        p.stop()
        XCTAssertTrue(log.openStarts.allSatisfy(region.contains))
    }

    func testShortRegionOfASlowClipShowsThePictureCoveringIn() {
        let log = LoopReaderLog()
        // 2 fps, 4 pictures at 0, 0.5, 1.0, 1.5 s; [0.6, 0.85) starts no picture.
        let region = VideoLoopRegion(inMilliseconds: 600, outMilliseconds: 850)
        let p = pipeline { LoopFakeReader(fps: 2, frameCount: 4, log: log) }
        p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        for i in 0..<20 {
            XCTAssertTrue(p.waitUntilIdle())
            if let frame = p.take(upTo: Int64(i) * 50_000_000) { XCTAssertEqual(frame.frame, 1, "the picture covering in") }
        }
        XCTAssertEqual(p.state, .running, "never an empty pass")
        p.stop()
    }

    // MARK: Edits, seek, resume (S2, R10)

    func testRegionEditsContinueInsideOrJumpToIn() {
        let log = LoopReaderLog()
        let p = pipeline { LoopFakeReader(log: log) }
        p.start(atNanoseconds: 0, region: VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1500), mediaStartNanoseconds: nil)
        let before = play(p, from: 0, steps: 10)   // pictures 15…24
        let shownMedia = before.last!.mediaNanoseconds
        XCTAssertEqual(before.last!.frame, 24)
        // Out becomes 0.9 s (picture 27): the shown picture is inside, so playback continues from it.
        let narrower = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 900)
        p.start(atNanoseconds: playback(9), region: narrower, mediaStartNanoseconds: shownMedia)
        let after = play(p, from: 9, steps: 16)
        XCTAssertEqual(Array(after.prefix(4).map(\.frame)), [24, 25, 26, 15], "continues, then wraps at the new out")
        XCTAssertTrue(after.allSatisfy { (f: TimedFrame<Int>) -> Bool in narrower.contains(f.mediaNanoseconds) })
        // In becomes 1.1 s, past the shown picture: playback jumps to the new in.
        let later = VideoLoopRegion(inMilliseconds: 1100, outMilliseconds: 1500)
        p.start(atNanoseconds: playback(25), region: later, mediaStartNanoseconds: after.last!.mediaNanoseconds)
        let jumped = play(p, from: 25, steps: 15)
        XCTAssertEqual(jumped.first?.frame, 33, "the first picture at or after the new in")
        XCTAssertTrue(jumped.allSatisfy { (f: TimedFrame<Int>) -> Bool in later.contains(f.mediaNanoseconds) })
        p.stop()
        XCTAssertTrue(log.openStarts.allSatisfy { (s: Int64) -> Bool in s >= 500_000_000 && s < 1_500_000_000 },
                      "no open outside any region: \(log.openStarts)")
    }

    func testStallSeekAndResumeStayInside() {
        let log = LoopReaderLog()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        let p = pipeline { LoopFakeReader(log: log) }
        p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        _ = play(p, from: 0, steps: 3)
        // A 10 s stall: the decoder seeks inside the region (10.305 s → 10.305 mod 0.5 = 0.305 s → picture 24).
        let jump: Int64 = 10_305_000_000
        XCTAssertTrue(p.waitUntilIdle())
        _ = p.take(upTo: jump)
        XCTAssertTrue(p.waitUntilIdle())
        let caught = p.take(upTo: jump)
        XCTAssertEqual(caught?.frame, 24)
        XCTAssertEqual(p.statistics.seeks, 1)
        // Resume (background and back): restart at the shown picture.
        p.start(atNanoseconds: jump + 2 * Self.frame, region: region, mediaStartNanoseconds: caught!.mediaNanoseconds)
        XCTAssertTrue(p.waitUntilIdle())
        XCTAssertEqual(p.take(upTo: jump + 2 * Self.frame)?.frame, 24, "the same picture after the resume")
        p.stop()
        XCTAssertTrue(log.openStarts.allSatisfy(region.contains), "every open inside: \(log.openStarts)")
    }

    // MARK: Recovery (S4, R5, R6)

    func testReaderErrorNearTheEndContinuesAtInAndIsCounted() {
        let log = LoopReaderLog()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        // Open 1 probes the duration at in; open 2… are passes. Fail at picture 27 in the first pass.
        let p = pipeline { LoopFakeReader(log: log, failAt: 27, failOnOpen: 1) }
        p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        let shown = playHolding(p, steps: 30)
        // Pictures 27-29 are lost: 26 stays on screen for their slots, then the next pass starts at in.
        XCTAssertEqual(Array(shown.prefix(17).map(\.frame)), Array(15...26) + [26, 26, 26, 15, 16], "then in again")
        XCTAssertTrue(shown.allSatisfy { (f: TimedFrame<Int>) -> Bool in region.contains(f.mediaNanoseconds) })
        XCTAssertEqual(p.statistics.recoveredErrors, 1)
        XCTAssertEqual(p.state, .running)
        p.stop()
    }

    func testEarlyEndContinuesAtInAndIsCounted() {
        let log = LoopReaderLog()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        let p = pipeline { LoopFakeReader(log: log, endAt: 25) }   // the file "ends" at picture 25
        p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        let shown = playHolding(p, steps: 25)
        XCTAssertEqual(Array(shown.prefix(17).map(\.frame)), Array(15...24) + [24, 24, 24, 24, 24, 15, 16])
        XCTAssertGreaterThanOrEqual(p.statistics.earlyEnds, 2)
        XCTAssertEqual(p.state, .running)
        p.stop()
    }

    func testWholeFileEndOfFileErrorRecovers() {
        let log = LoopReaderLog()
        let p = pipeline { LoopFakeReader(log: log, failAt: 58, failOnOpen: 1) }
        p.start(atNanoseconds: 0)
        let shown = playHolding(p, steps: 62)
        XCTAssertEqual(Array(shown.suffix(4).map(\.frame)), [57, 57, 0, 1], "after picture 57 the file starts again")
        XCTAssertEqual(p.statistics.recoveredErrors, 1)
        XCTAssertEqual(p.state, .running)
        p.stop()
    }

    func testRepeatedBadPassesFail() {
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        // Every pass fails at its first picture: no picture at all → three bad passes → failed.
        let empty = pipeline { LoopFakeReader(log: LoopReaderLog(), failAt: 15) }
        empty.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        XCTAssertTrue(empty.waitUntilIdle())
        XCTAssertEqual(empty.state, .failed(.damaged))

        // Every pass fails at picture 20: drain until the third error ends the session.
        let failing = pipeline { LoopFakeReader(log: LoopReaderLog(), failAt: 20) }
        failing.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
        var i = 0
        while failing.state == .running, i < 60 {
            XCTAssertTrue(failing.waitUntilIdle())
            _ = failing.take(upTo: playback(i))
            i += 1
        }
        XCTAssertEqual(failing.state, .failed(.damaged), "a fragment is not looped forever")
        XCTAssertEqual(failing.statistics.recoveredErrors, 3)
    }
}
