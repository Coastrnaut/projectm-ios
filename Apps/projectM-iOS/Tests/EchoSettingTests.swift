// FX-010-T14: the Echo setting, its readouts and ACC-005 sliders, the cap on stored counts, ACC-012's effective value,
// the keys' policies, scene and preset round trips through the app's effect-chain paths, and a real host's compositor
// (FX-010-R4, R10, R12 to R14).
import Compositor
import FlashSafety
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class EchoSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "EchoSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testOffByDefaultPersistedAndCapped() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = EchoSetting(defaults: defaults)
            XCTAssertEqual(setting.feedback, .off)
            for key in EchoSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [EchoFeedback] = []
            setting.onChange = { (value: EchoFeedback) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.count = 2
            setting.delaySeconds = 0.25
            setting.decay = 0.75
            XCTAssertEqual(reported.count, 4)
            let expected = EchoFeedback(isEnabled: true, count: 2, delaySeconds: 0.25, decay: 0.75)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(EchoSetting(defaults: defaults).feedback, expected, "kept across a relaunch")
            setting.count = 9
            XCTAssertEqual(setting.count, 4, "above the cap → the cap")
            setting.delaySeconds = 5
            XCTAssertEqual(setting.delaySeconds, 0.5)
            setting.decay = .nan
            XCTAssertEqual(setting.decay, EchoFeedback.defaultDecay)
        }
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: EchoSetting.enabledKey)   // a number, not a Bool
            defaults.set(1000, forKey: EchoSetting.countKey)
            defaults.set("slow", forKey: EchoSetting.delayKey)
            let setting = EchoSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.count, 4, "a stored 1000 reads as the cap")
            XCTAssertEqual(setting.delaySeconds, EchoFeedback.defaultDelay)
        }
    }

    func testReadoutsSliderStepsAndSafetyCap() {
        withDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(EchoSetting.countText(3), "3")
            XCTAssertEqual(EchoSetting.delayText(0.1), "100 ms")
            XCTAssertEqual(EchoSetting.decayText(0.6), "0.60")
            XCTAssertEqual(EchoParameterSpecs.count.stepCount, 3)
            XCTAssertEqual(EchoParameterSpecs.delay.stepCount, 49)
            let setting = EchoSetting(defaults: defaults)
            _ = AccessibleParameterAdjuster.adjust(EchoParameterSpecs.count, target: EchoSection.countTarget(setting),
                                                   direction: .increment)
            XCTAssertEqual(setting.count, 4, "one VoiceOver step is one echo")
            XCTAssertFalse(AccessibleParameterAdjuster.adjust(EchoParameterSpecs.count, target: EchoSection.countTarget(setting),
                                                              direction: .increment).moved, "never past the cap")
            _ = AccessibleParameterAdjuster.adjust(EchoParameterSpecs.delay, target: EchoSection.delayTarget(setting),
                                                   direction: .increment)
            XCTAssertEqual(setting.delaySeconds, 0.11, accuracy: 1e-9, "one step is 10 ms")
            setting.isEnabled = true
            XCTAssertEqual(setting.effective(clamp: .standard), setting.feedback)
            let reduce = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
            XCTAssertEqual(setting.effective(clamp: reduce).weightCap, 0.5, "Reduce flashing halves the weight cap")
        }
    }

    func testKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(EchoSetting.allKeys, ["settings.echo.enabled", "settings.echo.count", "settings.echo.delay",
                                             "settings.echo.decay"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in EchoSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.echo), "Echo")
    }

    func testSceneAndPresetRoundTripThroughTheAppPaths() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let echo = EchoSetting(defaults: defaults)
            echo.isEnabled = true
            echo.count = 4
            echo.delaySeconds = 0.2
            chain.order = OutputEffectOrder([.echo, .trails, .grade])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, echo: echo.feedback)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.echo", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Ghosts", effects: live.entries(over: nil)))
            chain.order = .standard
            echo.isEnabled = false
            echo.count = 1
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, echo: echo)
            XCTAssertEqual(echo.feedback, EchoFeedback(isEnabled: true, count: 4, delaySeconds: 0.2))
            XCTAssertEqual(chain.order.effects, [.echo, .trails, .grade, .chromatic, .directionalBlur, .radialBlur, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .filmGrain])
            echo.isEnabled = false
            SceneAutosaveCapture.applyEffects(chain.presets.preset(named: "Ghosts")?.effects, chain: chain, grade: grade,
                                              trails: trails, echo: echo)
            XCTAssertTrue(echo.isEnabled, "the preset turns it back on")
            SceneAutosaveCapture.applyEffects([SceneEffectEntry(kind: "fx.trails", enabled: false)], chain: chain, grade: grade,
                                              trails: trails, echo: echo)
            XCTAssertTrue(echo.isEnabled, "a scene without an echo entry leaves it alone")
        }
    }

    func testHostCompositorTakesTheEcho() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.echoFeedback, .off)
        let on = EchoFeedback(isEnabled: true, count: 4, delaySeconds: 0.01)
        AppCoordinator.apply(echo: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.echoFeedback, on)
        for k in 0..<3 {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                        presentationTimeNanoseconds: 1_000_000_000 + UInt64(k) * 16_666_667,
                                                        contentScale: 2, reduceFlashing: false, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
        }
        XCTAssertEqual(host.compositor.echoStores, 3)
        XCTAssertEqual(host.compositor.echoFrames, 2, "echoes from the second frame on")
        XCTAssertEqual(host.compositor.echoHistoryTextures.count, EchoFeedback.cap)
        AppCoordinator.apply(echo: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsEchoPictures, "off returns every picture to the shared pool")
    }
}
