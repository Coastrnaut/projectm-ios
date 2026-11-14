// MED-006-T04: the slideshow's settings and schedule (MED-006-R4 to R7, R14; S1, S2, S4, S5). Plain
// Swift on an injected clock and beat grid, so these run in the Linux shape too. No wall clock.
import Foundation
import ImageLayer
import XCTest

final class SlideshowTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000
    private static let frame: UInt64 = 16_666_667   // 60 Hz

    private let ids: [UUID] = (0..<5).map { (n: Int) -> UUID in
        UUID(uuidString: String(format: "0000A000-0000-4000-8000-%012d", n))!
    }

    /// Ticks at 60 Hz from `start` for `duration`; returns (time, new index) for every change.
    private func run(_ schedule: inout SlideshowSchedule, from start: UInt64, for duration: UInt64,
                     mode: SlideshowMode, seconds: Int = 5, beats: Int = 4, grid: SlideshowBeatGrid? = nil,
                     floor: UInt64 = SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 3)) -> [(UInt64, Int)] {
        var changes: [(UInt64, Int)] = []
        var t: UInt64 = start
        while t <= start + duration {
            if let index = schedule.tick(now: t, mode: mode, seconds: seconds, beats: beats, grid: grid, floorNanoseconds: floor) {
                changes.append((t, index))
            }
            t += Self.frame
        }
        return changes
    }

    // MARK: Settings (C1)

    func testSettingsSanitizeAndRoundTripThroughJSON() throws {
        let many: [UUID] = (0..<25).map { (_: Int) -> UUID in UUID() }
        let settings = SlideshowSettings(enabled: true, slides: [ids[1], ids[0], ids[1]] + many, mode: .beats, seconds: 99, beats: 3)
        XCTAssertEqual(settings.slides.count, SlideshowSettings.maximumSlides, "capped at 20")
        XCTAssertEqual(Array(settings.slides.prefix(2)), [ids[1], ids[0]], "duplicates after the first dropped, order kept")
        XCTAssertEqual(settings.seconds, 60, "clamped")
        XCTAssertEqual(settings.beats, 4, "an unknown beat count reads as 4")
        XCTAssertEqual(SlideshowSettings(seconds: 1).seconds, 2)
        let back = SlideshowSettings.decode(settings.encoded)
        XCTAssertEqual(back, settings)
        XCTAssertEqual(SlideshowSettings.decode(nil), .off)
        XCTAssertEqual(SlideshowSettings.decode(Data("not json".utf8)), .off)
        let lower = Data("{\"enabled\":true,\"slides\":[\"0000a000-0000-4000-8000-000000000001\",\"x\"],\"mode\":\"beats\",\"seconds\":7,\"beats\":8}".utf8)
        let read = SlideshowSettings.decode(lower)
        XCTAssertEqual(read.slides, [], "non-canonical identifiers are dropped")
        XCTAssertEqual(read.mode, .beats)
        XCTAssertEqual(read.seconds, 7)
        XCTAssertEqual(read.beats, 8)
        XCTAssertFalse(read.isActive, "on but empty is not active")
        XCTAssertTrue(SlideshowSettings(enabled: true, slides: [ids[0]]).isActive)
    }

    // MARK: The acceptance (S1, S2)

    /// "Five-image fixture follows saved ordering and timing mode": Time 5 s over two cycles.
    func testFiveSlidesFollowTheSavedOrderInTimeMode() {
        let saved: [UUID] = [ids[2], ids[0], ids[4], ids[1], ids[3]]
        let settings = SlideshowSettings(enabled: true, slides: saved, mode: .time, seconds: 5)
        var schedule = SlideshowSchedule(count: settings.slides.count)
        XCTAssertEqual(schedule.index, 0, "the first slide of the saved order shows first")
        let start: UInt64 = 100 * Self.second
        // Exact 5 s steps: tick on a 1 ms grid so every boundary is hit exactly.
        var changes: [(UInt64, Int)] = []
        var t: UInt64 = start
        while t <= start + 50 * Self.second {
            if let i = schedule.tick(now: t, mode: settings.mode, seconds: settings.seconds, beats: settings.beats, grid: nil,
                                     floorNanoseconds: SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 3)) {
                changes.append((t, i))
            }
            t += 1_000_000
        }
        XCTAssertEqual(changes.map { (c: (UInt64, Int)) -> Int in c.1 }, [1, 2, 3, 4, 0, 1, 2, 3, 4, 0], "two full cycles in order")
        let times: [UInt64] = changes.map { (c: (UInt64, Int)) -> UInt64 in c.0 - start }
        let expected: [UInt64] = (1...10).map { (n: Int) -> UInt64 in UInt64(n) * 5 * Self.second }
        XCTAssertEqual(times, expected, "exactly every 5 s")
        let shown: [UUID] = changes.map { (c: (UInt64, Int)) -> UUID in saved[c.1] }
        XCTAssertEqual(Array(shown.prefix(5)), [ids[0], ids[4], ids[1], ids[3], ids[2]])
    }

    /// Beats every 2 on a steady 120 BPM grid: changes exactly on beats 2, 4, 6… in order.
    func testFiveSlidesChangeOnEveryOtherBeatInBeatsMode() throws {
        let period: UInt64 = Self.second / 2
        let anchor: UInt64 = 10 * Self.second
        let grid = try XCTUnwrap(SlideshowBeatGrid(periodNanoseconds: period, anchorNanoseconds: anchor))
        var schedule = SlideshowSchedule(count: 5)
        // Start just after a beat (the anchor), 1 ms ticks so the change frame is the beat itself.
        var changes: [(UInt64, Int)] = []
        var t: UInt64 = anchor + 1
        while t <= anchor + 10 * Self.second + Self.second / 4 {
            if let i = schedule.tick(now: t, mode: .beats, seconds: 60, beats: 2, grid: grid,
                                     floorNanoseconds: SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 3)) {
                changes.append((t, i))
            }
            t += 1_000_000
        }
        XCTAssertEqual(changes.map { (c: (UInt64, Int)) -> Int in c.1 }, [1, 2, 3, 4, 0, 1, 2, 3, 4, 0], "order")
        for (n, change) in changes.enumerated() {
            let beat: UInt64 = anchor + UInt64(2 * (n + 1)) * period
            XCTAssertTrue(change.0 >= beat && change.0 < beat + 1_000_000, "change \(n) on beat \(2 * (n + 1))")
        }
    }

    // MARK: Uncertain tempo (S4, R6)

    func testUnreliableTempoFallsBackToTheTimeInterval() throws {
        var schedule = SlideshowSchedule(count: 5)
        let changes = run(&schedule, from: 0, for: 21 * Self.second, mode: .beats, seconds: 4, beats: 1, grid: nil)
        XCTAssertEqual(changes.count, 5, "every 4 s, not on beats")
        XCTAssertEqual(changes.map { (c: (UInt64, Int)) -> Int in c.1 }, [1, 2, 3, 4, 0])
        // The grid becomes reliable: beat counting starts from that moment (every 4 beats at 120 BPM = 2 s).
        let grid = try XCTUnwrap(SlideshowBeatGrid(periodNanoseconds: Self.second / 2, anchorNanoseconds: 0))
        let start: UInt64 = schedule.lastTick ?? 0
        let beatChanges = run(&schedule, from: start + Self.frame, for: 6 * Self.second, mode: .beats, seconds: 60, beats: 4, grid: grid)
        XCTAssertEqual(beatChanges.count, 3, "three changes in 6 s at every 4 beats")
        for change in beatChanges {
            XCTAssertLessThan(change.0 % (Self.second / 2), Self.frame, "each on a beat")
        }
    }

    // MARK: Safety floor (S5, R7)

    func testChangesAreNeverCloserThanTheSafetyFloor() throws {
        let grid = try XCTUnwrap(SlideshowBeatGrid(periodNanoseconds: Self.second / 4, anchorNanoseconds: 0))   // 240 BPM
        XCTAssertEqual(SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 3), Self.second)
        XCTAssertEqual(SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 2), 2 * Self.second)
        XCTAssertEqual(SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 1), 3 * Self.second)
        XCTAssertEqual(SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 9), Self.second, "clamped")
        for (f, floor) in [(3, Self.second), (2, 2 * Self.second), (1, 3 * Self.second)] {
            var schedule = SlideshowSchedule(count: 5)
            let changes = run(&schedule, from: Self.frame, for: 10 * Self.second, mode: .beats, beats: 1, grid: grid,
                              floor: SlideshowSafetyFloor.nanoseconds(flashesPerSecond: f))
            XCTAssertFalse(changes.isEmpty)
            var previous: UInt64?
            for change in changes {
                if let previous { XCTAssertGreaterThanOrEqual(change.0 - previous, floor, "f=\(f)") }
                XCTAssertLessThan(change.0 % (Self.second / 4), Self.frame, "f=\(f): still on a beat")
                previous = change.0
            }
            XCTAssertLessThanOrEqual(changes.count, Int(10 * Self.second / floor), "f=\(f)")
        }
        // Time mode with an interval shorter than the floor: the floor wins.
        var schedule = SlideshowSchedule(count: 3)
        let changes = run(&schedule, from: 0, for: 10 * Self.second, mode: .time, seconds: 2,
                          floor: SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 1))
        XCTAssertEqual(changes.count, 3, "every 3 s under Strict")
    }

    // MARK: Pauses, timing changes, one slide

    func testPausesAddNothingAndTimingChangesRestartWithoutAChange() {
        var schedule = SlideshowSchedule(count: 5)
        _ = run(&schedule, from: 0, for: 3 * Self.second, mode: .time)
        let last: UInt64 = schedule.lastTick ?? 0
        // A 10-minute pause (one long step) adds nothing.
        XCTAssertNil(schedule.tick(now: last + 600 * Self.second, mode: .time, seconds: 5, beats: 4, grid: nil, floorNanoseconds: Self.second))
        XCTAssertEqual(schedule.index, 0)
        let before: UInt64 = schedule.slideNanoseconds
        XCTAssertGreaterThanOrEqual(before, 2 * Self.second)
        schedule.timingChanged()
        XCTAssertEqual(schedule.slideNanoseconds, 0)
        XCTAssertEqual(schedule.index, 0, "no change on a timing edit")
        let changes = run(&schedule, from: last + 600 * Self.second + Self.frame, for: 6 * Self.second, mode: .time)
        XCTAssertEqual(changes.count, 1, "the slide restarted its 5 s")
        // One slide never changes; zero slides never change.
        for count in [0, 1] {
            var single = SlideshowSchedule(count: count)
            XCTAssertTrue(run(&single, from: 0, for: 30 * Self.second, mode: .time, seconds: 2).isEmpty)
            XCTAssertEqual(single.nextIndex, 0)
        }
    }

    func testRelistKeepsTheShownIndexAndRestartStartsOver() {
        var schedule = SlideshowSchedule(count: 5, index: 3)
        XCTAssertEqual(schedule.nextIndex, 4)
        schedule.relist(count: 3, index: 7)
        XCTAssertEqual(schedule.index, 2, "clamped into the new list")
        schedule.restart(count: 4)
        XCTAssertEqual(schedule.index, 0)
        XCTAssertNil(schedule.lastTick)
        XCTAssertEqual(SlideshowBeatGrid(periodNanoseconds: 0, anchorNanoseconds: 1), nil)
    }
}
