// FX-006-T14: the chromatic split setting, its readouts and ACC-005 sliders, the keys' policies, scene and preset round
// trips through the app's effect-chain paths, and a real host's compositor (FX-006-R8 to R10).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class ChromaticSplitSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "ChromaticSplitSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testOffByDefaultPersistedAndClamped() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ChromaticSplitSetting(defaults: defaults)
            XCTAssertEqual(setting.split, .off)
            for key in ChromaticSplitSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [ChromaticSplit] = []
            setting.onChange = { (value: ChromaticSplit) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.amount = 0.015
            setting.angleDegrees = 90
            setting.isRadial = true
            XCTAssertEqual(reported.count, 4)
            let expected = ChromaticSplit(isEnabled: true, amount: 0.015, angleDegrees: 90, isRadial: true)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(ChromaticSplitSetting(defaults: defaults).split, expected, "kept across a relaunch")
            setting.amount = 5
            XCTAssertEqual(setting.amount, 0.02, "out of range → nearest bound")
            setting.angleDegrees = -45
            XCTAssertEqual(setting.angleDegrees, 315, "angles wrap")
            setting.amount = .nan
            XCTAssertEqual(setting.amount, ChromaticSplit.defaultAmount)
        }
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: ChromaticSplitSetting.enabledKey)   // a number, not a Bool
            defaults.set("wide", forKey: ChromaticSplitSetting.amountKey)
            XCTAssertFalse(ChromaticSplitSetting(defaults: defaults).isEnabled, "only a Bool turns it on")
            XCTAssertEqual(ChromaticSplitSetting(defaults: defaults).amount, ChromaticSplit.defaultAmount)
        }
    }

    func testReadoutsSpokenValuesAndSliderSteps() {
        withDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(ChromaticSplitSetting.amountText(0.005), "0.5%")
            XCTAssertEqual(ChromaticSplitSetting.angleText(45), "45\u{00B0}")
            XCTAssertEqual(SpokenValueFormatter.text(0.005, unit: .percent(decimals: 1)), "0.5 percent")
            XCTAssertEqual(ChromaticSplitParameterSpecs.amount.stepCount, 20)
            XCTAssertEqual(ChromaticSplitParameterSpecs.angle.stepCount, 24)
            let setting = ChromaticSplitSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(ChromaticSplitParameterSpecs.amount,
                                                        target: ChromaticSplitSection.amountTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.amount, 0.006, accuracy: 1e-9, "one VoiceOver step is 0.1%")
            _ = AccessibleParameterAdjuster.adjust(ChromaticSplitParameterSpecs.angle,
                                                   target: ChromaticSplitSection.angleTarget(setting), direction: .increment)
            XCTAssertEqual(setting.angleDegrees, 15, accuracy: 1e-9)
        }
    }

    func testKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(ChromaticSplitSetting.allKeys, ["settings.chromatic.enabled", "settings.chromatic.amount",
                                                       "settings.chromatic.angle", "settings.chromatic.radial"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in ChromaticSplitSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.summary(.standard),
                       "Trails \u{2192} Color \u{2192} Chromatic split \u{2192} Directional blur \u{2192} Radial blur \u{2192} Echo \u{2192} Mosaic \u{2192} Edge outline \u{2192} Lens distortion \u{2192} Vignette \u{2192} Scanlines")   // FX-007, FX-008 appended
    }

    func testSceneAndPresetRoundTripThroughTheAppPaths() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let chromatic = ChromaticSplitSetting(defaults: defaults)
            chromatic.isEnabled = true
            chromatic.amount = 0.01
            chromatic.angleDegrees = 30
            chain.order = OutputEffectOrder([.chromatic, .trails, .grade])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, chromatic: chromatic.split)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.chromatic", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Fringe", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            chromatic.isEnabled = false
            chromatic.amount = 0.002
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, chromatic: chromatic)
            XCTAssertEqual(chromatic.split, ChromaticSplit(isEnabled: true, amount: 0.01, angleDegrees: 30))
            XCTAssertEqual(chain.order.effects, [.chromatic, .trails, .grade, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .vignette, .scanlines])
            chromatic.isEnabled = false
            let preset = chain.presets.preset(named: "Fringe")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, chromatic: chromatic)
            XCTAssertTrue(chromatic.isEnabled, "the preset turns it back on")
            // A scene without a split entry leaves the split alone.
            let fx020 = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(fx020, chain: chain, grade: grade, trails: trails, chromatic: chromatic)
            XCTAssertTrue(chromatic.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testHostCompositorTakesTheSplit() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.chromaticSplit, .off)
        let on = ChromaticSplit(isEnabled: true, amount: 0.02)
        AppCoordinator.apply(chromatic: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.chromaticSplit, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.chromaticFrames, 1)
        AppCoordinator.apply(chromatic: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsChromaticPicture, "off returns the picture to the shared pool")
    }
}
