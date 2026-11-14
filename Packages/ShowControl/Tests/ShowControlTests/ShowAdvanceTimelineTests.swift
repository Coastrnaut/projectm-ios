// ShowAdvanceTimelineTests.swift — SHOW-002-T07: the roadmap acceptance ("Injected clock fires one advance per cue at
// configured deadline") and the engine's rules (contract show-cue-dwell.md D3 T1-T5; SHOW-002-S1 to S4). Every time
// comes from `ShowManualClock`; no test waits.
import Foundation
import ShowControl
import XCTest

final class ShowAdvanceTimelineTests: XCTestCase {
    /// Five cues with dwells 10, 20, 30, 40 and 50 s.
    private func timedShow() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        for n in 1...5 { try list.setDwell(ShowFixtures.uuid(n), to: try ShowCueDwell(seconds: n * 10)) }
        return list
    }

    private func cueNumber(_ list: ShowCueList) -> Int { (list.activeIndex ?? -1) + 1 }

    /// Runs the clock from `clock.now()` to `end` in `step` ticks, recording each advance as (time, to cue).
    private func run(_ list: inout ShowCueList, _ timeline: inout ShowAdvanceTimeline, clock: ShowManualClock,
                     until end: Duration, step: Duration) -> [(time: Duration, cue: Int)] {
        var fired: [(time: Duration, cue: Int)] = []
        while clock.now() < end {
            clock.advance(by: step)
            if let result = ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()), result.moved {
                fired.append((clock.now(), cueNumber(list)))
            }
        }
        return fired
    }

    // MARK: Acceptance (SHOW-002-S1)

    func testInjectedClockFiresOneAdvancePerCueAtItsDeadline() throws {
        for step in [Duration.seconds(1), .milliseconds(250)] {
            let clock = ShowManualClock()
            var list = try timedShow()
            var timeline = ShowAdvanceTimeline()
            ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
            XCTAssertEqual(cueNumber(list), 1)
            let fired = run(&list, &timeline, clock: clock, until: .seconds(300), step: step)
            XCTAssertEqual(fired.map(\.time), [.seconds(10), .seconds(30), .seconds(60), .seconds(100)],
                           "one advance per cue, exactly at start + dwell (step \(step))")
            XCTAssertEqual(fired.map(\.cue), [2, 3, 4, 5])
            XCTAssertEqual(cueNumber(list), 5, "the show stops on the last cue")
            XCTAssertTrue(timeline.isIdle, "the last cue never counts down")
        }
    }

    func testNoAdvanceOneInstantBeforeTheDeadline() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
        clock.set(.seconds(10) - .nanoseconds(1))
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()))
        XCTAssertEqual(timeline.remainingWholeSeconds(at: clock.now()), 1, "rounded up")
        clock.set(.seconds(10))
        XCTAssertEqual(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now())?.outcome, .moved)
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()), "never twice at the same time")
        XCTAssertEqual(cueNumber(list), 2)
        XCTAssertEqual(timeline.remaining(at: clock.now()), .seconds(20))
    }

    // MARK: Jumps (SHOW-002-R5, S2; research D2)

    func testAJumpPastSeveralDeadlinesFiresOnceAndRestartsFromTheJump() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(2)) }
        clock.set(.seconds(500))   // past cue 2's (20 s), and where cues 3 and 4 would have ended
        XCTAssertEqual(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now())?.outcome, .moved)
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()))
        XCTAssertEqual(cueNumber(list), 3, "exactly one advance")
        XCTAssertEqual(timeline.phase, .running(cueID: ShowFixtures.uuid(3), deadline: .seconds(530)), "cue 3 counts from the jump")
    }

    // MARK: Manual steps (SHOW-002-R6, S3)

    func testAManualNextResetsTheDeadline() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
        clock.set(.seconds(4))
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
        XCTAssertEqual(cueNumber(list), 2)
        let fired = run(&list, &timeline, clock: clock, until: .seconds(30), step: .seconds(1))
        XCTAssertEqual(fired.map(\.time), [.seconds(24)], "cue 1's deadline (10 s) never fires; cue 2's is 4 + 20 s")
        XCTAssertEqual(fired.map(\.cue), [3])
    }

    func testPreviousAndGoToRestartInFull() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(3)) }
        clock.set(.seconds(25))
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.previous() }
        XCTAssertEqual(timeline.phase, .running(cueID: ShowFixtures.uuid(2), deadline: .seconds(45)))
        clock.set(.seconds(40))
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(2)) }
        XCTAssertEqual(timeline.phase, .running(cueID: ShowFixtures.uuid(2), deadline: .seconds(60)), "Go to the active cue restarts it")
        // A step that does not move (Previous on cue 1 / Next on the last) leaves the countdown alone.
        let unchanged = timeline
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(77)) }
        XCTAssertEqual(timeline, unchanged)
    }

    // MARK: Off, Standby, last cue (SHOW-002-R8)

    func testOffStandbyAndTheLastCueNeverCountDown() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        try list.setDwell(ShowFixtures.uuid(2), to: nil)
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.started(list: list, timeline: &timeline, at: clock.now())
        XCTAssertTrue(timeline.isIdle, "Standby")
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(2)) }
        XCTAssertTrue(timeline.isIdle, "Off")
        XCTAssertEqual(run(&list, &timeline, clock: clock, until: .seconds(4000), step: .seconds(100)).count, 0)
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(5)) }
        XCTAssertTrue(timeline.isIdle, "the last cue's dwell is ignored")
        XCTAssertNil(timeline.remaining(at: clock.now()))
    }

    func testADueAdvanceOnACueThatBecameLastDoesNothing() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(4)) }
        try list.move(fromOffsets: IndexSet(integer: 3), toOffset: 5)   // cue 4 is now last
        clock.set(.seconds(40))
        XCTAssertEqual(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now())?.outcome, .atEnd)
        XCTAssertEqual(list.activeCue?.id, ShowFixtures.uuid(4))
        XCTAssertTrue(timeline.isIdle)
        // A due cue that is no longer active is dropped.
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.go(to: ShowFixtures.uuid(1)) }
        list.standBy()
        clock.set(.seconds(60))
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()))
        XCTAssertNil(list.activeCue)
    }

    // MARK: Holds (SHOW-002-R7, S4)

    func testAHoldKeepsTheRemainingTime() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
        clock.set(.seconds(6))
        timeline.setHeld(true, at: clock.now())
        XCTAssertEqual(timeline.phase, .held(cueID: ShowFixtures.uuid(1), remaining: .seconds(4)))
        clock.set(.seconds(106))
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: clock.now()), "held: nothing fires")
        XCTAssertEqual(timeline.remainingWholeSeconds(at: clock.now()), 4)
        timeline.setHeld(false, at: clock.now())
        let fired = run(&list, &timeline, clock: clock, until: .seconds(115), step: .milliseconds(500))
        XCTAssertEqual(fired.map(\.time), [.seconds(110)], "4 s after the hold ends")
    }

    func testAStepWhileHeldStartsHeldWithTheFullDwell() throws {
        let clock = ShowManualClock()
        var list = try timedShow()
        var timeline = ShowAdvanceTimeline()
        timeline.setHeld(true, at: clock.now())
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: clock.now()) { (l: inout ShowCueList) -> ShowStep in l.next() }
        XCTAssertEqual(timeline.phase, .held(cueID: ShowFixtures.uuid(1), remaining: .seconds(10)))
        clock.set(.seconds(50))
        timeline.setHeld(false, at: clock.now())
        XCTAssertEqual(timeline.phase, .running(cueID: ShowFixtures.uuid(1), deadline: .seconds(60)))
    }

    // MARK: Clocks and dwell values

    func testClocksAreMonotonic() {
        let manual = ShowManualClock(.seconds(5))
        manual.advance(by: .seconds(-3))
        manual.set(.seconds(1))
        XCTAssertEqual(manual.now(), .seconds(5), "never backwards")
        let real = ShowContinuousClock()
        let a = real.now()
        XCTAssertGreaterThanOrEqual(real.now(), a)
    }

    func testDwellBoundsAndText() throws {
        XCTAssertThrowsError(try ShowCueDwell(seconds: 0))
        XCTAssertThrowsError(try ShowCueDwell(seconds: 3601))
        XCTAssertEqual(try ShowCueDwell(seconds: 3600).clockText, "60:00")
        XCTAssertEqual(try ShowCueDwell(seconds: 5).clockText, "0:05")
        XCTAssertEqual(try ShowCueDwell(seconds: 90).spokenText, "1 minute 30 seconds")
        XCTAssertEqual(try ShowCueDwell(seconds: 1).spokenText, "1 second")
        XCTAssertEqual(ShowCueDwell.presets.count, 20)
        XCTAssertEqual(ShowCueDwell.presets, ShowCueDwell.presets.sorted())
        var list = try ShowFixtures.fiveCues()
        XCTAssertThrowsError(try list.setDwell(ShowFixtures.uuid(77), to: nil))
        list.go(to: ShowFixtures.uuid(2))
        try list.setDwell(ShowFixtures.uuid(3), to: try ShowCueDwell(seconds: 7))
        XCTAssertEqual(list.position, .cue(ShowFixtures.uuid(2)), "an edit never moves the position")
        let copy = try list.insert(sceneID: ShowFixtures.sceneID(6), label: "copy", after: ShowFixtures.uuid(3),
                                   cueID: ShowFixtures.uuid(6), dwell: list.cues[2].dwell)
        XCTAssertEqual(copy.dwell?.seconds, 7, "Duplicate carries the dwell (SHOW-002-R14)")
    }
}
