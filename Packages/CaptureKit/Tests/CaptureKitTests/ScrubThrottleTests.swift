// ScrubThrottleTests.swift — at most 10 seeks per second while the scrubber is dragged
// (AUD-006-T11; AUD-006-R12).
import XCTest
@testable import CaptureKit

final class ScrubThrottleTests: XCTestCase {
    func testFirstValuePassesThenOnlyEveryTenthOfASecond() {
        var throttle = ScrubThrottle()
        XCTAssertTrue(throttle.shouldSeek(at: 100.00))
        XCTAssertFalse(throttle.shouldSeek(at: 100.01))
        XCTAssertFalse(throttle.shouldSeek(at: 100.099))
        XCTAssertTrue(throttle.shouldSeek(at: 100.10))
        XCTAssertFalse(throttle.shouldSeek(at: 100.15))
        XCTAssertTrue(throttle.shouldSeek(at: 100.21))
    }

    func testAtMostTenPerSecond() {
        var throttle = ScrubThrottle()
        var accepted = 0
        var time = 0.0
        while time < 1.0 {                              // a value every millisecond for one second
            if throttle.shouldSeek(at: time) { accepted += 1 }
            time += 0.001
        }
        XCTAssertLessThanOrEqual(accepted, 10)
        XCTAssertGreaterThanOrEqual(accepted, 9)
    }

    func testResetReArmsAndAClockGoingBackwardsDoesNotBlock() {
        var throttle = ScrubThrottle()
        XCTAssertTrue(throttle.shouldSeek(at: 5))
        throttle.reset()
        XCTAssertTrue(throttle.shouldSeek(at: 5.001))
        XCTAssertTrue(throttle.shouldSeek(at: 1), "a clock that jumped back does not block seeking")
        XCTAssertEqual(ScrubThrottle.minimumInterval, 0.1)
    }
}
