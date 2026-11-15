// FX-016-T14: the lens distortion setting, its readout and ACC-005 slider, the keys' policies, scene and preset round
// trips through the app's effect-chain paths, and a real host's compositor (FX-016-R8 to R10, S6, S7).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LensDistortionSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withLensDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "LensDistortionSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLensDistortionOffByDefaultPersistedAndClamped() {
        withLensDefaults { (defaults: UserDefaults) -> Void in
            let setting = LensDistortionSetting(defaults: defaults)
            XCTAssertEqual(setting.lens, .off)
            XCTAssertTrue(setting.zoomToFill, "zoom to fill is on by default")
            for key in LensDistortionSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [LensDistortion] = []
            setting.onChange = { (value: LensDistortion) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.strength = -0.6
            setting.zoomToFill = false
            XCTAssertEqual(reported.count, 3)
            let expected = LensDistortion(isEnabled: true, strength: -0.6, zoomToFill: false)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(LensDistortionSetting(defaults: defaults).lens, expected, "kept across a relaunch")
            setting.strength = 7
            XCTAssertEqual(setting.strength, 1, "out of range → nearest bound")
            setting.strength = .nan
            XCTAssertEqual(setting.strength, 0.3, "NaN → the default")
            XCTAssertEqual(LensDistortionSetting(defaults: defaults).strength, 0.3, "the clamped value is what is stored")
        }
        withLensDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: LensDistortionSetting.enabledKey)   // a number, not a Bool
            defaults.set("bulge", forKey: LensDistortionSetting.strengthKey)
            defaults.set("no", forKey: LensDistortionSetting.zoomToFillKey)
            let setting = LensDistortionSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.strength, LensDistortion.defaultStrength)
            XCTAssertTrue(setting.zoomToFill, "only a Bool turns zoom off")
            defaults.set(-9.0, forKey: LensDistortionSetting.strengthKey)
            XCTAssertEqual(LensDistortionSetting(defaults: defaults).strength, -1)
        }
    }

    func testLensDistortionReadoutSpokenValueAndSliderStep() {
        withLensDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(LensDistortionSetting.strengthText(0.3), "+30%")
            XCTAssertEqual(LensDistortionSetting.strengthText(0), "0%")
            XCTAssertEqual(LensDistortionSetting.strengthText(-1), "-100%")
            XCTAssertEqual(SpokenValueFormatter.text(0.3, unit: .percent(decimals: 0)), "30 percent")
            XCTAssertEqual(LensDistortionParameterSpecs.strength.stepCount, 200)
            let setting = LensDistortionSetting(defaults: defaults)
            let down = AccessibleParameterAdjuster.adjust(LensDistortionParameterSpecs.strength,
                                                          target: LensDistortionSection.strengthTarget(setting), direction: .decrement)
            XCTAssertTrue(down.moved)
            XCTAssertEqual(setting.strength, 0.29, accuracy: 1e-9, "one VoiceOver step is 1%")
        }
    }

    func testLensDistortionKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(LensDistortionSetting.allKeys, ["settings.lensDistortion.enabled", "settings.lensDistortion.strength",
                                                       "settings.lensDistortion.zoomToFill"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in LensDistortionSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.lensDistortion), "Lens distortion")
        XCTAssertEqual(OutputEffectOrder.standard.effects.firstIndex(of: .lensDistortion), 8, "after Edge outline")
    }

    func testLensDistortionSceneAndPresetRoundTripThroughTheAppPaths() {
        withLensDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let lens = LensDistortionSetting(defaults: defaults)
            lens.isEnabled = true
            lens.strength = -0.8
            lens.zoomToFill = false
            chain.order = OutputEffectOrder([.lensDistortion, .trails, .grade])
            var live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback)
            live.lensDistortion = lens.lens
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.lensDistortion", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Pinch", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            lens.isEnabled = false
            lens.strength = 0.5
            lens.zoomToFill = true
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, lensDistortion: lens)
            XCTAssertEqual(lens.lens, LensDistortion(isEnabled: true, strength: -0.8, zoomToFill: false))
            XCTAssertEqual(chain.order.effects.first, .lensDistortion)
            lens.isEnabled = false
            let preset = chain.presets.preset(named: "Pinch")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, lensDistortion: lens)
            XCTAssertTrue(lens.isEnabled, "the preset turns it back on")
            // A scene without a lens entry leaves the warp alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, lensDistortion: lens)
            XCTAssertTrue(lens.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testLensDistortionHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.lensDistortion, .off)
        let on = LensDistortion(isEnabled: true, strength: 0.7, zoomToFill: true)
        AppCoordinator.apply(lensDistortion: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.lensDistortion, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.lensDistortionFrames, 1)
        AppCoordinator.apply(lensDistortion: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsLensDistortionPicture, "off returns the picture to the shared pool")
    }
}
