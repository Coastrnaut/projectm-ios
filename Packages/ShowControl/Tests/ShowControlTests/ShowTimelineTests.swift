// ShowTimelineTests.swift — SHOW-007-T03 (contract specs/243-show-007-timeline-transport/contracts/show-timeline-transport.md
// T1, T3; seek plans for T2): the timeline from dwells (skipped cues excluded, open end), time ↔ cue, loop wrap, seek
// plans and scrub coalescing. Pure; no clock.
import Foundation
import ShowControl
import XCTest

final class ShowTimelineTests: XCTestCase {
    private func cueID(_ n: Int) -> UUID { UUID(uuidString: "C0E00000-0000-4000-8000-00000000000\(n)")! }
    private func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    /// Five cues; `dwells[i]` seconds (nil = Off); `skipped` cue numbers.
    private func list(_ dwells: [Int?], skipped: Set<Int> = []) throws -> ShowCueList {
        var list = ShowCueList(name: "T")
        for (i, dwell) in dwells.enumerated() {
            let n = i + 1
            try list.append(sceneID: sceneID(n), label: "Cue \(n)", cueID: cueID(n))
            if let dwell { try list.setDwell(cueID(n), to: try ShowCueDwell(seconds: dwell)) }
            if skipped.contains(n) { try list.setSkipped(cueID(n), true) }
        }
        return list
    }

    func testEntriesSkipSkippedCuesAndStopAtTheOpenEnd() throws {
        let timeline = ShowTimeline(list: try list([30, 30, 30, nil, 30], skipped: [2]))
        XCTAssertEqual(timeline.entries.map(\.cueID), [cueID(1), cueID(3), cueID(4)], "cue 2 skipped; cue 5 after the open end")
        XCTAssertEqual(timeline.entries.map(\.start), [.zero, .seconds(30), .seconds(60)])
        XCTAssertEqual(timeline.duration, .seconds(60))
        XCTAssertTrue(timeline.isOpenEnded)
        XCTAssertFalse(timeline.canLoop)
        XCTAssertNil(timeline.loopTarget(from: cueID(4), looping: true))
        XCTAssertEqual(timeline.locate(.seconds(500), looping: true)?.cueID, cueID(4), "no wrap with an open end")
        XCTAssertEqual(timeline.locate(.seconds(500), looping: true)?.remaining, nil)
        XCTAssertTrue(ShowTimeline(list: try list([nil, 30])).duration == .zero, "a first cue without a dwell: no time")
        XCTAssertTrue(ShowTimeline(list: ShowCueList()).isEmpty)
    }

    func testLocateAndTimeAreInverse() throws {
        let timeline = ShowTimeline(list: try list([30, 30, 30, 30, 30]))
        let point = try XCTUnwrap(timeline.locate(.seconds(75), looping: false))
        XCTAssertEqual(point.cueID, cueID(3))
        XCTAssertEqual(point.index, 2)
        XCTAssertEqual(point.elapsed, .seconds(15))
        XCTAssertEqual(point.remaining, .seconds(15))
        XCTAssertEqual(timeline.time(ofCue: cueID(3), elapsed: .seconds(15)), .seconds(75))
        XCTAssertEqual(timeline.time(ofCue: cueID(3), remaining: .seconds(15)), .seconds(75))
        XCTAssertEqual(timeline.locate(.seconds(60), looping: false)?.cueID, cueID(3), "a boundary belongs to the later cue")
        XCTAssertEqual(timeline.locate(.seconds(-4), looping: false)?.cueID, cueID(1))
        let end = try XCTUnwrap(timeline.locate(.seconds(999), looping: false))
        XCTAssertEqual(end.cueID, cueID(5))
        XCTAssertEqual(end.remaining, .zero, "the end clamps to the last cue with nothing left")
        XCTAssertNil(timeline.time(ofCue: UUID(), elapsed: .zero))
    }

    func testLoopWrapsTimesAndNamesTheFirstCue() throws {
        let timeline = ShowTimeline(list: try list([10, 20, 30], skipped: [1]))
        XCTAssertTrue(timeline.canLoop)
        XCTAssertEqual(timeline.duration, .seconds(50))
        XCTAssertEqual(timeline.locate(.seconds(55), looping: true)?.cueID, cueID(2))
        XCTAssertEqual(timeline.locate(.seconds(55), looping: true)?.elapsed, .seconds(5))
        XCTAssertEqual(timeline.locate(.seconds(50), looping: true)?.cueID, cueID(2), "the end is the next pass's start")
        XCTAssertEqual(timeline.loopTarget(from: cueID(3), looping: true), cueID(2))
        XCTAssertNil(timeline.loopTarget(from: cueID(3), looping: false))
        XCTAssertNil(timeline.loopTarget(from: cueID(2), looping: true), "only the last cue wraps")
    }

    func testSeekPlanAppliesOnlyTheDestinationAndRepeatsAreNothing() throws {
        let timeline = ShowTimeline(list: try list([30, 30, 30, 30, 30]))
        XCTAssertEqual(ShowSeekPlan.plan(activeCueID: cueID(1), timeline: timeline, to: .seconds(75), looping: false,
                                         currentRemaining: .seconds(30)),
                       .apply(cueID: cueID(3), remaining: .seconds(15)))
        XCTAssertEqual(ShowSeekPlan.plan(activeCueID: cueID(3), timeline: timeline, to: .seconds(75), looping: false,
                                         currentRemaining: .seconds(15)), .none, "the same seek again: nothing")
        XCTAssertEqual(ShowSeekPlan.plan(activeCueID: cueID(3), timeline: timeline, to: .seconds(80), looping: false,
                                         currentRemaining: .seconds(15)),
                       .reposition(cueID: cueID(3), remaining: .seconds(10)), "inside the active cue: the countdown only")
        XCTAssertEqual(ShowSeekPlan.plan(activeCueID: nil, timeline: ShowTimeline(list: ShowCueList()), to: .zero, looping: false,
                                         currentRemaining: nil), .none)
    }

    func testScrubCommitsOnceWithTheLastPreview() {
        var scrub = ShowScrub()
        scrub.begin()
        XCTAssertNil(scrub.previewTime)
        for s in [10, 40, 70, 95, 75] { scrub.move(to: .seconds(s)) }
        XCTAssertEqual(scrub.previewTime, .seconds(75))
        XCTAssertEqual(scrub.end(), .seconds(75))
        XCTAssertFalse(scrub.isScrubbing)
        XCTAssertNil(scrub.end(), "a second end commits nothing")
        scrub.begin()
        XCTAssertNil(scrub.end(), "a drag that never moved commits nothing")
        scrub.move(to: .seconds(5))
        scrub.cancel()
        XCTAssertNil(scrub.end())
    }
}
