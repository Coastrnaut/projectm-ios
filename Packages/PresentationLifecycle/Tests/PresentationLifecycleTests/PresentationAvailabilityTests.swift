// PERF-011-T02: the availability state machine (PERF-011-R1; data-model.md truth table).
import XCTest
@testable import PresentationLifecycle

final class PresentationAvailabilityTests: XCTestCase {
    private func state(backgrounded: Bool, locked: Bool) -> PresentationAvailability {
        var state = PresentationAvailability()
        if backgrounded { state.apply(.enteredBackground) }
        if locked { state.apply(.locked) }
        return state
    }

    func testStartsPresentable() {
        let state = PresentationAvailability()
        XCTAssertTrue(state.canPresent)
        XCTAssertFalse(state.isBackgrounded)
        XCTAssertFalse(state.isLocked)
    }

    /// Every state × every signal: (backgrounded, locked) before → after.
    func testTruthTable() {
        typealias Flags = (backgrounded: Bool, locked: Bool)
        let table: [(Flags, PresentationSignal, Flags)] = [
            ((false, false), .enteredBackground, (true, false)),
            ((false, false), .willEnterForeground, (false, false)),
            ((false, false), .locked, (false, true)),
            ((false, false), .unlocked, (false, false)),
            ((true, false), .enteredBackground, (true, false)),
            ((true, false), .willEnterForeground, (false, false)),
            ((true, false), .locked, (true, true)),
            ((true, false), .unlocked, (true, false)),
            ((false, true), .enteredBackground, (true, true)),
            ((false, true), .willEnterForeground, (false, false)),
            ((false, true), .locked, (false, true)),
            ((false, true), .unlocked, (false, false)),
            ((true, true), .enteredBackground, (true, true)),
            ((true, true), .willEnterForeground, (false, false)),
            ((true, true), .locked, (true, true)),
            ((true, true), .unlocked, (true, false)),
        ]
        XCTAssertEqual(table.count, 4 * PresentationSignal.allCases.count)
        for (before, signal, after) in table {
            var state = state(backgrounded: before.backgrounded, locked: before.locked)
            let result = state.apply(signal)
            XCTAssertEqual(state.isBackgrounded, after.backgrounded, "\(before) \(signal)")
            XCTAssertEqual(state.isLocked, after.locked, "\(before) \(signal)")
            XCTAssertEqual(state.canPresent, !after.backgrounded && !after.locked, "\(before) \(signal)")
            XCTAssertEqual(result, state.canPresent, "apply returns the new canPresent")
        }
    }

    func testUnlockWhileBackgroundedStaysUnavailable() {
        var state = PresentationAvailability()
        state.apply(.enteredBackground)
        state.apply(.locked)
        XCTAssertFalse(state.apply(.unlocked), "still in the background")
        XCTAssertTrue(state.apply(.willEnterForeground))
    }

    func testForegroundClearsALockWithoutAnUnlockSignal() {
        var state = PresentationAvailability()
        state.apply(.enteredBackground)
        state.apply(.locked)
        XCTAssertTrue(state.apply(.willEnterForeground), "entering the foreground proves frames can be presented")
        XCTAssertFalse(state.isLocked)
        XCTAssertTrue(state.apply(.unlocked), "a late unlock changes nothing")
    }

    func testLockInTheForegroundThenUnlock() {
        var state = PresentationAvailability()
        XCTAssertFalse(state.apply(.locked))
        XCTAssertTrue(state.apply(.unlocked))
    }
}
