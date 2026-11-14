// FX-020-T12, T17: the effect order and preset settings, Color's on/off switch, scene capture and restore of the chain,
// and a real host's compositor (FX-020-R8 to R10).
import Compositor
import FlashSafety
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class EffectChainSettingTests: XCTestCase {
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "EffectChainSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    private let colorFirst = OutputEffectOrder([.grade, .trails])

    func testOrderPersistsAndStandardStoresNothing() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            XCTAssertEqual(chain.order, .standard)
            var reported: [OutputEffectOrder] = []
            chain.onChange = { (order: OutputEffectOrder) -> Void in reported.append(order) }
            chain.order = colorFirst
            XCTAssertEqual(defaults.string(forKey: EffectChainSetting.orderKey), "fx.grade,fx.trails")
            XCTAssertEqual(EffectChainSetting(defaults: defaults).order, colorFirst, "kept across a relaunch")
            chain.order = .standard
            XCTAssertNil(defaults.object(forKey: EffectChainSetting.orderKey))
            XCTAssertEqual(reported, [colorFirst, .standard])
            XCTAssertEqual(EffectChainSetting.summary(colorFirst), "Color \u{2192} Trails")
        }
    }

    func testColorOffGivesNeutralAndKeepsValues() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let grade = ColorGradeSetting(defaults: defaults)
            XCTAssertTrue(grade.isEnabled, "on by default")
            grade.gamma = 1.5
            grade.isEnabled = false
            XCTAssertEqual(grade.effectiveGrade(clamp: .standard), .neutral)
            XCTAssertEqual(grade.gamma, 1.5, "values kept")
            let reloaded = ColorGradeSetting(defaults: defaults)
            XCTAssertFalse(reloaded.isEnabled)
            reloaded.resetToNeutral()
            XCTAssertTrue(reloaded.isEnabled)
            XCTAssertNil(defaults.object(forKey: ColorGradeSetting.enabledKey))
        }
    }

    func testPresetsPersistAndApplyThroughTheSettings() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            chain.order = colorFirst
            grade.saturation = 0.5
            trails.isEnabled = true
            trails.halfLifeSeconds = 0.4
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled, trails: trails.feedback)
            XCTAssertTrue(chain.savePreset(name: "Soft", effects: live.entries(over: nil)))
            XCTAssertFalse(chain.savePreset(name: " ", effects: []))
            // Change everything, then apply the preset from a relaunched setting.
            chain.order = .standard
            grade.saturation = 1
            trails.isEnabled = false
            let relaunched = EffectChainSetting(defaults: defaults)
            let preset = try? XCTUnwrap(relaunched.presets.preset(named: "soft"))
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails)
            XCTAssertEqual(chain.order, colorFirst)
            XCTAssertEqual(grade.saturation, 0.5)
            XCTAssertEqual(trails.feedback, MotionFeedback(isEnabled: true, halfLifeSeconds: 0.4))
            relaunched.deletePreset(named: "Soft")
            XCTAssertNil(defaults.object(forKey: EffectChainSetting.presetsKey))
        }
    }

    func testSceneWritesTheListOnlyWhenNeededAndRestoreAppliesIt() {
        let defaultLive = SceneEffectSettings(order: .standard, grade: .neutral, gradeEnabled: true, trails: .off)
        XCTAssertNil(SceneAutosaveCapture.effects(defaultLive, carry: nil), "default chain: field left out")
        var reordered = defaultLive
        reordered.order = colorFirst
        let written = SceneAutosaveCapture.effects(reordered, carry: nil)
        XCTAssertEqual(written?.map(\.kind), ["fx.grade", "fx.trails"])
        let unknown = SceneEffectEntry(kind: "fx.future")
        XCTAssertEqual(SceneAutosaveCapture.effects(defaultLive, carry: [unknown])?.map(\.kind), ["fx.future", "fx.trails", "fx.grade"],
                       "a carried list is always written back, unknown entries kept")
        XCTAssertEqual(SceneAutosaveCapture.effects(nil, carry: [unknown]), [unknown])
        withDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails)
            XCTAssertEqual(chain.order, colorFirst)
            SceneAutosaveCapture.applyEffects(nil, chain: chain, grade: grade, trails: trails)
            XCTAssertEqual(chain.order, .standard, "a scene without a list restores the standard order")
        }
    }

    func testKeysAreBackedUpAndErased() {
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in EffectChainSetting.allKeys + [ColorGradeSetting.enabledKey] {
            XCTAssertTrue(included.contains(key), "\(key) is backed up and erased with Settings")
        }
    }

    func testHostCompositorTakesTheOrder() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.outputEffectOrder, .standard)
        AppCoordinator.apply(colorFirst, to: [host.compositor])
        XCTAssertEqual(host.compositor.outputEffectOrder, colorFirst)
    }
}
