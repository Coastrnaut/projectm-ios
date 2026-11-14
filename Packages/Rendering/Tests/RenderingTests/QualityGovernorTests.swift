// Task T100: thermal and low-power adaptation (FR-049). Each thermal state maps to settings that
// lower the frame rate or the render scale, never below 30 fps; Low Power Mode caps at 30 fps.
// Audio state and labels are not inputs, so they cannot be affected.
import XCTest
@testable import Rendering

final class QualityGovernorTests: XCTestCase {
    func testNominalAndFairRunAtFullQuality() {
        for state in [ThermalLevel.nominal, .fair] {
            let s = QualityGovernor.settings(thermal: state, lowPower: false)
            XCTAssertEqual(s, QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0), "\(state)")
        }
    }

    func testSeriousDropsToThirtyFramesPerSecond() {
        XCTAssertEqual(QualityGovernor.settings(thermal: .serious, lowPower: false),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 1.0))
    }

    func testCriticalAlsoLowersTheRenderScale() {
        XCTAssertEqual(QualityGovernor.settings(thermal: .critical, lowPower: false),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
    }

    func testLowPowerModeCapsAtThirty() {
        XCTAssertEqual(QualityGovernor.settings(thermal: .nominal, lowPower: true),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 1.0))
        XCTAssertEqual(QualityGovernor.settings(thermal: .critical, lowPower: true),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
    }

    func testNeverBelowThirtyFramesPerSecond() {
        for state in ThermalLevel.allCases {
            for lowPower in [false, true] {
                XCTAssertGreaterThanOrEqual(QualityGovernor.settings(thermal: state, lowPower: lowPower).maxFramesPerSecond, 30)
            }
        }
    }

    /// PERF-003-R7: with an adaptable effect on, serious keeps 60 fps (the effect steps down first); critical and Low
    /// Power cap as before. Without one the table is exactly the two-argument one.
    func testAdaptiveEffectsDeferTheSeriousCapOnly() {
        for state in ThermalLevel.allCases {
            for lowPower in [false, true] {
                XCTAssertEqual(QualityGovernor.settings(thermal: state, lowPower: lowPower, adaptiveEffects: false),
                               QualityGovernor.settings(thermal: state, lowPower: lowPower), "\(state) \(lowPower)")
            }
        }
        XCTAssertEqual(QualityGovernor.settings(thermal: .nominal, lowPower: false, adaptiveEffects: true), .full)
        XCTAssertEqual(QualityGovernor.settings(thermal: .serious, lowPower: false, adaptiveEffects: true), .full)
        XCTAssertEqual(QualityGovernor.settings(thermal: .critical, lowPower: false, adaptiveEffects: true),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
        XCTAssertEqual(QualityGovernor.settings(thermal: .serious, lowPower: true, adaptiveEffects: true),
                       QualitySettings(maxFramesPerSecond: 30, renderScale: 1.0))
    }

    func testFrameRateRangeFollowsTheSettings() {
        let full = QualitySettings(maxFramesPerSecond: 60, renderScale: 1).frameRateRange
        XCTAssertEqual(full.minimum, 30)
        XCTAssertEqual(full.maximum, 60)
        let capped = QualitySettings(maxFramesPerSecond: 30, renderScale: 1).frameRateRange
        XCTAssertEqual(capped.maximum, 30)
        XCTAssertEqual(capped.minimum, 30)
    }

    func testThermalLevelFromProcessInfo() {
        XCTAssertEqual(ThermalLevel(ProcessInfo.ThermalState.nominal), .nominal)
        XCTAssertEqual(ThermalLevel(ProcessInfo.ThermalState.fair), .fair)
        XCTAssertEqual(ThermalLevel(ProcessInfo.ThermalState.serious), .serious)
        XCTAssertEqual(ThermalLevel(ProcessInfo.ThermalState.critical), .critical)
    }
}
