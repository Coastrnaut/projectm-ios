// MED-004-T04, T14, T16: playback speed on an injected clock and through the decode pipeline with a
// fake reader (MED-004-R1, R2, R4, R5, R9, S1 to S3). Plain Swift: runs in the Linux shape too. No
// wall-clock assertion: waits are ceilings for a slow shared Mac, never timing budgets.
import Dispatch
import Foundation
import VideoLayer
import XCTest

/// Opens, preparations and reads of `SpeedFakeReader` (shared across a session's reader instances).
final class SpeedReaderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var opens = 0
    private var preparedAt: [Int] = []

    func opened() { lock.withLock { opens += 1 } }
    /// `index`: the picture read last when the preparation was asked for.
    func prepared(afterReading index: Int) { lock.withLock { preparedAt.append(index) } }
    var openCount: Int { lock.withLock { opens } }
    var preparedAfter: [Int] { lock.withLock { preparedAt } }
}

/// `frameCount` pictures at 30 fps (each picture is its index). With a `gate`, every picture waits
/// for one signal (a decoder slower than the speed needs); the end of the file never waits.
final class SpeedFakeReader: VideoFrameReading {
    static let fps: Int64 = 30
    let frameCount: Int
    let log: SpeedReaderLog
    let gate: DispatchSemaphore?
    private var position = 0
    private var end: Int64?

    init(frameCount: Int = 60, log: SpeedReaderLog, gate: DispatchSemaphore? = nil) {
        self.frameCount = frameCount
        self.log = log
        self.gate = gate
    }

    static func pts(_ k: Int) -> Int64 { Int64(k) * 1_000_000_000 / fps }

    func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo {
        try open(startNanoseconds: startNanoseconds, endNanoseconds: nil)
    }

    func open(startNanoseconds: Int64, endNanoseconds: Int64?) throws(VideoImportError) -> VideoTrackInfo {
        log.opened()
        let index: Int64 = startNanoseconds * Self.fps / 1_000_000_000
        position = Int(max(index, 0))
        end = endNanoseconds
        let duration: Int64 = Int64(frameCount) * 1_000_000_000 / Self.fps
        return VideoTrackInfo(width: 64, height: 48, rotation: .none, frameRate: Double(Self.fps), durationNanoseconds: duration, codec: .h264)
    }

    func prepare(startNanoseconds: Int64, endNanoseconds: Int64?) { log.prepared(afterReading: position - 1) }

    func next() throws(VideoImportError) -> (pts: Int64, frame: Int)? {
        guard position < frameCount else { return nil }
        if let end, Self.pts(position) >= end { return nil }
        gate?.wait()
        defer { position += 1 }
        return (Self.pts(position), position)
    }

    func close() {}
}

final class VideoSpeedTests: XCTestCase {
    private static let second: Int64 = 1_000_000_000
    private static let picture: Int64 = 1_000_000_000 / 30
    private static let base: UInt64 = 50_000_000_000

    private func speed(_ percent: Int) -> VideoPlaybackSpeed {
        guard let s = VideoPlaybackSpeed(percent: percent) else {
            XCTFail("speed \(percent) not offered")
            return .normal
        }
        return s
    }

    /// The presentation time of 60 Hz step `i` (exact: step 120 is 2 s after step 0).
    private func presentation(_ i: Int) -> UInt64 { Self.base + UInt64(i) * 1_000_000_000 / 60 }

    // MARK: C1 — the speed set

    func testOnlyTheSafeSpeedsExist() {
        XCTAssertEqual(VideoPlaybackSpeed.all.map(\.percent), [25, 50, 75, 100, 125, 150, 200])
        XCTAssertEqual(VideoPlaybackSpeed.all, VideoPlaybackSpeed.all.sorted())
        XCTAssertEqual(VideoPlaybackSpeed.normal.percent, 100)
        XCTAssertTrue(VideoPlaybackSpeed.normal.isNormal)
        let rejected: [Int] = [0, -50, 1, 33, 99, 101, 250, 300, 400]
        for p in rejected { XCTAssertNil(VideoPlaybackSpeed(percent: p), "\(p) is outside the safe set") }
        let leads: [(Int, Int64)] = [(25, 500_000_000), (50, 500_000_000), (100, 500_000_000), (150, 750_000_000), (200, 1_000_000_000)]
        for (p, lead) in leads { XCTAssertEqual(speed(p).prerollLeadNanoseconds, lead, "lead at \(p) %") }
    }

    // MARK: S1 — the acceptance on an injected clock

    /// "Half-speed fixture advances one second per two seconds elapsed." 2 s of 60 Hz presentation
    /// steps advance the video by 1 s at 0.5× (exact here; the criterion allows one picture interval).
    func testHalfSpeedAdvancesOneSecondPerTwoSecondsElapsed() {
        let cases: [(Int, Int64)] = [(50, 1_000_000_000), (100, 2_000_000_000), (200, 4_000_000_000),
                                     (25, 500_000_000), (75, 1_500_000_000), (150, 3_000_000_000)]
        for (percent, expected) in cases {
            var clock = VideoPlaybackClock()
            clock.setSpeed(speed(percent))
            XCTAssertEqual(clock.advance(to: presentation(0)), 0)
            var previous: Int64 = 0
            for i in 1...120 {
                let now = clock.advance(to: presentation(i))
                XCTAssertGreaterThanOrEqual(now, previous, "\(percent) %: time never runs back")
                previous = now
            }
            let advanced: Int64 = clock.playbackNanoseconds
            XCTAssertLessThan(abs(advanced - expected), Self.picture, "\(percent) %: within one picture interval")
            XCTAssertEqual(advanced, expected, "\(percent) %: exact with integer scaling")
            XCTAssertEqual(clock.presentationSinceSpeedChange, 2 * Self.second)
            XCTAssertEqual(clock.playbackSinceSpeedChange, expected)
        }
    }

    func testOddStepsCarryTheRemainderWithoutDrift() {
        let steps: [UInt64] = [16_666_667, 16_666_666, 7, 33_333_333, 1, 999_999_999]
        for s in VideoPlaybackSpeed.all {
            var clock = VideoPlaybackClock()
            clock.setSpeed(s)
            var t: UInt64 = Self.base
            clock.advance(to: t)
            var total: Int64 = 0
            for round in 0..<200 {
                let step: UInt64 = steps[round % steps.count]
                t += step
                total += Int64(step)
                clock.advance(to: t)
            }
            let exact: Int64 = total * Int64(s.percent) / 100
            XCTAssertEqual(clock.playbackNanoseconds, exact, "\(s.percent) %: ⌊Σ step × speed⌋, no drift")
        }
    }

    func testPausesAndBackwardStepsAddNothingAtEverySpeed() {
        for s in VideoPlaybackSpeed.all {
            var clock = VideoPlaybackClock()
            clock.setSpeed(s)
            clock.advance(to: Self.base)
            clock.advance(to: Self.base + 1_000_000_001)   // a pause longer than 1 s
            clock.advance(to: Self.base + 500_000_000)     // backwards
            XCTAssertEqual(clock.playbackNanoseconds, 0, "\(s.percent) %")
            clock.advance(to: Self.base + 1_100_000_000)
            let expected: Int64 = 99_999_999 * Int64(s.percent) / 100   // the step from the last forward time
            XCTAssertEqual(clock.playbackNanoseconds, expected, "\(s.percent) %: the next normal step counts")
            clock.reset()
            XCTAssertEqual(clock.playbackNanoseconds, 0)
            XCTAssertEqual(clock.speed, s, "reset keeps the speed")
        }
    }

    // MARK: S2 — a change mid-play is continuous

    func testSpeedChangeKeepsTheVideoTimeContinuous() {
        var clock = VideoPlaybackClock()
        clock.advance(to: presentation(0))
        for i in 1...60 { clock.advance(to: presentation(i)) }
        XCTAssertEqual(clock.playbackNanoseconds, Self.second)
        clock.setSpeed(speed(200))
        XCTAssertEqual(clock.playbackNanoseconds, Self.second, "no jump at the change")
        XCTAssertEqual(clock.presentationSinceSpeedChange, 0, "a new measurement window")
        let step: Int64 = Int64(presentation(61) - presentation(60))
        clock.advance(to: presentation(61))
        XCTAssertEqual(clock.playbackNanoseconds, Self.second + 2 * step, "the first step after the change adds step × new speed")
        clock.setSpeed(speed(50))
        let before: Int64 = clock.playbackNanoseconds
        let next: Int64 = Int64(presentation(62) - presentation(61))
        clock.advance(to: presentation(62))
        XCTAssertEqual(clock.playbackNanoseconds - before, next / 2)
    }

    // MARK: Pipeline helpers

    /// The newest fake picture whose time is ≤ `playback` (whole 2 s file, no loop).
    private static func pictureDue(at playback: Int64) -> Int {
        var k = Int(playback * 30 / second)
        while SpeedFakeReader.pts(k + 1) <= playback { k += 1 }
        return k
    }

    private func pipeline(_ make: @escaping @Sendable () -> SpeedFakeReader) -> VideoDecodePipeline<SpeedFakeReader> {
        VideoDecodePipeline<SpeedFakeReader>(capacity: 3, makeReader: make)
    }

    /// One frame as the layer runs it: advance the clock, take the newest due picture, else hold.
    private func step(_ p: VideoDecodePipeline<SpeedFakeReader>, _ clock: inout VideoPlaybackClock, _ i: Int,
                      held: inout TimedFrame<Int>?) -> Int64 {
        let playback = clock.advance(to: presentation(i))
        if let newest = p.take(upTo: playback) { held = newest }
        return playback
    }

    // MARK: S1, S2 through the pipeline

    func testPipelineShowsThePictureOfTheVideoTimeAndASpeedChangeNeedsNoRestart() {
        let log = SpeedReaderLog()
        let p = pipeline { SpeedFakeReader(log: log) }
        var clock = VideoPlaybackClock()
        clock.setSpeed(speed(50))
        p.setSpeed(speed(50))
        p.start(atNanoseconds: 0)
        var held: TimedFrame<Int>?
        var shown: [Int] = []
        for i in 0...90 {
            if i == 61 {
                // 0.5 s of video at 0.5×, then 2× for 30 steps (1 s more): 1.5 s < the 2 s file.
                XCTAssertTrue(p.waitUntilIdle())
                let opens = log.openCount
                let seeks = p.statistics.seeks
                clock.setSpeed(speed(200))
                p.setSpeed(speed(200))
                XCTAssertEqual(log.openCount, opens, "a speed change opens nothing")
                XCTAssertEqual(p.statistics.seeks, seeks, "and seeks nowhere")
                XCTAssertEqual(p.speed, speed(200))
            }
            XCTAssertTrue(p.waitUntilIdle(timeout: 5))
            let playback = step(p, &clock, i, held: &held)
            guard let frame = held else { return XCTFail("no picture at step \(i)") }
            let expected = Self.pictureDue(at: playback)
            XCTAssertEqual(frame.frame, expected, "step \(i): playback \(playback) shows picture \(expected)")
            shown.append(frame.frame)
        }
        XCTAssertEqual(clock.playbackNanoseconds, 1_500_000_000)
        XCTAssertEqual(shown, shown.sorted(), "pictures stay in order across the change")
        XCTAssertEqual(p.statistics.seeks, 0)
        // At 2× a 60 Hz frame advances one 30 fps picture; where integer ns put two pictures in one frame
        // the older is dropped (the per-step check above proves the shown one is always the due one).
        p.stop()
    }

    // MARK: R9 — above 1× with a decoder that cannot keep up

    func testSlowDecoderAtDoubleSpeedNeverSlowsPlayback() {
        let log = SpeedReaderLog()
        let gate = DispatchSemaphore(value: 0)
        let p = pipeline { SpeedFakeReader(log: log, gate: gate) }
        var clock = VideoPlaybackClock()
        clock.setSpeed(speed(200))
        p.setSpeed(speed(200))
        p.start(atNanoseconds: 0)
        var held: TimedFrame<Int>?
        var released = 0
        var lastShown: Int64 = -1
        for i in 0...120 {
            if i % 2 == 0 {   // one picture per two frames: half of what 2× needs
                gate.signal()
                released += 1
                let target = released
                XCTAssertTrue(waitFor { p.statistics.decoded >= target }, "step \(i): the decoder read its picture")
            }
            let playback = step(p, &clock, i, held: &held)
            XCTAssertEqual(playback, 2 * Int64(presentation(i) - presentation(0)), "step \(i): playback advances at 2× regardless")
            if let frame = held {
                XCTAssertLessThanOrEqual(frame.presentationNanoseconds, playback, "step \(i): never early")
                XCTAssertGreaterThanOrEqual(frame.presentationNanoseconds, lastShown, "step \(i): never back")
                XCTAssertLessThan(playback - frame.presentationNanoseconds, 1_200_000_000, "step \(i): lag bounded by the seek rule")
                lastShown = frame.presentationNanoseconds
            }
        }
        XCTAssertEqual(clock.playbackNanoseconds, 4 * Self.second)
        XCTAssertGreaterThanOrEqual(p.statistics.seeks, 1, "the decoder seeks to the video time instead of slowing playback")
        p.stop()
        for _ in 0..<8 { gate.signal() }   // let the stopped session's thread finish
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        for _ in 0..<5000 where !condition() { usleep(1000) }
        return condition()
    }

    // MARK: S3 — the loop region at 0.5× and 2×

    func testLoopRegionStaysSeamlessAtHalfAndDoubleSpeed() {
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)   // pictures 15…29
        let runs: [(Int, Int)] = [(50, 200), (200, 60)]   // (percent, 60 Hz steps): 1.67 s and 2 s of video
        for (percent, steps) in runs {
            let log = SpeedReaderLog()
            let p = pipeline { SpeedFakeReader(log: log) }
            var clock = VideoPlaybackClock()
            clock.setSpeed(speed(percent))
            p.setSpeed(speed(percent))
            p.start(atNanoseconds: 0, region: region, mediaStartNanoseconds: nil)
            var held: TimedFrame<Int>?
            var wraps = 0
            var previous: Int?
            for i in 0..<steps {
                XCTAssertTrue(p.waitUntilIdle(timeout: 5))
                let playback = step(p, &clock, i, held: &held)
                guard let frame = held else { return XCTFail("\(percent) %: no picture at step \(i)") }
                XCTAssertTrue(region.contains(frame.mediaNanoseconds), "\(percent) %, step \(i): inside")
                let lateness: Int64 = playback - frame.presentationNanoseconds
                XCTAssertGreaterThanOrEqual(lateness, 0, "\(percent) %, step \(i): never early")
                XCTAssertLessThan(lateness, Self.picture, "\(percent) %, step \(i): no picture held past its slot (gap 0)")
                if let previous, frame.frame < previous {
                    wraps += 1
                    XCTAssertEqual(previous, 29, "\(percent) %: the wrap leaves from out − 1")
                    XCTAssertEqual(frame.frame, 15, "\(percent) %: and arrives at in")
                }
                previous = frame.frame
            }
            XCTAssertGreaterThanOrEqual(wraps, 3, "\(percent) %: at least three boundaries")
            XCTAssertEqual(p.state, .running)
            p.stop()
        }
    }

    /// The pre-roll lead grows with speeds above 1× (research MED-004-D3): on the whole 2 s file the
    /// pass at 0 is prepared after reading picture 45 (1.5 s) at 0.5× and 1×, picture 30 (1.0 s) at 2×.
    func testPrerollStartsEarlierInVideoTimeAboveNormalSpeed() {
        let runs: [(Int, Int)] = [(50, 45), (100, 45), (150, 38), (200, 30)]
        for (percent, firstPrepared) in runs {
            let log = SpeedReaderLog()
            let p = pipeline { SpeedFakeReader(log: log) }
            p.setSpeed(speed(percent))
            p.start(atNanoseconds: 0)
            var t: Int64 = 0
            while log.preparedAfter.isEmpty, t < 2 * Self.second {
                XCTAssertTrue(p.waitUntilIdle(timeout: 5))
                _ = p.take(upTo: t)
                t += Self.picture
            }
            XCTAssertEqual(log.preparedAfter.first, firstPrepared, "\(percent) %")
            p.stop()
        }
    }

    func testSpeedSetOnARunningSessionChangesItsLead() {
        let log = SpeedReaderLog()
        let p = pipeline { SpeedFakeReader(log: log) }
        p.start(atNanoseconds: 0)
        XCTAssertTrue(p.waitUntilIdle())
        p.setSpeed(speed(200))   // after pictures 0-2 were read, before the lead is reached at 1×
        var t: Int64 = 0
        while log.preparedAfter.isEmpty, t < 2 * Self.second {
            XCTAssertTrue(p.waitUntilIdle(timeout: 5))
            _ = p.take(upTo: t)
            t += Self.picture
        }
        XCTAssertEqual(log.preparedAfter.first, 30, "the running session uses the 2× lead")
        XCTAssertEqual(log.openCount, 1, "no restart")
        p.stop()
    }
}
