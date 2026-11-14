// FX-003-T12, T14, T15, FX-004-T09: the colour grade setting (and FX-004's hue), its ACC-012 gain cap, the Settings section's targets and the hosts
// (FX-003-R1, R8, R9).
import Compositor
import FlashSafety
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class ColorGradeSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "ColorGradeSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testNeutralByDefaultAndPersisted() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ColorGradeSetting(defaults: defaults)
            XCTAssertEqual(setting.grade, .neutral)
            XCTAssertTrue(setting.isNeutral)
            for key in ColorGradeSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [ColorGrade] = []
            setting.onChange = { (grade: ColorGrade) -> Void in reported.append(grade) }
            setting.temperature = 0.25
            setting.gain = 1.5
            setting.saturation = 0
            XCTAssertEqual(reported.last, ColorGrade(temperature: 0.25, gain: 1.5, saturation: 0))
            XCTAssertEqual(defaults.double(forKey: ColorGradeSetting.gainKey), 1.5)
            let reloaded = ColorGradeSetting(defaults: defaults)
            XCTAssertEqual(reloaded.grade, ColorGrade(temperature: 0.25, gain: 1.5, saturation: 0), "kept across a relaunch (0.0 is not a Bool)")
        }
    }

    func testReadRuleAndClamping() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set("warm", forKey: ColorGradeSetting.temperatureKey)
            defaults.set(Double.nan, forKey: ColorGradeSetting.gammaKey)
            defaults.set(9.0, forKey: ColorGradeSetting.gainKey)
            defaults.set(true, forKey: ColorGradeSetting.saturationKey)
            defaults.set(-1.0, forKey: ColorGradeSetting.liftKey)
            let setting = ColorGradeSetting(defaults: defaults)
            XCTAssertEqual(setting.grade, ColorGrade(temperature: 0, lift: -0.1, gamma: 1, gain: 2, saturation: 1))
            setting.saturation = 5
            XCTAssertEqual(setting.saturation, 2)
            XCTAssertEqual(defaults.double(forKey: ColorGradeSetting.saturationKey), 2)
            setting.lift = .nan
            XCTAssertEqual(setting.lift, 0, "NaN → neutral")
        }
    }

    func testResetToNeutralRemovesTheKeys() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ColorGradeSetting(defaults: defaults)
            setting.gamma = 1.4
            setting.lift = 0.02
            var last: ColorGrade?
            setting.onChange = { (grade: ColorGrade) -> Void in last = grade }
            setting.resetToNeutral()
            XCTAssertEqual(setting.grade, .neutral)
            XCTAssertEqual(last, .neutral)
            for key in ColorGradeSetting.allKeys { XCTAssertNil(defaults.object(forKey: key)) }
        }
    }

    func testReadouts() {
        XCTAssertEqual(ColorGradeSetting.temperatureText(0), "Neutral")
        XCTAssertEqual(ColorGradeSetting.temperatureText(0.25), "Warm 25")
        XCTAssertEqual(ColorGradeSetting.temperatureText(-1), "Cool 100")
        XCTAssertEqual(ColorGradeSetting.liftText(0.02), "+0.020")
        XCTAssertEqual(ColorGradeSetting.liftText(-0.05), "\u{2212}0.050")
        XCTAssertEqual(ColorGradeSetting.liftText(0), "0.000")
        XCTAssertEqual(ColorGradeSetting.gammaText(1), "1.00")
        XCTAssertEqual(ColorGradeSetting.gainText(1.5), "1.50\u{00D7}")
        XCTAssertEqual(ColorGradeSetting.saturationText(1), "100%")
    }

    func testSafetyProfileCapsOnlyTheGainBoost() {
        let grade = ColorGrade(temperature: 0.3, gain: 2, saturation: 1.5)
        XCTAssertEqual(ColorGradeSetting.effective(grade, clamp: .standard), grade, "Standard: unchanged")
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let capped: ColorGrade = ColorGradeSetting.effective(grade, clamp: strict)
        XCTAssertEqual(capped.gain, 1.25, accuracy: 1e-6, "Strict: 1 + 0.25 × (2 − 1)")
        XCTAssertEqual(capped.saturation, 1.5)
        XCTAssertEqual(ColorGradeSetting.effective(ColorGrade(gain: 0.6), clamp: strict).gain, 0.6, "dimming is never capped")
    }

    func testSectionTargetsWriteTheSetting() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ColorGradeSetting(defaults: defaults)
            let target: ParameterTarget = ColorGradeSection.target(setting, \.gain)
            let result = AccessibleParameterAdjuster.adjust(ColorGradeParameterSpecs.gain, target: target, direction: .increment)
            XCTAssertTrue(result.moved)
            XCTAssertEqual(setting.gain, 1.05, accuracy: 1e-9, "one VoiceOver step")
            XCTAssertEqual(ColorGradeParameterSpecs.all.count, 6)
            for spec in ColorGradeParameterSpecs.all { XCTAssertLessThanOrEqual(spec.stepCount, 60, spec.id) }
        }
    }

    // MARK: - FX-004: hue

    func testHuePersistsClampsAndResets() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ColorGradeSetting(defaults: defaults)
            XCTAssertEqual(setting.hue, 0)
            XCTAssertTrue(ColorGradeSetting.allKeys.contains(ColorGradeSetting.hueKey), "the UI-test reset removes it")
            XCTAssertEqual(ColorGradeSetting.hueKey, "settings.colorGrade.hue")
            var reported: ColorGrade?
            setting.onChange = { (grade: ColorGrade) -> Void in reported = grade }
            setting.hue = 30
            XCTAssertEqual(reported, ColorGrade(hue: 30))
            XCTAssertFalse(setting.isNeutral)
            XCTAssertEqual(defaults.double(forKey: ColorGradeSetting.hueKey), 30)
            XCTAssertEqual(ColorGradeSetting(defaults: defaults).hue, 30, "kept across a relaunch")
            setting.hue = -400
            XCTAssertEqual(setting.hue, -180, "clamped")
            setting.hue = .nan
            XCTAssertEqual(setting.hue, 0, "NaN → 0")
            setting.hue = 0
            XCTAssertEqual(ColorGradeSetting(defaults: defaults).hue, 0, "0.0 is not a Bool")
            setting.hue = 90
            setting.resetToNeutral()
            XCTAssertEqual(setting.hue, 0)
            XCTAssertNil(defaults.object(forKey: ColorGradeSetting.hueKey), "Reset to neutral removes the hue")
            defaults.set("red", forKey: ColorGradeSetting.hueKey)
            XCTAssertEqual(ColorGradeSetting(defaults: defaults).hue, 0, "not a number → 0")
            defaults.set(true, forKey: ColorGradeSetting.hueKey)
            XCTAssertEqual(ColorGradeSetting(defaults: defaults).hue, 0, "a Bool → 0")
        }
    }

    func testHueReadoutSpokenValueAndSlider() {
        XCTAssertEqual(ColorGradeSetting.hueText(0), "0\u{00B0}")
        XCTAssertEqual(ColorGradeSetting.hueText(30), "+30\u{00B0}")
        XCTAssertEqual(ColorGradeSetting.hueText(-120), "\u{2212}120\u{00B0}")
        XCTAssertEqual(ColorGradeSetting.hueText(-0.4), "0\u{00B0}")
        XCTAssertEqual(SpokenValueFormatter.text(30, unit: .signedDegrees), "plus 30 degrees")
        XCTAssertEqual(SpokenValueFormatter.text(-1, unit: .signedDegrees), "minus 1 degree")
        XCTAssertEqual(SpokenValueFormatter.text(0, unit: .signedDegrees), "0 degrees")
        let spec: AccessibleParameterSpec = ColorGradeParameterSpecs.hue
        XCTAssertEqual(spec.label, "Hue")
        XCTAssertEqual(spec.id, "colorHueSlider")
        XCTAssertEqual(spec.stepCount, 36)
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ColorGradeSetting(defaults: defaults)
            let target: ParameterTarget = ColorGradeSection.target(setting, \.hue)
            let result = AccessibleParameterAdjuster.adjust(spec, target: target, direction: .increment)
            XCTAssertTrue(result.moved)
            XCTAssertEqual(setting.hue, 10, accuracy: 1e-9, "one VoiceOver step is 10 degrees")
        }
    }

    func testSafetyProfileDoesNotCapTheHue() {
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let grade = ColorGrade(gain: 2, hue: -120)
        let capped: ColorGrade = ColorGradeSetting.effective(grade, clamp: strict)
        XCTAssertEqual(capped.hue, -120, "the hue keeps luminance, so ACC-012 leaves it (FX-004-R6)")
        XCTAssertEqual(ColorGradeSetting.effective(ColorGrade(hue: 45), clamp: strict), ColorGrade(hue: 45))
    }

    func testPhotoHostPassesTheGradeToItsCompositor() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.colorGrade, .neutral)
        host.colorGrade = ColorGrade(gamma: 1.2)
        XCTAssertEqual(host.compositor.colorGrade, ColorGrade(gamma: 1.2))
    }
}
