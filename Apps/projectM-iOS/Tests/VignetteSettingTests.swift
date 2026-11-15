// FX-015-T11: the vignette setting, its readouts and ACC-005 sliders, the keys' policies, scene and preset round trips
// through the app's effect-chain paths, and a real host's compositor (FX-015-R8 to R10).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class VignetteSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withVignetteDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "VignetteSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testVignetteOffByDefaultPersistedAndClamped() {
        withVignetteDefaults { (defaults: UserDefaults) -> Void in
            let setting = VignetteSetting(defaults: defaults)
            XCTAssertEqual(setting.vignette, .off)
            for key in VignetteSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [Vignette] = []
            setting.onChange = { (value: Vignette) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.intensity = 0.8
            setting.softness = 0.3
            setting.centerX = 0.25
            setting.centerY = 0.75
            XCTAssertEqual(reported.count, 5)
            let expected = Vignette(isEnabled: true, intensity: 0.8, softness: 0.3, centerX: 0.25, centerY: 0.75)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(VignetteSetting(defaults: defaults).vignette, expected, "kept across a relaunch")
            setting.intensity = 7
            XCTAssertEqual(setting.intensity, 1, "out of range → nearest bound")
            setting.softness = 0
            XCTAssertEqual(setting.softness, 0.1)
            setting.centerX = .nan
            XCTAssertEqual(setting.centerX, 0.5, "NaN → the default")
            XCTAssertEqual(VignetteSetting(defaults: defaults).softness, 0.1, "the clamped value is what is stored")
        }
        withVignetteDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: VignetteSetting.enabledKey)   // a number, not a Bool
            defaults.set("dark", forKey: VignetteSetting.intensityKey)
            defaults.set(true, forKey: VignetteSetting.softnessKey)
            defaults.set(9.0, forKey: VignetteSetting.centerYKey)
            let setting = VignetteSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.intensity, Vignette.defaultIntensity)
            XCTAssertEqual(setting.softness, Vignette.defaultSoftness)
            XCTAssertEqual(setting.centerY, 1)
        }
    }

    func testVignetteReadoutsSpokenValuesAndSliderSteps() {
        withVignetteDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(VignetteSetting.percentText(0.5), "50%")
            XCTAssertEqual(VignetteSetting.fractionText(0.5), "0.50")
            XCTAssertEqual(VignetteSetting.fractionText(0.05), "0.05")
            XCTAssertEqual(VignetteSetting.fractionText(1), "1.00")
            XCTAssertEqual(SpokenValueFormatter.text(0.5, unit: .percent(decimals: 0)), "50 percent")
            XCTAssertEqual(VignetteParameterSpecs.intensity.stepCount, 100)
            XCTAssertEqual(VignetteParameterSpecs.centerX.stepCount, 20)
            let setting = VignetteSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(VignetteParameterSpecs.intensity,
                                                        target: VignetteSection.intensityTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.intensity, 0.51, accuracy: 1e-9, "one VoiceOver step is 1%")
        }
    }

    func testVignetteKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(VignetteSetting.allKeys, ["settings.vignette.enabled", "settings.vignette.intensity",
                                                 "settings.vignette.softness", "settings.vignette.centerX",
                                                 "settings.vignette.centerY"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in VignetteSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.vignette), "Vignette")
        XCTAssertEqual(OutputEffectOrder.standard.effects.firstIndex(of: .vignette), 9, "appended after Lens distortion (FX-017 follows)")
    }

    func testVignetteSceneAndPresetRoundTripThroughTheAppPaths() {
        withVignetteDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let vignette = VignetteSetting(defaults: defaults)
            vignette.isEnabled = true
            vignette.intensity = 0.9
            vignette.centerX = 0.3
            chain.order = OutputEffectOrder([.vignette, .trails, .grade])
            var live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback)
            live.vignette = vignette.vignette
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.vignette", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Frame", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            vignette.isEnabled = false
            vignette.intensity = 0.1
            vignette.centerX = 0.9
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, vignette: vignette)
            XCTAssertEqual(vignette.vignette, Vignette(isEnabled: true, intensity: 0.9, softness: 0.5, centerX: 0.3, centerY: 0.5))
            XCTAssertEqual(chain.order.effects.first, .vignette)
            vignette.isEnabled = false
            let preset = chain.presets.preset(named: "Frame")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, vignette: vignette)
            XCTAssertTrue(vignette.isEnabled, "the preset turns it back on")
            // A scene without a vignette entry leaves the vignette alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, vignette: vignette)
            XCTAssertTrue(vignette.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testVignetteHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.vignette, .off)
        let on = Vignette(isEnabled: true, intensity: 0.7, softness: 0.4)
        AppCoordinator.apply(vignette: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.vignette, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.vignetteFrames, 1)
        AppCoordinator.apply(vignette: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsVignettePicture, "off returns the picture to the shared pool")
    }
}
