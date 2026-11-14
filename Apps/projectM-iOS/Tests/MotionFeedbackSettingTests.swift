// FX-009-T15: the Trails setting, its ACC-012 caps, the Settings section's target, the keys' policies and a real host's
// compositor (FX-009-R5, R7, R9, R11).
import Compositor
import FlashSafety
import LibraryBackup
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class MotionFeedbackSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "MotionFeedbackSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testOffByDefaultAndPersisted() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = MotionFeedbackSetting(defaults: defaults)
            XCTAssertEqual(setting.feedback, .off)
            for key in MotionFeedbackSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [MotionFeedback] = []
            setting.onChange = { (value: MotionFeedback) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.halfLifeSeconds = 0.35
            XCTAssertEqual(reported.last, MotionFeedback(isEnabled: true, halfLifeSeconds: 0.35))
            XCTAssertEqual(reported.count, 2)
            let reloaded = MotionFeedbackSetting(defaults: defaults)
            XCTAssertEqual(reloaded.feedback, MotionFeedback(isEnabled: true, halfLifeSeconds: 0.35), "kept across a relaunch")
        }
    }

    func testReadRuleAndClamping() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: MotionFeedbackSetting.enabledKey)   // a number, not a Bool
            defaults.set(Double.nan, forKey: MotionFeedbackSetting.halfLifeKey)
            XCTAssertEqual(MotionFeedbackSetting(defaults: defaults).feedback, .off, "only a Bool turns it on; NaN → 0.20")
            defaults.set(true, forKey: MotionFeedbackSetting.halfLifeKey)
            XCTAssertEqual(MotionFeedbackSetting(defaults: defaults).halfLifeSeconds, 0.20, "a Bool length → 0.20")
            defaults.set("long", forKey: MotionFeedbackSetting.halfLifeKey)
            XCTAssertEqual(MotionFeedbackSetting(defaults: defaults).halfLifeSeconds, 0.20)
            defaults.set(9.0, forKey: MotionFeedbackSetting.halfLifeKey)
            let setting = MotionFeedbackSetting(defaults: defaults)
            XCTAssertEqual(setting.halfLifeSeconds, 0.5, "out of range → nearest bound")
            setting.halfLifeSeconds = 0.01
            XCTAssertEqual(setting.halfLifeSeconds, 0.05)
            XCTAssertEqual(defaults.double(forKey: MotionFeedbackSetting.halfLifeKey), 0.05)
            setting.halfLifeSeconds = .nan
            XCTAssertEqual(setting.halfLifeSeconds, 0.20, "NaN → the default")
        }
    }

    func testSafetyCapsAndCapNote() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = MotionFeedbackSetting(defaults: defaults)
            setting.isEnabled = true
            setting.halfLifeSeconds = 0.5
            XCTAssertEqual(setting.effective(clamp: .standard), setting.feedback, "Standard: unchanged")
            let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
            XCTAssertEqual(setting.effective(clamp: strict).halfLifeSeconds, 0.125, accuracy: 1e-12)
            let reduce = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
            XCTAssertEqual(setting.effective(clamp: reduce).halfLifeSeconds, 0.25, accuracy: 1e-12)
            XCTAssertEqual(MotionFeedbackSetting.capText(user: setting.feedback, effective: setting.effective(clamp: strict)),
                           "Your safety settings shorten Trails to 0.13 s.")
            XCTAssertEqual(MotionFeedbackSetting.capText(user: setting.feedback, effective: setting.feedback), "")
            let none = SensorySafetyLimits(flashesPerSecond: 1, riseLimitPerSecond: 0.1, intensityLimit: 0)
            let zero = SafetyClamp(profile: SensorySafetyProfile(preset: .custom, custom: none), reduceFlashingSetting: false)
            XCTAssertFalse(setting.effective(clamp: zero).isActive)
            XCTAssertEqual(MotionFeedbackSetting.capText(user: setting.feedback, effective: setting.effective(clamp: zero)),
                           "Your safety settings turn Trails off.")
        }
    }

    func testReadoutSpokenValueAndSlider() {
        withDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(MotionFeedbackSetting.halfLifeText(0.2), "0.20 s")
            XCTAssertEqual(MotionFeedbackSetting.halfLifeText(0.125), "0.13 s")
            XCTAssertEqual(SpokenValueFormatter.text(0.2, unit: .seconds), "0.2 seconds")
            XCTAssertEqual(SpokenValueFormatter.text(0.25, unit: .seconds), "0.25 seconds")
            XCTAssertEqual(TrailsParameterSpecs.length.stepCount, 9)
            let setting = MotionFeedbackSetting(defaults: defaults)
            let result = AccessibleParameterAdjuster.adjust(TrailsParameterSpecs.length, target: TrailsSection.target(setting),
                                                            direction: .increment)
            XCTAssertTrue(result.moved)
            XCTAssertEqual(setting.halfLifeSeconds, 0.25, accuracy: 1e-9, "one VoiceOver step is 0.05 s")
        }
    }

    func testKeysAreInTheBackupPolicyAndTheUITestReset() {
        XCTAssertEqual(MotionFeedbackSetting.allKeys, ["settings.feedback.enabled", "settings.feedback.halfLife"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in MotionFeedbackSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased with Settings") }
    }

    func testHostCompositorTakesTrailsAndResetsOnASceneChange() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.motionFeedback, .off)
        let on = MotionFeedback(isEnabled: true, halfLifeSeconds: 0.3)
        AppCoordinator.apply(on, to: [host.compositor])
        XCTAssertEqual(host.compositor.motionFeedback, on)
        func frame(_ k: UInt64) throws {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertNotNil(host.compositor.encodeScene(width: 16, height: 16, commandBuffer: commands,
                                                        presentationTimeNanoseconds: 1_000_000_000 + k * 16_666_667,
                                                        contentScale: 2, reduceFlashing: false, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
        }
        try frame(0)
        try frame(1)
        XCTAssertEqual(host.compositor.trailsResets, 1, "the first active frame starts clean")
        AppCoordinator.resetTrails([host.compositor])   // a cue apply, reopen or undo
        try frame(2)
        XCTAssertEqual(host.compositor.trailsResets, 2, "the next frame shows the new scene only")
        XCTAssertEqual(host.compositor.trailsFrames, 3)
        AppCoordinator.apply(.off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsTrailsPictures, "off returns the pictures to the shared pool")
    }
}
