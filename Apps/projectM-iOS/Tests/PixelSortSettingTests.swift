// FX-011-T10: the pixel sort setting, its readout and ACC-005 slider, the keys' policies, scene and preset round trips
// through the app's effect-chain paths, and a real host's compositor (FX-011-R9, R10, S7).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class PixelSortSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withSortDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "PixelSortSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testPixelSortOffByDefaultPersistedAndClamped() {
        withSortDefaults { (defaults: UserDefaults) -> Void in
            let setting = PixelSortSetting(defaults: defaults)
            XCTAssertEqual(setting.sort, .off)
            for key in PixelSortSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [PixelSort] = []
            setting.onChange = { (value: PixelSort) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.threshold = 0.25
            setting.span = 8
            setting.direction = .vertical
            XCTAssertEqual(reported.count, 4)
            let expected = PixelSort(isEnabled: true, threshold: 0.25, span: 8, direction: .vertical)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(PixelSortSetting(defaults: defaults).sort, expected, "kept across a relaunch")
            setting.threshold = 7
            XCTAssertEqual(setting.threshold, 1, "out of range → nearest bound")
            setting.threshold = .nan
            XCTAssertEqual(setting.threshold, 0.5, "NaN → the default")
            setting.span = 40
            XCTAssertEqual(setting.span, 32, "rounded down to a choice")
            setting.span = 1
            XCTAssertEqual(setting.span, 4)
            XCTAssertEqual(PixelSortSetting(defaults: defaults).span, 4, "the valid value is what is stored")
        }
        withSortDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: PixelSortSetting.enabledKey)   // a number, not a Bool
            defaults.set("dark", forKey: PixelSortSetting.thresholdKey)
            defaults.set(true, forKey: PixelSortSetting.spanKey)
            defaults.set("diagonal", forKey: PixelSortSetting.directionKey)
            let setting = PixelSortSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.threshold, PixelSort.defaultThreshold)
            XCTAssertEqual(setting.span, PixelSort.defaultSpan)
            XCTAssertEqual(setting.direction, .horizontal)
        }
    }

    func testPixelSortReadoutSpokenValueAndSliderStep() {
        withSortDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(PixelSortSetting.thresholdText(0.5), "50%")
            XCTAssertEqual(PixelSortSetting.thresholdText(0.054), "5%")
            XCTAssertEqual(SpokenValueFormatter.text(0.5, unit: .percent(decimals: 0)), "50 percent")
            XCTAssertEqual(PixelSortParameterSpecs.threshold.stepCount, 100)
            let setting = PixelSortSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(PixelSortParameterSpecs.threshold,
                                                        target: PixelSortSection.thresholdTarget(setting), direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.threshold, 0.51, accuracy: 1e-9, "one VoiceOver step is 1%")
        }
    }

    func testPixelSortKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(PixelSortSetting.allKeys, ["settings.pixelSort.enabled", "settings.pixelSort.threshold",
                                                  "settings.pixelSort.span", "settings.pixelSort.direction"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in PixelSortSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.pixelSort), "Pixel sort")
        let order: [OutputEffectKind] = OutputEffectOrder.standard.effects
        XCTAssertEqual(order.firstIndex(of: .pixelSort), (order.firstIndex(of: .lensDistortion) ?? 0) + 1)
        XCTAssertEqual(order.firstIndex(of: .vignette), order.count - 2, "Vignette follows, then FX-017's film grain last")
        XCTAssertEqual(order.last, .filmGrain)
    }

    func testPixelSortSceneAndPresetRoundTripThroughTheAppPaths() {
        withSortDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let sort = PixelSortSetting(defaults: defaults)
            sort.isEnabled = true
            sort.threshold = 0.3
            sort.span = 16
            chain.order = OutputEffectOrder([.pixelSort, .trails, .grade])
            var live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback)
            live.pixelSort = sort.sort
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.pixelSort", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Streaks", effects: live.entries(over: nil)))
            chain.order = .standard
            sort.isEnabled = false
            sort.threshold = 0.9
            sort.span = 64
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, pixelSort: sort)
            XCTAssertEqual(sort.sort, PixelSort(isEnabled: true, threshold: 0.3, span: 16))
            XCTAssertEqual(chain.order.effects.first, .pixelSort)
            sort.isEnabled = false
            let preset = chain.presets.preset(named: "Streaks")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, pixelSort: sort)
            XCTAssertTrue(sort.isEnabled, "the preset turns it back on")
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, pixelSort: sort)
            XCTAssertTrue(sort.isEnabled, "a scene without the entry leaves it alone")
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testPixelSortHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.pixelSort, .off)
        let on = PixelSort(isEnabled: true, threshold: 0.1, span: 8)
        AppCoordinator.apply(pixelSort: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.pixelSort, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.pixelSortDispatches, 1)
        AppCoordinator.apply(pixelSort: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsPixelSortPicture, "off returns the picture to the shared pool")
    }
}
