// FX-007-T14: the directional blur setting, its readouts and ACC-005 sliders, the keys' policies, scene and preset round
// trips through the app's effect-chain paths, and a real host's compositor (FX-007-R9 to R11).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class DirectionalBlurSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "DirectionalBlurSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testOffByDefaultPersistedAndClamped() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = DirectionalBlurSetting(defaults: defaults)
            XCTAssertEqual(setting.blur, .off)
            for key in DirectionalBlurSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [DirectionalBlur] = []
            setting.onChange = { (value: DirectionalBlur) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.radius = 0.015
            setting.angleDegrees = 90
            XCTAssertEqual(reported.count, 3)
            let expected = DirectionalBlur(isEnabled: true, radius: 0.015, angleDegrees: 90)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(DirectionalBlurSetting(defaults: defaults).blur, expected, "kept across a relaunch")
            setting.radius = 5
            XCTAssertEqual(setting.radius, 0.02, "out of range → nearest bound")
            setting.angleDegrees = 225
            XCTAssertEqual(setting.angleDegrees, 45, "the axis folds into 0…180")
            setting.radius = .nan
            XCTAssertEqual(setting.radius, DirectionalBlur.defaultRadius)
        }
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: DirectionalBlurSetting.enabledKey)   // a number, not a Bool
            defaults.set("wide", forKey: DirectionalBlurSetting.radiusKey)
            XCTAssertFalse(DirectionalBlurSetting(defaults: defaults).isEnabled, "only a Bool turns it on")
            XCTAssertEqual(DirectionalBlurSetting(defaults: defaults).radius, DirectionalBlur.defaultRadius)
        }
    }

    func testReadoutsAndSliderSteps() {
        withDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(DirectionalBlurSetting.radiusText(0.005), "0.5%")
            XCTAssertEqual(DirectionalBlurSetting.angleText(45), "45\u{00B0}")
            XCTAssertEqual(DirectionalBlurParameterSpecs.radius.stepCount, 20)
            XCTAssertEqual(DirectionalBlurParameterSpecs.angle.stepCount, 12)
            let setting = DirectionalBlurSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(DirectionalBlurParameterSpecs.radius,
                                                        target: DirectionalBlurSection.radiusTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.radius, 0.006, accuracy: 1e-9, "one VoiceOver step is 0.1%")
            _ = AccessibleParameterAdjuster.adjust(DirectionalBlurParameterSpecs.angle,
                                                   target: DirectionalBlurSection.angleTarget(setting), direction: .increment)
            XCTAssertEqual(setting.angleDegrees, 15, accuracy: 1e-9)
        }
    }

    func testKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(DirectionalBlurSetting.allKeys, ["settings.directionalBlur.enabled", "settings.directionalBlur.radius",
                                                        "settings.directionalBlur.angle"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in DirectionalBlurSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.directionalBlur), "Directional blur")
    }

    func testSceneAndPresetRoundTripThroughTheAppPaths() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let blur = DirectionalBlurSetting(defaults: defaults)
            blur.isEnabled = true
            blur.radius = 0.01
            blur.angleDegrees = 30
            chain.order = OutputEffectOrder([.directionalBlur, .trails, .grade])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, directionalBlur: blur.blur)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.directionalBlur", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Streak", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            blur.isEnabled = false
            blur.radius = 0.002
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, directionalBlur: blur)
            XCTAssertEqual(blur.blur, DirectionalBlur(isEnabled: true, radius: 0.01, angleDegrees: 30))
            XCTAssertEqual(chain.order.effects, [.directionalBlur, .trails, .grade, .chromatic, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette])
            blur.isEnabled = false
            let preset = chain.presets.preset(named: "Streak")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, directionalBlur: blur)
            XCTAssertTrue(blur.isEnabled, "the preset turns it back on")
            // A scene without a blur entry leaves the blur alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, directionalBlur: blur)
            XCTAssertTrue(blur.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testHostCompositorTakesTheBlur() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.directionalBlur, .off)
        let on = DirectionalBlur(isEnabled: true, radius: 0.02)
        AppCoordinator.apply(directionalBlur: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.directionalBlur, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.directionalBlurFrames, 1)
        AppCoordinator.apply(directionalBlur: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsDirectionalBlurPicture, "off returns the picture to the shared pool")
    }
}
