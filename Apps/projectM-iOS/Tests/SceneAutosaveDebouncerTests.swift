// SceneAutosaveDebouncerTests.swift — SCN-002-T11: the quiet period and the maximum latency on a fake
// clock (SCN-002-R2; S4). No wall clock.
import XCTest
@testable import projectM_iOS

final class SceneAutosaveDebouncerTests: XCTestCase {
    func testBurstIsDueOneQuietPeriodAfterTheLastEdit() {
        var d = SceneAutosaveDebouncer()
        for i in 0..<10 { d.edit(at: Double(i) * 0.1) }
        XCTAssertEqual(d.deadline ?? 0, 1.9, accuracy: 1e-9)
        XCTAssertFalse(d.isDue(at: 1.85))
        XCTAssertTrue(d.isDue(at: 1.9))
    }

    func testContinuousEditsAreDueAtTheMaximumLatency() {
        var d = SceneAutosaveDebouncer()
        var t = 0.0
        while t < 5 {
            d.edit(at: t)
            XCTAssertFalse(d.isDue(at: t), "not due while editing at \(t)")
            t += 0.5
        }
        XCTAssertEqual(d.deadline ?? 0, 5, accuracy: 1e-9)
        XCTAssertTrue(d.isDue(at: 5))
    }

    func testResetClearsThePendingEdit() {
        var d = SceneAutosaveDebouncer()
        XCTAssertFalse(d.isPending)
        XCTAssertNil(d.deadline)
        d.edit(at: 3)
        XCTAssertTrue(d.isPending)
        d.reset()
        XCTAssertFalse(d.isPending)
        XCTAssertFalse(d.isDue(at: 100))
        XCTAssertEqual(d.edit(at: 10), 11, accuracy: 1e-9, "a new burst starts its own window")
    }
}
