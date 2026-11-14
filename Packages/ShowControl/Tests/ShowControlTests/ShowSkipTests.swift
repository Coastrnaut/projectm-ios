// ShowSkipTests.swift — SHOW-005-T11 (contract specs/232-show-005-cue-hold-skip/contracts/show-cue-hold-skip.md K1-K3):
// Next, Previous and the timed advance pass over skipped cues; Go to Cue still reaches one; every cue skipped gives
// `.allSkipped`; the `skip` flag round-trips and is read leniently. Injected clock only.
import Foundation
import ShowControl
import XCTest

final class ShowSkipTests: XCTestCase {
    private static let scene = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

    /// Five cues; `skipped` are 1-based cue numbers.
    private func show(skipping skipped: Set<Int> = []) throws -> (ShowCueList, [UUID]) {
        var list = ShowCueList(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, name: "Skip")
        var ids: [UUID] = []
        for n in 1...5 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
            try list.append(sceneID: Self.scene, label: "Cue \(n)", cueID: id)
            if skipped.contains(n) { try list.setSkipped(id, true) }
            ids.append(id)
        }
        return (list, ids)
    }

    private func number(_ list: ShowCueList) -> Int? { list.activeIndex.map { (i: Int) -> Int in i + 1 } }

    func testNextAndPreviousPassOverOneAndSeveralSkippedCues() throws {
        var (list, ids) = try show(skipping: [3])
        list.go(to: ids[1])
        XCTAssertEqual(list.next().outcome, .moved)
        XCTAssertEqual(number(list), 4, "Next from 2 passes over skipped 3")
        XCTAssertEqual(list.previous().outcome, .moved)
        XCTAssertEqual(number(list), 2, "Previous from 4 passes over skipped 3")

        (list, ids) = try show(skipping: [1, 2, 3])
        XCTAssertEqual(list.next().outcome, .moved)
        XCTAssertEqual(number(list), 4, "Standby → the first cue not skipped")
        XCTAssertFalse(list.canGoPrevious, "only skipped cues before 4")
        XCTAssertEqual(list.previous().outcome, .atStart)
        XCTAssertEqual(number(list), 4)

        (list, ids) = try show(skipping: [4, 5])
        list.go(to: ids[2])
        XCTAssertFalse(list.canGoNext, "only skipped cues after 3")
        XCTAssertEqual(list.next().outcome, .atEnd)
        XCTAssertEqual(number(list), 3)
    }

    func testGoToReachesASkippedCueAndStepsLeaveIt() throws {
        var (list, ids) = try show(skipping: [2, 3])
        XCTAssertEqual(list.go(to: ids[2]).outcome, .moved, "Go to Cue is explicit")
        XCTAssertEqual(number(list), 3)
        list.next()
        XCTAssertEqual(number(list), 4)
        list.go(to: ids[2])
        list.previous()
        XCTAssertEqual(number(list), 1)
    }

    func testSkippingTheActiveCueKeepsThePositionAndAllSkippedDoesNotMove() throws {
        var (list, ids) = try show()
        list.go(to: ids[1])
        for id in ids { try list.setSkipped(id, true) }
        XCTAssertEqual(number(list), 2, "skipping never moves the show")
        XCTAssertTrue(list.allSkipped)
        XCTAssertFalse(list.canGoNext)
        XCTAssertFalse(list.canGoPrevious)
        XCTAssertEqual(list.next().outcome, .allSkipped)
        XCTAssertEqual(list.previous().outcome, .allSkipped)
        XCTAssertEqual(number(list), 2)
        try list.setSkipped(ids[4], false)
        XCTAssertFalse(list.allSkipped)
        XCTAssertEqual(list.next().outcome, .moved)
        XCTAssertEqual(number(list), 5)
    }

    func testTimedAdvancePassesOverSkippedCues() throws {
        var (list, ids) = try show(skipping: [2, 3])
        try list.setDwell(ids[0], to: ShowCueDwell(seconds: 10))
        var timeline = ShowAdvanceTimeline()
        ShowTimedAdvance.step(list: &list, timeline: &timeline, at: .zero) { (l: inout ShowCueList) -> ShowStep in l.next() }
        XCTAssertNil(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: .seconds(9)))
        XCTAssertEqual(ShowTimedAdvance.tick(list: &list, timeline: &timeline, at: .seconds(10))?.outcome, .moved)
        XCTAssertEqual(number(list), 4, "the timed advance passes over cues 2 and 3")

        // A cue whose following cues are all skipped gets no countdown.
        (list, ids) = try show(skipping: [5])
        try list.setDwell(ids[3], to: ShowCueDwell(seconds: 5))
        list.go(to: ids[3])
        ShowTimedAdvance.started(list: list, timeline: &timeline, at: .zero)
        XCTAssertTrue(timeline.isIdle)
    }

    func testSkipFlagRoundTripsAndOnlySkippedCuesWriteIt() throws {
        let (plain, _) = try show()
        XCTAssertFalse(String(decoding: plain.encoded(), as: UTF8.self).contains("\"skip\""), "no key without skipped cues")
        let (skipped, ids) = try show(skipping: [2, 4])
        let bytes = skipped.encoded()
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self).components(separatedBy: "\"skip\":true").count - 1, 2)
        let decoded = try ShowCueList.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list.cues.filter(\.skipped).map(\.id), [ids[1], ids[3]])
        XCTAssertEqual(decoded.list.encoded(), bytes, "byte-identical round trip")
    }

    func testInvalidSkipValuesAreDroppedAndCounted() throws {
        let (list, _) = try show()
        let text = String(decoding: list.encoded(), as: UTF8.self)
        for value in ["false", "null"] {
            let edited = text.replacingOccurrences(of: "\"label\":\"Cue 1\"", with: "\"label\":\"Cue 1\",\"skip\":\(value)")
            let decoded = try ShowCueList.decode(Data(edited.utf8))
            XCTAssertEqual(decoded.warnings, [], value)
            XCTAssertFalse(decoded.list.cues[0].skipped, value)
        }
        for value in ["1", "\"yes\"", "{}", "[true]"] {
            let edited = text.replacingOccurrences(of: "\"label\":\"Cue 1\"", with: "\"label\":\"Cue 1\",\"skip\":\(value)")
                .replacingOccurrences(of: "\"label\":\"Cue 2\"", with: "\"label\":\"Cue 2\",\"skip\":\(value)")
            let decoded = try ShowCueList.decode(Data(edited.utf8))
            XCTAssertEqual(decoded.warnings, [.droppedSkipFlags(2)], value)
            XCTAssertFalse(decoded.list.cues[0].skipped || decoded.list.cues[1].skipped, value)
            XCTAssertEqual(decoded.list.cues.count, 5)
        }
    }
}
