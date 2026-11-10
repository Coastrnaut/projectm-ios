// Task T086: device auto-lock is suppressed only while the visualization runs in the foreground
// (FR-084), and restored when it is paused, stopped, or the app leaves the foreground.
import XCTest
@testable import projectM_iOS

final class IdleTimerPolicyTests: XCTestCase {
    func testSuppressedOnlyWhileRunningInTheForeground() {
        XCTAssertTrue(IdleTimerPolicy.suppressAutoLock(visualization: .running, appIsActive: true))
    }

    func testRestoredWhenPaused() {
        XCTAssertFalse(IdleTimerPolicy.suppressAutoLock(visualization: .paused, appIsActive: true))
    }

    func testRestoredWhenStoppedOrNotVisualizing() {
        XCTAssertFalse(IdleTimerPolicy.suppressAutoLock(visualization: .notVisualizing, appIsActive: true))
    }

    func testRestoredWhenSuspended() {
        XCTAssertFalse(IdleTimerPolicy.suppressAutoLock(visualization: .suspended, appIsActive: true))
    }

    func testRestoredWhenTheAppLeavesTheForeground() {
        for state in [VisualizationState.running, .paused, .suspended, .notVisualizing] {
            XCTAssertFalse(IdleTimerPolicy.suppressAutoLock(visualization: state, appIsActive: false), "\(state)")
        }
    }
}
