// ShowRehearsalTargetTests.swift — SHOW-006-T04 (specs/237-show-006-cue-rehearsal; R2; contract C2): the rehearsal
// target follows the cue Next would reach, passes over skipped cues, picks any cue with the arrows and never moves
// the show's position.
import Foundation
import ShowControl
import XCTest

final class ShowRehearsalTargetTests: XCTestCase {
    private static let scene = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

    /// Four cues; `skipped` are 1-based cue numbers.
    private func show(skipping skipped: Set<Int> = []) throws -> (ShowCueList, [UUID]) {
        var list = ShowCueList(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!, name: "Rehearse")
        var ids: [UUID] = []
        for n in 1...4 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
            try list.append(sceneID: Self.scene, label: "Cue \(n)", cueID: id)
            if skipped.contains(n) { try list.setSkipped(id, true) }
            ids.append(id)
        }
        return (list, ids)
    }

    func testFollowNextIsTheCueNextWouldReachAndFollowsTheShow() throws {
        var (list, ids) = try show(skipping: [3])
        XCTAssertEqual(ShowRehearsalTarget.followNext.resolve(in: list)?.id, ids[0], "Standby → the first cue")
        list.go(to: ids[1])
        XCTAssertEqual(ShowRehearsalTarget.followNext.resolve(in: list)?.id, ids[3], "skipped cue 3 is passed over")
        XCTAssertEqual(list.nextCue?.id, ids[3])
        list.go(to: ids[3])
        XCTAssertNil(ShowRehearsalTarget.followNext.resolve(in: list), "end of show")
        XCTAssertNil(ShowCueList().nextCue, "empty show")
    }

    func testPickedTargetsStepThroughEveryCueWithoutMovingTheShow() throws {
        var (list, ids) = try show(skipping: [3])
        list.go(to: ids[0])
        let before = list
        var target = ShowRehearsalTarget.followNext.stepped(by: 1, in: list)   // from cue 2
        XCTAssertEqual(target, .picked(ids[2]), "the arrows reach a skipped cue")
        target = target.stepped(by: 5, in: list)
        XCTAssertEqual(target, .picked(ids[3]), "clamped to the last cue")
        target = target.stepped(by: -9, in: list)
        XCTAssertEqual(target, .picked(ids[0]), "clamped to the first cue")
        XCTAssertEqual(list, before, "resolving and stepping never change the list")
        list.go(to: ids[3])
        XCTAssertEqual(ShowRehearsalTarget.followNext.stepped(by: -1, in: list), .picked(ids[3]), "from the end, back is the last cue")
        XCTAssertEqual(ShowRehearsalTarget.followNext.stepped(by: 1, in: ShowCueList()), .followNext, "empty show")
    }

    func testAPickedCueThatIsGoneFallsBackToTheNextCue() throws {
        var (list, ids) = try show()
        list.go(to: ids[0])
        let target = ShowRehearsalTarget.picked(ids[3])
        XCTAssertEqual(target.resolve(in: list)?.id, ids[3])
        try list.remove(ids[3])
        XCTAssertEqual(target.resolve(in: list)?.id, ids[1], "a removed pick falls back to the next cue")
    }
}
