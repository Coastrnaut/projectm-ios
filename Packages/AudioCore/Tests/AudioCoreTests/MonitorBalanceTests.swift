// MonitorBalanceTests.swift — AUD-010-T03: the balance law and the stored value's validation
// (AUD-010-R2, R7).
import XCTest
@testable import AudioCore

final class MonitorBalanceTests: XCTestCase {
    func testLawAtFivePoints() {
        let cases: [(Double, Float, Float)] = [(-1, 1, 0), (-0.5, 1, 0.5), (0, 1, 1), (0.5, 0.5, 1), (1, 0, 1)]
        for (balance, left, right) in cases {
            let gains = MonitorBalance.gains(balance)
            XCTAssertEqual(gains.left, left, accuracy: 1e-6, "left at \(balance)")
            XCTAssertEqual(gains.right, right, accuracy: 1e-6, "right at \(balance)")
        }
    }

    func testNearSideIsNeverAboveUnity() {
        for step in -100...100 {
            let gains = MonitorBalance.gains(Double(step) / 100)
            XCTAssertLessThanOrEqual(max(gains.left, gains.right), 1)
            XCTAssertEqual(max(gains.left, gains.right), 1, accuracy: 1e-6, "one side always at unity")
        }
    }

    func testValidation() {
        XCTAssertEqual(MonitorBalance.validated(.nan), 0)
        XCTAssertEqual(MonitorBalance.validated(-3), -1)
        XCTAssertEqual(MonitorBalance.validated(.infinity), 1)
        XCTAssertEqual(MonitorBalance.validated(0.333), 0.33)
        XCTAssertEqual(MonitorBalance.validated(-0.305), -0.31, accuracy: 1e-12)
    }

    func testCentreDetent() {
        XCTAssertEqual(MonitorBalance.validated(0.03), 0)
        XCTAssertEqual(MonitorBalance.validated(-0.029), 0)
        XCTAssertEqual(MonitorBalance.validated(0.04), 0.04)
        XCTAssertEqual(MonitorBalance.gains(0.02).right, 1)
        XCTAssertEqual(MonitorBalance.gains(0.02).left, 1)
    }
}
