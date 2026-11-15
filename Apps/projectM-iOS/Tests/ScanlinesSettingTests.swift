// FX-018-T11: the scanline setting, its readouts and ACC-005 sliders (spoken "3 pixels", "50 percent"; Thickness
// follows the spacing and is fixed at 1 for spacing 2), the keys' policies, scene and preset round trips through the
// app's effect-chain paths, and a real host's compositor (FX-018-R8 to R10).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class ScanlinesSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withScanlinesDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "ScanlinesSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testScanlinesOffByDefaultPersistedAndClamped() {
        withScanlinesDefaults { (defaults: UserDefaults) -> Void in
            let setting = ScanlinesSetting(defaults: defaults)
            XCTAssertEqual(setting.scanlines, .off)
            for key in ScanlinesSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [Scanlines] = []
            setting.onChange = { (value: Scanlines) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.spacing = 6
            setting.thickness = 4
            setting.intensity = 0.8
            setting.isVertical = true
            XCTAssertEqual(reported.count, 5)
            let expected = Scanlines(isEnabled: true, spacing: 6, thickness: 4, intensity: 0.8, isVertical: true)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(ScanlinesSetting(defaults: defaults).scanlines, expected, "kept across a relaunch")
            setting.spacing = 40
            XCTAssertEqual(setting.spacing, 16, "out of range → nearest bound")
            setting.intensity = .nan
            XCTAssertEqual(setting.intensity, 0.5, "NaN → the default")
            setting.thicknessValue = 30
            XCTAssertEqual(setting.thickness, 15, "at most spacing − 1")
            setting.spacing = 3
            XCTAssertEqual(setting.thickness, 2, "lowering the spacing lowers the thickness with it")
            XCTAssertEqual(ScanlinesSetting(defaults: defaults).thickness, 2, "and stores it")
            setting.spacingValue = 4.6
            XCTAssertEqual(setting.spacing, 5, "rounded to whole pixels")
        }
        withScanlinesDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: ScanlinesSetting.enabledKey)   // a number, not a Bool
            defaults.set("wide", forKey: ScanlinesSetting.spacingKey)
            defaults.set(9, forKey: ScanlinesSetting.thicknessKey)
            defaults.set(true, forKey: ScanlinesSetting.intensityKey)
            let setting = ScanlinesSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.spacing, Scanlines.defaultSpacing)
            XCTAssertEqual(setting.thickness, 2, "a stored thickness above spacing − 1 reads as spacing − 1")
            XCTAssertEqual(setting.intensity, Scanlines.defaultIntensity)
        }
    }

    func testScanlinesReadoutsSpokenValuesAndSliderSteps() {
        withScanlinesDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(ScanlinesSetting.pixelText(3), "3 px")
            XCTAssertEqual(ScanlinesSetting.percentText(0.5), "50%")
            XCTAssertEqual(SpokenValueFormatter.text(3, unit: .pixels), "3 pixels")
            XCTAssertEqual(SpokenValueFormatter.text(1, unit: .pixels), "1 pixel")
            XCTAssertEqual(SpokenValueFormatter.text(0.5, unit: ScanlinesParameterSpecs.intensity.unit), "50 percent")
            XCTAssertEqual(ScanlinesParameterSpecs.spacing.stepCount, 14)
            XCTAssertEqual(ScanlinesParameterSpecs.intensity.stepCount, 100)
            let setting = ScanlinesSetting(defaults: defaults)
            XCTAssertEqual(SpokenValueFormatter.text(ScanlinesSection.spacingTarget(setting).get(),
                                                     unit: ScanlinesParameterSpecs.spacing.unit), "3 pixels")
            let up = AccessibleParameterAdjuster.adjust(ScanlinesParameterSpecs.spacing,
                                                        target: ScanlinesSection.spacingTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.spacing, 4, "one VoiceOver step is one pixel")
            XCTAssertEqual(setting.thicknessRange, 1...3, "Thickness ranges 1…spacing − 1")
            XCTAssertTrue(setting.isThicknessAdjustable)
            setting.thickness = 3
            setting.spacing = 2
            XCTAssertEqual(setting.thickness, 1)
            XCTAssertFalse(setting.isThicknessAdjustable, "at spacing 2 the Thickness slider is disabled")
            XCTAssertEqual(setting.thicknessRange, 1...2, "and never has equal bounds")
        }
    }

    func testScanlinesKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(ScanlinesSetting.allKeys, ["settings.scanlines.enabled", "settings.scanlines.spacing",
                                                  "settings.scanlines.thickness", "settings.scanlines.intensity",
                                                  "settings.scanlines.vertical"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in ScanlinesSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.scanlines), "Scanlines")
        let order: [OutputEffectKind] = OutputEffectOrder.standard.effects
        XCTAssertGreaterThan(order.firstIndex(of: .scanlines) ?? -1, order.firstIndex(of: .vignette) ?? 99, "after Vignette")
    }

    func testScanlinesSceneAndPresetRoundTripThroughTheAppPaths() {
        withScanlinesDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let lines = ScanlinesSetting(defaults: defaults)
            lines.isEnabled = true
            lines.spacing = 8
            lines.thickness = 3
            lines.intensity = 0.9
            chain.order = OutputEffectOrder([.scanlines, .trails, .grade])
            var live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback)
            live.scanlines = lines.scanlines
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.scanlines", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "CRT", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            lines.isEnabled = false
            lines.spacing = 2
            lines.intensity = 0.1
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, scanlines: lines)
            XCTAssertEqual(lines.scanlines, Scanlines(isEnabled: true, spacing: 8, thickness: 3, intensity: 0.9))
            XCTAssertEqual(chain.order.effects.first, .scanlines)
            lines.isEnabled = false
            let preset = chain.presets.preset(named: "CRT")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, scanlines: lines)
            XCTAssertTrue(lines.isEnabled, "the preset turns it back on")
            // A scene with a thickness above spacing − 1 is applied as spacing − 1.
            let wide = SceneEffectEntry(kind: "fx.scanlines", enabled: true,
                                        parameters: ["spacing": .double(4), "thickness": .double(9)])
            SceneAutosaveCapture.applyEffects([wide], chain: chain, grade: grade, trails: trails, scanlines: lines)
            XCTAssertEqual(lines.spacing, 4)
            XCTAssertEqual(lines.thickness, 3)
            // A scene without a scanlines entry leaves them alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, scanlines: lines)
            XCTAssertTrue(lines.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testScanlinesHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.scanlines, .off)
        let on = Scanlines(isEnabled: true, spacing: 4, thickness: 2, intensity: 0.7)
        AppCoordinator.apply(scanlines: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.scanlines, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.scanlinesFrames, 1)
        AppCoordinator.apply(scanlines: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsScanlinesPicture, "off returns the picture to the shared pool")
    }
}
