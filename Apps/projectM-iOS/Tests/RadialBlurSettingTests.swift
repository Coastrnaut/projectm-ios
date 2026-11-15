// FX-008-T14: the radial blur setting, its readouts and ACC-005 sliders, the keys' policies, scene and preset round
// trips through the app's effect-chain paths, and a real host's compositor (FX-008-R8 to R10).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class RadialBlurSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "RadialBlurSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testOffByDefaultPersistedAndClamped() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = RadialBlurSetting(defaults: defaults)
            XCTAssertEqual(setting.blur, .off)
            for key in RadialBlurSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [RadialBlur] = []
            setting.onChange = { (value: RadialBlur) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.strength = 0.2
            setting.focusX = 0.25
            setting.focusY = 0.75
            XCTAssertEqual(reported.count, 4)
            let expected = RadialBlur(isEnabled: true, strength: 0.2, focusX: 0.25, focusY: 0.75)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(RadialBlurSetting(defaults: defaults).blur, expected, "kept across a relaunch")
            setting.strength = 5
            XCTAssertEqual(setting.strength, 0.25, "out of range → nearest bound")
            setting.focusX = -1
            XCTAssertEqual(setting.focusX, 0)
            setting.focusY = .nan
            XCTAssertEqual(setting.focusY, 0.5)
        }
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: RadialBlurSetting.enabledKey)   // a number, not a Bool
            defaults.set("lots", forKey: RadialBlurSetting.strengthKey)
            XCTAssertFalse(RadialBlurSetting(defaults: defaults).isEnabled, "only a Bool turns it on")
            XCTAssertEqual(RadialBlurSetting(defaults: defaults).strength, RadialBlur.defaultStrength)
        }
    }

    func testReadoutsSpokenValuesAndSliderSteps() {
        withDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(RadialBlurSetting.percentText(0.1), "10%")
            XCTAssertEqual(RadialBlurSetting.percentText(0.5), "50%")
            XCTAssertEqual(SpokenValueFormatter.text(0.1, unit: .percent(decimals: 0)), "10 percent")
            XCTAssertEqual(RadialBlurParameterSpecs.strength.stepCount, 25)
            XCTAssertEqual(RadialBlurParameterSpecs.focusX.stepCount, 20)
            let setting = RadialBlurSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(RadialBlurParameterSpecs.strength,
                                                        target: RadialBlurSection.strengthTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.strength, 0.11, accuracy: 1e-9, "one VoiceOver step is 1%")
            _ = AccessibleParameterAdjuster.adjust(RadialBlurParameterSpecs.focusY,
                                                   target: RadialBlurSection.focusYTarget(setting), direction: .decrement)
            XCTAssertEqual(setting.focusY, 0.45, accuracy: 1e-9)
        }
    }

    func testKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(RadialBlurSetting.allKeys, ["settings.radialBlur.enabled", "settings.radialBlur.strength",
                                                   "settings.radialBlur.centerX", "settings.radialBlur.centerY"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in RadialBlurSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.radialBlur), "Radial blur")
    }

    func testSceneAndPresetRoundTripThroughTheAppPaths() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let radial = RadialBlurSetting(defaults: defaults)
            radial.isEnabled = true
            radial.strength = 0.15
            radial.focusX = 0.3
            chain.order = OutputEffectOrder([.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines, .filmGrain])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, radialBlur: radial.blur)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.radialBlur", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Zoom", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            radial.isEnabled = false
            radial.strength = 0.02
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, radialBlur: radial)
            XCTAssertEqual(radial.blur, RadialBlur(isEnabled: true, strength: 0.15, focusX: 0.3))
            XCTAssertEqual(chain.order.effects, [.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines, .filmGrain])
            radial.isEnabled = false
            let preset = chain.presets.preset(named: "Zoom")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, radialBlur: radial)
            XCTAssertTrue(radial.isEnabled, "the preset turns it back on")
            // A scene without a blur entry leaves the blur alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, radialBlur: radial)
            XCTAssertTrue(radial.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testHostCompositorTakesTheBlur() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.radialBlur, .off)
        let on = RadialBlur(isEnabled: true, strength: 0.25)
        AppCoordinator.apply(radialBlur: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.radialBlur, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.radialBlurFrames, 1)
        AppCoordinator.apply(radialBlur: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsRadialBlurPicture, "off returns the picture to the shared pool")
    }
}
