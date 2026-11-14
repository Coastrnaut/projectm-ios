// SensorySafetyTests.swift — ACC-012-T04: the clamp table on values (each preset × glow intensity,
// binding, speed and flash configuration), precedence, Standard identity and stored-value bounds
// (ACC-012-R1 to R7, S1, S3). Pure values; runs on Linux.
import XCTest
@testable import FlashSafety

final class SensorySafetyTests: XCTestCase {
    private struct Row {
        let preset: SensorySafetyPreset
        let glow: Float          // a manual glow intensity of 0.8 (range maximum 1)
        let bound: Double        // manual 0.5 driven to 1.0 by a binding, then capped at limit × 1
        let speed: Double        // speed 3 with a cap of 4
        let budget: Int
        let rise: Double?
        let override: Bool       // the renderer gets an explicit configuration
    }

    private let table: [Row] = [
        Row(preset: .standard, glow: 0.8, bound: 1.0, speed: 3, budget: 6, rise: nil, override: false),
        Row(preset: .reduced, glow: 0.5, bound: 0.5, speed: 2, budget: 4, rise: 0.25, override: false),
        Row(preset: .strict, glow: 0.25, bound: 0.25, speed: 1, budget: 2, rise: 0.10, override: true),
    ]

    func testClampTableForEveryPresetAndParameterType() {
        for row in table {
            let clamp = SafetyClamp(profile: SensorySafetyProfile(preset: row.preset), reduceFlashingSetting: false)
            XCTAssertEqual(clamp.intensity(0.8, maximum: 1), row.glow, accuracy: 1e-6, "\(row.preset) glow")
            let modulated: Double = clamp.modulated(manual: 0.5, modulated: 1.0)
            let bound: Float = clamp.intensity(Float(modulated), maximum: 1)
            XCTAssertEqual(Double(bound), row.bound, accuracy: 1e-6, "\(row.preset) binding")
            XCTAssertEqual(clamp.speed(3, cap: 4), row.speed, accuracy: 1e-12, "\(row.preset) speed")
            XCTAssertEqual(clamp.speed(-3, cap: 4), -row.speed, accuracy: 1e-12, "\(row.preset) negative speed")
            XCTAssertEqual(clamp.flashConfiguration.transitionBudget, row.budget, "\(row.preset) budget")
            XCTAssertEqual(clamp.flashConfiguration.riseRatePerSecond, row.rise, "\(row.preset) rise")
            XCTAssertEqual(clamp.flashLimitsOverride != nil, row.override, "\(row.preset) override")
        }
    }

    func testPresetsMapOntoFX019Configurations() {
        XCTAssertEqual(SensorySafetyLimits.standard.flashConfiguration, .alwaysOn)
        XCTAssertEqual(SensorySafetyLimits.reduced.flashConfiguration, .reduceFlashing)
        let strict: FlashEnvelopeConfiguration = SensorySafetyLimits.strict.flashConfiguration
        XCTAssertEqual(strict.luminanceThreshold, FlashEnvelopeConfiguration.alwaysOn.luminanceThreshold)
        XCTAssertEqual(strict.window, 1)
    }

    func testStandardIsTheIdentity() {
        let clamp = SafetyClamp.standard
        XCTAssertTrue(clamp.isIdentity)
        XCTAssertFalse(clamp.reducesFlashing)
        XCTAssertNil(clamp.flashLimitsOverride)
        let odd: [Float] = [0, 0.123_456_7, 0.8, 1, 5]
        for v in odd { XCTAssertEqual(clamp.intensity(v, maximum: 1).bitPattern, v.bitPattern) }
        XCTAssertEqual(clamp.modulated(manual: 0.3, modulated: 0.7).bitPattern, (0.7 as Double).bitPattern)
        XCTAssertEqual(clamp.speed(17, cap: 4), 17)
    }

    func testReduceFlashingRaisesTheFlashLimitOnly() {
        let standard = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
        XCTAssertEqual(standard.flashConfiguration, .reduceFlashing)
        XCTAssertNil(standard.flashLimitsOverride, "the renderer's own Reduce flashing path, unchanged")
        XCTAssertTrue(standard.reducesFlashing)
        XCTAssertEqual(standard.limits.intensityLimit, 1, "Reduce flashing never caps intensity (ACC-001-R5)")
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: true)
        XCTAssertEqual(strict.limits, .strict, "the stricter wins")
        let loose = SensorySafetyProfile(preset: .custom, custom: SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: 0.5,
                                                                                    intensityLimit: 0.9))
        let raised = SafetyClamp(profile: loose, reduceFlashingSetting: true)
        XCTAssertEqual(raised.limits.flashesPerSecond, 2)
        XCTAssertEqual(raised.limits.riseLimitPerSecond, 0.25)
        XCTAssertEqual(raised.limits.intensityLimit, 0.9)
    }

    func testAProfileStricterThanStandardTurnsReduceFlashingOn() {
        XCTAssertTrue(SafetyClamp(profile: SensorySafetyProfile(preset: .reduced), reduceFlashingSetting: false).reducesFlashing)
        XCTAssertTrue(SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false).reducesFlashing)
        let intensityOnly = SensorySafetyProfile(preset: .custom, custom: SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: nil,
                                                                                            intensityLimit: 0.4))
        XCTAssertFalse(SafetyClamp(profile: intensityOnly, reduceFlashingSetting: false).reducesFlashing)
    }

    func testCustomValuesAreClampedAndNeverLooserThanStandard() {
        let wild = SensorySafetyLimits(flashesPerSecond: 9, riseLimitPerSecond: 7, intensityLimit: 3)
        XCTAssertEqual(wild.flashesPerSecond, 3)
        XCTAssertEqual(wild.riseLimitPerSecond, 1.0)
        XCTAssertEqual(wild.intensityLimit, 1)
        let low = SensorySafetyLimits(flashesPerSecond: 0, riseLimitPerSecond: 0.001, intensityLimit: -1)
        XCTAssertEqual(low.flashesPerSecond, 1)
        XCTAssertEqual(low.riseLimitPerSecond, 0.05)
        XCTAssertEqual(low.intensityLimit, 0)
        let nan = SensorySafetyLimits(flashesPerSecond: 2, riseLimitPerSecond: .nan, intensityLimit: .nan)
        XCTAssertNil(nan.riseLimitPerSecond)
        XCTAssertEqual(nan.intensityLimit, 1)
        XCTAssertLessThanOrEqual(wild.flashConfiguration.transitionBudget, FlashEnvelopeConfiguration.alwaysOn.transitionBudget)
    }

    func testCustomProfileUsesItsOwnLimits() {
        let custom = SensorySafetyLimits(flashesPerSecond: 2, riseLimitPerSecond: 0.2, intensityLimit: 0.6)
        let clamp = SafetyClamp(profile: SensorySafetyProfile(preset: .custom, custom: custom), reduceFlashingSetting: false)
        XCTAssertEqual(clamp.limits, custom)
        XCTAssertEqual(clamp.intensity(0.9, maximum: 1), 0.6, accuracy: 1e-6)
        XCTAssertEqual(clamp.flashLimitsOverride?.riseRatePerSecond, 0.2)
    }
}
