// PERF-008-T04, T14 (specs/201-perf-008-battery-saver): power profile budgets and their composition with the
// thermal/Low Power governor. Standard keeps FR-049's table exactly; Battery saver is a ceiling (30 fps, 0.75) the
// governor never exceeds and the 30 fps floor still holds; Follow Low Power Mode switches with Low Power.
import XCTest
@testable import Rendering

final class PowerProfileTests: XCTestCase {
    override func tearDown() {
        PowerProfileState.current = .standard
        super.tearDown()
    }

    func testBudgetsPerProfileAndLowPower() {
        for lowPower in [false, true] {
            XCTAssertEqual(PowerProfile.standard.budget(lowPower: lowPower), .standard)
            XCTAssertEqual(PowerProfile.batterySaver.budget(lowPower: lowPower), .batterySaver)
        }
        XCTAssertEqual(PowerProfile.followLowPowerMode.budget(lowPower: false), .standard, "US2: Low Power off")
        XCTAssertEqual(PowerProfile.followLowPowerMode.budget(lowPower: true), .batterySaver, "US2: Low Power on")
        XCTAssertEqual(PowerBudget.batterySaver,
                       PowerBudget(maxFramesPerSecond: 30, renderScaleCap: 0.75, allowsBackgroundWarmUp: false))
    }

    func testStoredValueFallsBackToStandard() {
        XCTAssertEqual(PowerProfile(stored: nil), .standard)
        XCTAssertEqual(PowerProfile(stored: "turbo"), .standard)
        XCTAssertEqual(PowerProfile(stored: "batterySaver"), .batterySaver)
    }

    /// The standard budget changes nothing: every cell of today's table is reproduced.
    func testStandardBudgetKeepsTodaysTable() {
        for thermal in ThermalLevel.allCases {
            for lowPower in [false, true] {
                for adaptive in [false, true] {
                    XCTAssertEqual(QualityGovernor.settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptive, budget: .standard),
                                   QualityGovernor.settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptive),
                                   "\(thermal) \(lowPower) \(adaptive)")
                }
            }
        }
    }

    /// R3: Battery saver is a ceiling; the governor can only lower further, never below 30 fps, and caps never compound.
    func testBatterySaverIsACeilingTheGovernorNeverExceeds() {
        for thermal in ThermalLevel.allCases {
            for lowPower in [false, true] {
                for adaptive in [false, true] {
                    let system = QualityGovernor.settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptive)
                    let saver = QualityGovernor.settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptive, budget: .batterySaver)
                    let label = "\(thermal) \(lowPower) \(adaptive)"
                    XCTAssertEqual(saver.maxFramesPerSecond, 30, label)
                    XCTAssertEqual(saver.renderScale, 0.75, label)
                    XCTAssertLessThanOrEqual(saver.maxFramesPerSecond, system.maxFramesPerSecond, label)
                    XCTAssertLessThanOrEqual(saver.renderScale, system.renderScale, label)
                }
            }
        }
        let floor = PowerBudget(maxFramesPerSecond: 10, renderScaleCap: 0.5, allowsBackgroundWarmUp: false)
        XCTAssertEqual(QualityGovernor.settings(thermal: .nominal, lowPower: false, adaptiveEffects: false, budget: floor),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 0.5), "the 30 fps floor holds under any budget")
    }

    /// The state posts once per real change (on the main thread) and never for the same value.
    func testStateChangePostsOncePerChange() {
        nonisolated(unsafe) var posts = 0
        let token = NotificationCenter.default.addObserver(forName: PowerProfileState.didChangeNotification, object: nil,
                                                           queue: nil) { (_: Notification) in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        PowerProfileState.current = .batterySaver
        PowerProfileState.current = .batterySaver
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(PowerProfileState.budget(lowPower: false), .batterySaver)
        PowerProfileState.current = .standard
        XCTAssertEqual(posts, 2)
        XCTAssertTrue(QualityGovernor.changeNotifications.contains(PowerProfileState.didChangeNotification))
    }
}
