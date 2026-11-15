// FX-014-T14: the edge outline setting, its readout and ACC-005 slider, the keys' policies, the ACC-012 colour scale,
// scene and preset round trips through the app's effect-chain paths, and a real host's compositor (FX-014-R9, R10,
// R11, R15).
import Compositor
import FlashSafety
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class EdgeOutlineSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withOutlineDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "EdgeOutlineSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testEdgeOutlineOffByDefaultPersistedAndClamped() {
        withOutlineDefaults { (defaults: UserDefaults) -> Void in
            let setting = EdgeOutlineSetting(defaults: defaults)
            XCTAssertEqual(setting.outline, .off)
            for key in EdgeOutlineSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [EdgeOutline] = []
            setting.onChange = { (value: EdgeOutline) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.threshold = 0.4
            setting.width = 2
            setting.color = EdgeOutlineColor(red: 1, green: 0, blue: 0)
            setting.mode = .outlineOnly
            XCTAssertEqual(reported.count, 5)
            let expected = EdgeOutline(isEnabled: true, threshold: 0.4, width: 2, color: EdgeOutlineColor(red: 1, green: 0, blue: 0),
                                       mode: .outlineOnly)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(defaults.string(forKey: EdgeOutlineSetting.colorKey), "FF0000")
            XCTAssertEqual(EdgeOutlineSetting(defaults: defaults).outline, expected, "kept across a relaunch")
            setting.threshold = 9
            XCTAssertEqual(setting.threshold, 1, "out of range → nearest bound")
            setting.width = 0
            XCTAssertEqual(setting.width, 1)
            setting.thresholdValue = 0.234
            XCTAssertEqual(setting.threshold, 0.23, accuracy: 1e-12, "the slider rounds to hundredths")
        }
        withOutlineDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: EdgeOutlineSetting.enabledKey)   // a number, not a Bool
            defaults.set("high", forKey: EdgeOutlineSetting.thresholdKey)
            defaults.set(true, forKey: EdgeOutlineSetting.widthKey)
            defaults.set("blue", forKey: EdgeOutlineSetting.colorKey)
            defaults.set("glow", forKey: EdgeOutlineSetting.modeKey)
            XCTAssertEqual(EdgeOutlineSetting(defaults: defaults).outline, .off, "unreadable values read as the defaults")
        }
    }

    func testEdgeOutlineReadoutSpokenValueSliderAndSafetyScale() {
        withOutlineDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(EdgeOutlineSetting.thresholdText(0.2), "0.20")
            XCTAssertEqual(SpokenValueFormatter.text(0.2, unit: .number(decimals: 2)), "0.20")
            XCTAssertEqual(EdgeOutlineParameterSpecs.threshold.stepCount, 98)
            let setting = EdgeOutlineSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(EdgeOutlineParameterSpecs.threshold,
                                                        target: EdgeOutlineSection.thresholdTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.threshold, 0.21, accuracy: 1e-9, "one VoiceOver step is one hundredth")
            setting.isEnabled = true
            XCTAssertEqual(setting.effective(clamp: .standard).colorScale, 1)
            let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
            XCTAssertEqual(setting.effective(clamp: strict).colorScale, 0.25, "ACC-012: the colour is scaled by the limit")
        }
    }

    func testEdgeOutlineKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(EdgeOutlineSetting.allKeys, ["settings.edgeOutline.enabled", "settings.edgeOutline.threshold",
                                                    "settings.edgeOutline.width", "settings.edgeOutline.color",
                                                    "settings.edgeOutline.mode"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in EdgeOutlineSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.edgeOutline), "Edge outline")
        XCTAssertEqual(OutputEffectOrder.standard.effects.firstIndex(of: .edgeOutline), 7, "after Mosaic")
    }

    func testEdgeOutlineSceneAndPresetRoundTripThroughTheAppPaths() {
        withOutlineDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let outline = EdgeOutlineSetting(defaults: defaults)
            outline.isEnabled = true
            outline.threshold = 0.5
            outline.width = 3
            outline.color = EdgeOutlineColor(red: 0, green: 1, blue: 0)
            chain.order = OutputEffectOrder([.edgeOutline, .trails, .grade])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, edgeOutline: outline.outline)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.edgeOutline", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Lines", effects: live.entries(over: nil)))
            let saved: EdgeOutline = outline.outline
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            outline.isEnabled = false
            outline.threshold = 0.1
            outline.width = 1
            outline.mode = .outlineOnly
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, edgeOutline: outline)
            XCTAssertEqual(outline.outline, saved)
            XCTAssertEqual(chain.order.effects.first, .edgeOutline)
            outline.isEnabled = false
            let preset = chain.presets.preset(named: "Lines")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, edgeOutline: outline)
            XCTAssertTrue(outline.isEnabled, "the preset turns it back on")
            // A scene without an outline entry leaves the outline alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, edgeOutline: outline)
            XCTAssertTrue(outline.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testEdgeOutlineHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.edgeOutline, .off)
        let on = EdgeOutline(isEnabled: true, threshold: 0.1, width: 2)
        AppCoordinator.apply(edgeOutline: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.edgeOutline, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.edgeOutlineFrames, 1)
        AppCoordinator.apply(edgeOutline: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsEdgeOutlinePicture, "off returns the picture to the shared pool")
    }
}
