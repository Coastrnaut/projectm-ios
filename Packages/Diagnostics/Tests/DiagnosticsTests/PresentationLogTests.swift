// PERF-011-T06: the presentation-transition signpost text (PERF-011-R12): a state word and counts.
#if canImport(os)
import XCTest
@testable import Diagnostics

final class PresentationLogTests: XCTestCase {
    func testSummaryCarriesTheStateAndTheCounts() {
        XCTAssertEqual(DiagnosticsLog.presentationSummary(canPresent: false, registered: 2, activeBefore: 2, activeAfter: 0),
                       "unavailable active 2 -> 0 of 2")
        XCTAssertEqual(DiagnosticsLog.presentationSummary(canPresent: true, registered: 3, activeBefore: 0, activeAfter: 3),
                       "available active 0 -> 3 of 3")
    }

    func testEmittingATransitionDoesNotTrap() {
        DiagnosticsLog.presentationTransition(canPresent: false, registered: 2, activeBefore: 2, activeAfter: 0)
        DiagnosticsLog.presentationTransition(canPresent: true, registered: 2, activeBefore: 0, activeAfter: 2)
    }
}
#endif
