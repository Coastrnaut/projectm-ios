// PerformancePadTests.swift — UIX-005-T04: the performance pad's Blackout target per output phase
// (UIX-005-R7, R8; research UIX-005-D5): exactly one B-key owner in each phase, and the tap's effect
// on the real ExternalDisplayCoordinator. No clock: the phases are read, not waited for.
import PresentationLifecycle
import XCTest
@testable import projectM_iOS

@MainActor
final class PerformancePadTests: XCTestCase {
    func testTheBlackoutTargetFollowsTheOutputPhase() {
        let live = PerformancePadBlackout.make(.live)
        XCTAssertEqual(live.title, "Black out output")
        XCTAssertTrue(live.blacksOut)
        XCTAssertTrue(live.isEnabled)
        XCTAssertTrue(live.carriesBKey, "B moves to the pad while SHOW-014's corner button is hidden")
        XCTAssertEqual(live.value, "Live")

        let fading = PerformancePadBlackout.make(.fadingIn)
        XCTAssertTrue(fading.blacksOut, "fading in can be blacked out again (as SHOW-014's button)")
        XCTAssertTrue(fading.carriesBKey)

        let black = PerformancePadBlackout.make(.blackedOut)
        XCTAssertEqual(black.title, "Restore output")
        XCTAssertFalse(black.blacksOut)
        XCTAssertTrue(black.isEnabled)
        XCTAssertFalse(black.carriesBKey, "the badge's Restore owns B while blacked out")
        XCTAssertEqual(black.value, "Blacked out")

        let waiting = PerformancePadBlackout.make(.restoreWaiting)
        XCTAssertEqual(waiting.title, "Restoring output")
        XCTAssertFalse(waiting.isEnabled)
        XCTAssertFalse(waiting.carriesBKey)
    }

    /// One B owner in every phase: the pad (live, fading in) or the badge (blacked out), never both.
    func testExactlyOneBKeyOwnerPerPhase() {
        let phases: [OutputBlackout.Phase] = [.live, .fadingIn, .blackedOut, .restoreWaiting]
        for phase in phases {
            let pad: Bool = PerformancePadBlackout.make(phase).carriesBKey
            let badge: Bool = phase.offersRestore
            XCTAssertFalse(pad && badge, "\(phase)")
        }
    }

    func testTheTargetTogglesTheOutput() {
        let external = ExternalDisplayCoordinator()
        PerformancePadBlackout.make(external.blackoutPhase).perform(external)
        XCTAssertEqual(external.blackoutPhase, .blackedOut, "one tap blacks out (OUT-010)")
        PerformancePadBlackout.make(external.blackoutPhase).perform(external)
        XCTAssertNotEqual(external.blackoutPhase, .blackedOut, "the second tap restores (fading in, or waiting for OUT-010-R7's spacing)")
    }

    func testTheLayoutFlagIsOffByDefault() {
        XCTAssertFalse(AppCoordinator.startsInPerformanceLayout, "session state, off at launch (UIX-005-R1)")
    }
}
