// ShowAcceptanceTests.swift — SHOW-001-S1, the row's acceptance: "Five-cue list advances
// deterministically and preserves scene IDs." A five-cue show with five distinct scenes is stepped
// through an 18-step script of next, previous and go to; the position and scene ID are checked at
// every step, and two runs from fresh, identical states give identical results.
import Foundation
import ShowControl
import XCTest

/// Fixed IDs so every run builds the same show.
enum ShowFixtures {
    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }

    static func sceneID(_ n: Int) -> String {
        UUID(uuidString: String(format: "5CE7E000-0000-4000-8000-%012d", n))!.uuidString
    }

    static let showID = uuid(999)

    /// Cues 1…5 (cue IDs uuid(1…5)) showing scenes 1…5, labelled "Cue A"…"Cue E".
    static func fiveCues() throws -> ShowCueList {
        var list = ShowCueList(id: showID, name: "Acceptance")
        let labels = ["Cue A", "Cue B", "Cue C", "Cue D", "Cue E"]
        for n in 1...5 {
            try list.append(sceneID: sceneID(n), label: labels[n - 1], cueID: uuid(n))
        }
        return list
    }
}

final class ShowAcceptanceTests: XCTestCase {
    enum Op: Equatable {
        case next, previous
        case go(Int)
    }

    /// (operation, expected outcome, expected cue number or 0 for Standby).
    static let script: [(op: Op, outcome: ShowStepOutcome, cue: Int)] = [
        (.previous, .atStart, 0),
        (.next, .moved, 1),
        (.next, .moved, 2),
        (.next, .moved, 3),
        (.previous, .moved, 2),
        (.next, .moved, 3),
        (.next, .moved, 4),
        (.next, .moved, 5),
        (.next, .atEnd, 5),
        (.next, .atEnd, 5),
        (.previous, .moved, 4),
        (.go(1), .moved, 1),
        (.previous, .atStart, 1),
        (.go(5), .moved, 5),
        (.go(5), .moved, 5),
        (.previous, .moved, 4),
        (.go(3), .moved, 3),
        (.next, .moved, 4),
    ]

    private func runScript() throws -> [ShowStep] {
        var list = try ShowFixtures.fiveCues()
        XCTAssertEqual(list.position, .standby)
        var steps: [ShowStep] = []
        for (index, entry) in Self.script.enumerated() {
            let step: ShowStep = switch entry.op {
            case .next: list.next()
            case .previous: list.previous()
            case let .go(n): list.go(to: ShowFixtures.uuid(n))
            }
            let expectedPosition: ShowPosition = entry.cue == 0 ? .standby : .cue(ShowFixtures.uuid(entry.cue))
            let expectedScene: String? = entry.cue == 0 ? nil : ShowFixtures.sceneID(entry.cue)
            XCTAssertEqual(step.outcome, entry.outcome, "step \(index + 1) \(entry.op)")
            XCTAssertEqual(step.position, expectedPosition, "step \(index + 1) \(entry.op)")
            XCTAssertEqual(step.sceneID, expectedScene, "step \(index + 1) \(entry.op)")
            XCTAssertEqual(list.activeSceneID, expectedScene, "step \(index + 1)")
            steps.append(step)
        }
        return steps
    }

    func testFiveCueScriptGivesTheExpectedCueAndSceneAtEveryStep() throws {
        XCTAssertGreaterThanOrEqual(Self.script.count, 15)
        _ = try runScript()
    }

    func testTwoRunsFromFreshStatesAreIdentical() throws {
        let first = try runScript()
        let second = try runScript()
        XCTAssertEqual(first, second)
    }

    func testFiveScenesAreDistinctAndKeptByTheirCues() throws {
        let list = try ShowFixtures.fiveCues()
        XCTAssertEqual(list.sceneIDs, (1...5).map { (n: Int) -> String in ShowFixtures.sceneID(n) })
        XCTAssertEqual(Set(list.sceneIDs).count, 5)
        XCTAssertEqual(list.cues.map(\.label), ["Cue A", "Cue B", "Cue C", "Cue D", "Cue E"])
    }

    func testPositionTextAndAvailability() throws {
        var list = try ShowFixtures.fiveCues()
        XCTAssertEqual(list.positionText, "Standby")
        XCTAssertTrue(list.canGoNext)
        XCTAssertFalse(list.canGoPrevious)
        list.go(to: ShowFixtures.uuid(2))
        XCTAssertEqual(list.positionText, "Cue 2 of 5")
        XCTAssertTrue(list.canGoNext)
        XCTAssertTrue(list.canGoPrevious)
        list.go(to: ShowFixtures.uuid(5))
        XCTAssertFalse(list.canGoNext)
        list.go(to: ShowFixtures.uuid(1))
        XCTAssertFalse(list.canGoPrevious)
    }

    func testEmptyShowAndUnknownCue() {
        var list = ShowCueList(id: ShowFixtures.showID)
        XCTAssertEqual(list.next().outcome, .empty)
        XCTAssertEqual(list.previous().outcome, .empty)
        XCTAssertFalse(list.canGoNext)
        XCTAssertFalse(list.canGoPrevious)
        XCTAssertEqual(list.go(to: ShowFixtures.uuid(1)).outcome, .unknownCue)
        XCTAssertEqual(list.position, .standby)
    }

    func testOneCueShow() throws {
        var list = ShowCueList(id: ShowFixtures.showID)
        try list.append(sceneID: ShowFixtures.sceneID(1), label: "Only", cueID: ShowFixtures.uuid(1))
        XCTAssertEqual(list.next().outcome, .moved)
        XCTAssertEqual(list.next().outcome, .atEnd)
        XCTAssertEqual(list.previous().outcome, .atStart)
        XCTAssertEqual(list.activeSceneID, ShowFixtures.sceneID(1))
    }
}
