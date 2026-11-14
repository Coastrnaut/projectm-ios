// RecentPresetHistoryTests.swift — PRE-006-T02 (specs/159-pre-006-recent-history; R1, R2, R8): the
// recently played list's rules and the 3 s dwell, on an explicit clock (no wall-clock assertions).
import PresetLibrary
import XCTest

final class RecentPresetHistoryTests: XCTestCase {
    func testRecordingPutsTheNewestFirstWithoutDuplicates() {
        var history = RecentPresetHistory()
        history.record("pack/a.milk")
        history.record("pack/b.milk")
        history.record("pack/a.milk")
        history.record("")
        XCTAssertEqual(history.ids, ["pack/a.milk", "pack/b.milk"])
    }

    func testTheFiftyFirstDistinctIDDropsTheOldest() {
        var history = RecentPresetHistory()
        for index in 0...RecentPresetHistory.capacity { history.record("pack/\(index).milk") }
        XCTAssertEqual(history.ids.count, 50)
        XCTAssertEqual(history.ids.first, "pack/50.milk")
        XCTAssertEqual(history.ids.last, "pack/1.milk")
        XCTAssertFalse(history.ids.contains("pack/0.milk"))
        history.record("pack/1.milk")   // re-showing the oldest moves it to the front, nothing dropped
        XCTAssertEqual(history.ids.count, 50)
        XCTAssertEqual(history.ids.first, "pack/1.milk")
    }

    func testStoredValuesAreReadLeniently() {
        XCTAssertEqual(RecentPresetHistory(storedValue: nil).ids, [])
        XCTAssertEqual(RecentPresetHistory(storedValue: "pack/a.milk").ids, [])
        let mixed: [Any] = ["pack/a.milk", 7, "", "pack/b.milk", "pack/a.milk"]
        XCTAssertEqual(RecentPresetHistory(storedValue: mixed).ids, ["pack/a.milk", "pack/b.milk"])
        let long: [String] = (0..<80).map { (index: Int) -> String in "pack/\(index).milk" }
        XCTAssertEqual(RecentPresetHistory(storedValue: long).ids, Array(long.prefix(50)))
    }

    func testClearEmptiesTheList() {
        var history = RecentPresetHistory(ids: ["pack/a.milk"])
        history.clear()
        XCTAssertTrue(history.isEmpty)
    }

    func testADwellOfThreeSecondsCountsAndLessDoesNot() {
        var dwell = RecentPresetDwell()
        dwell.shown("pack/a.milk", at: 100)
        XCTAssertEqual(dwell.deadline, 103)
        XCTAssertNil(dwell.due(at: 102.9))
        XCTAssertEqual(dwell.due(at: 103), "pack/a.milk")
        XCTAssertNil(dwell.due(at: 200), "recorded once")
    }

    func testANewerPresetReplacesTheCandidateAndCancelDropsIt() {
        var dwell = RecentPresetDwell()
        dwell.shown("pack/a.milk", at: 10)
        dwell.shown("pack/b.milk", at: 11)   // a flick: a stayed 1 s
        XCTAssertNil(dwell.due(at: 13.5), "b has been on screen 2.5 s")
        XCTAssertEqual(dwell.due(at: 14), "pack/b.milk")
        dwell.shown("pack/c.milk", at: 20)
        dwell.cancel()
        XCTAssertNil(dwell.due(at: 30))
        XCTAssertNil(dwell.deadline)
    }
}
