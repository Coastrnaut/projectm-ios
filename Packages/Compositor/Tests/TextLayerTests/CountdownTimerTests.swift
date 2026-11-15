// MED-012-T04: the countdown's timer, face and settings with an injected monotonic time (MED-012-S1, S2; contract
// C1, C2). Every platform; no wall clock.
import Foundation
import TextLayer
import XCTest

final class CountdownTimerTests: XCTestCase {
    private func running(_ seconds: Int, from start: Double = 100) -> CountdownTimer {
        var timer = CountdownTimer(durationSeconds: seconds)
        timer.start(at: start)
        return timer
    }

    /// C1: the face below and from an hour, and never negative.
    func testFormatStrings() {
        let cases: [(Int, String)] = [(0, "00:00"), (59, "00:59"), (300, "05:00"), (3599, "59:59"), (3600, "1:00:00"),
                                      (5940, "1:39:00"), (-5, "00:00")]
        for (seconds, expected) in cases {
            XCTAssertEqual(CountdownFormat.string(seconds: seconds), expected, "\(seconds) s")
        }
    }

    /// S1 (roadmap acceptance): exact strings at given elapsed times of a 5:00 run.
    func testExactStringsAtElapsedTimes() {
        let timer = running(300)
        let cases: [(Double, String)] = [(0, "05:00"), (0.5, "05:00"), (1, "04:59"), (60, "04:00"), (299, "00:01"),
                                         (299.5, "00:01"), (300, "00:00")]
        for (elapsed, expected) in cases {
            XCTAssertEqual(CountdownFormat.string(timer, at: 100 + elapsed), expected, "after \(elapsed) s")
        }
        XCTAssertEqual(CountdownFormat.string(running(5940), at: 100), "1:39:00")
    }

    /// S2: zero is reached once and nothing below it is ever shown, over skipped updates and a 10-hour overrun.
    func testReachesZeroOnceAcrossSkipsAndOverrun() {
        var timer = running(10)
        var finished = 0
        var lowest = Int.max
        // Uneven updates that skip whole seconds, cross zero between two updates, then keep coming for 10 hours.
        var times: [Double] = [0.3, 2.9, 7.1, 9.95, 12.4, 13, 60]
        times += stride(from: 3600.0, through: 36_000, by: 3600).map { (t: Double) -> Double in t }
        for t in times {
            if timer.advance(at: 100 + t) { finished += 1 }
            lowest = min(lowest, timer.displayedSeconds(at: 100 + t))
            XCTAssertGreaterThanOrEqual(timer.remaining(at: 100 + t), 0)
        }
        XCTAssertEqual(finished, 1, "the finished event fires exactly once")
        XCTAssertEqual(lowest, 0)
        XCTAssertEqual(CountdownFormat.string(timer, at: 100 + 36_000), "00:00")
        XCTAssertEqual(timer.state, .finished)
        XCTAssertFalse(timer.isRunning, "it stops at zero")
    }

    /// S2: one large jump straight past zero (the app back from the background) fires once; repeats fire nothing.
    func testLargeJumpFiresOnceAndRepeatsFireNothing() {
        var timer = running(300)
        XCTAssertFalse(timer.advance(at: 100 + 299.999))
        XCTAssertTrue(timer.advance(at: 100 + 7200))
        for _ in 0..<5 { XCTAssertFalse(timer.advance(at: 100 + 7200)) }
        XCTAssertFalse(timer.advance(at: 100 + 99_999))
        XCTAssertEqual(timer.remaining(at: 100 + 99_999), 0)
    }

    func testPauseKeepsTheRemainingTimeAndResumeContinues() {
        var timer = running(300)
        timer.pause(at: 100 + 30)
        XCTAssertEqual(timer.state, .paused)
        XCTAssertEqual(CountdownFormat.string(timer, at: 100 + 500), "04:30", "paused time does not count")
        XCTAssertFalse(timer.advance(at: 100 + 5000))
        timer.start(at: 1000)
        XCTAssertEqual(CountdownFormat.string(timer, at: 1010), "04:20")
    }

    /// Reset re-arms: a second run fires its own finished event once; Start after a finish restarts from the top.
    func testResetReArms() {
        var timer = running(5)
        XCTAssertTrue(timer.advance(at: 106))
        timer.reset()
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(CountdownFormat.string(timer, at: 500), "00:05")
        timer.start(at: 200)
        XCTAssertFalse(timer.advance(at: 204))
        XCTAssertTrue(timer.advance(at: 205))
        XCTAssertFalse(timer.advance(at: 206))
        timer.start(at: 300)   // a Start after the finish
        XCTAssertEqual(timer.state, .running)
        XCTAssertEqual(CountdownFormat.string(timer, at: 300), "00:05")
        timer.reset(durationSeconds: 0)
        XCTAssertEqual(timer.durationSeconds, 1, "clamped to 1 s")
        timer.reset(durationSeconds: 10_000)
        XCTAssertEqual(timer.durationSeconds, 5940, "clamped to 99 min")
    }

    func testScheduleWakesAtTheNextShownSecond() throws {
        let timer = running(300)
        XCTAssertEqual(try XCTUnwrap(CountdownSchedule.delay(timer, at: 100)), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(CountdownSchedule.delay(timer, at: 100.25)), 0.75, accuracy: 1e-9)
        XCTAssertNil(CountdownSchedule.delay(CountdownTimer(durationSeconds: 300), at: 100), "stopped: no ticks")
    }

    func testSettingsDefaultsAndStorage() {
        let d = CountdownOverlaySettings.default
        XCTAssertFalse(d.isShown, "off by default")
        XCTAssertEqual(d.durationSeconds, 300)
        XCTAssertFalse(d.startsFromCues)
        var s = CountdownOverlaySettings(isShown: true, durationSeconds: 90, startsFromCues: true)
        XCTAssertEqual(CountdownOverlaySettings.decodeStored(s.encodedForStorage()), .settings(s))
        s.minutes = 0
        s.seconds = 0
        XCTAssertEqual(s.durationSeconds, 1, "0:00 is raised to 1 s")
        s.minutes = 120
        XCTAssertEqual(s.durationSeconds, 5940, "99:00 at most")
        XCTAssertEqual(CountdownOverlaySettings.decodeStored(Data("{\"version\":2}".utf8)), .unsupportedVersion(2))
        XCTAssertEqual(CountdownOverlaySettings.decodeStored(Data("nope".utf8)), .damaged)
        XCTAssertEqual(CountdownOverlaySettings.decodeStored(Data("{\"version\":1,\"durationSeconds\":0}".utf8)),
                       .settings(CountdownOverlaySettings(durationSeconds: 1)))
        XCTAssertEqual(d.spec(for: "05:00").message, "", "hidden: nothing drawn")
        XCTAssertEqual(CountdownOverlaySettings(isShown: true).spec(for: "05:00").message, "05:00")
    }
}
