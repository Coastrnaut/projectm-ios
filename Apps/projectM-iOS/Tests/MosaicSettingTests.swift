// FX-012-T14: the mosaic setting, its readout and ACC-005 slider, the keys' policies, scene and preset round trips
// through the app's effect-chain paths, and a real host's compositor (FX-012-R8 to R10).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class MosaicSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withMosaicDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "MosaicSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testMosaicOffByDefaultPersistedAndClamped() {
        withMosaicDefaults { (defaults: UserDefaults) -> Void in
            let setting = MosaicSetting(defaults: defaults)
            XCTAssertEqual(setting.mosaic, .off)
            for key in MosaicSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [Mosaic] = []
            setting.onChange = { (value: Mosaic) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.blockSize = 16
            setting.shape = .hexagon
            XCTAssertEqual(reported.count, 3)
            let expected = Mosaic(isEnabled: true, blockSize: 16, shape: .hexagon)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(MosaicSetting(defaults: defaults).mosaic, expected, "kept across a relaunch")
            setting.blockSize = 500
            XCTAssertEqual(setting.blockSize, 64, "out of range → nearest bound")
            setting.blockSizeValue = 3.4
            XCTAssertEqual(setting.blockSize, 3, "the slider rounds to whole pixels")
        }
        withMosaicDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: MosaicSetting.enabledKey)   // a number, not a Bool
            defaults.set("big", forKey: MosaicSetting.sizeKey)
            defaults.set("triangle", forKey: MosaicSetting.shapeKey)
            let setting = MosaicSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.blockSize, Mosaic.defaultSize)
            XCTAssertEqual(setting.shape, .square)
        }
    }

    func testMosaicReadoutSpokenValueAndSliderStep() {
        withMosaicDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(MosaicSetting.sizeText(8), "8 px")
            XCTAssertEqual(SpokenValueFormatter.text(8, unit: .number(decimals: 0)), "8")
            XCTAssertEqual(MosaicParameterSpecs.size.stepCount, 63)
            let setting = MosaicSetting(defaults: defaults)
            let up = AccessibleParameterAdjuster.adjust(MosaicParameterSpecs.size, target: MosaicSection.sizeTarget(setting),
                                                        direction: .increment)
            XCTAssertTrue(up.moved)
            XCTAssertEqual(setting.blockSize, 9, "one VoiceOver step is one pixel")
        }
    }

    func testMosaicKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(MosaicSetting.allKeys, ["settings.mosaic.enabled", "settings.mosaic.size", "settings.mosaic.shape"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in MosaicSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.mosaic), "Mosaic")
    }

    func testMosaicSceneAndPresetRoundTripThroughTheAppPaths() {
        withMosaicDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let mosaic = MosaicSetting(defaults: defaults)
            mosaic.isEnabled = true
            mosaic.blockSize = 20
            mosaic.shape = .hexagon
            chain.order = OutputEffectOrder([.mosaic, .trails, .grade])
            let live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback, mosaic: mosaic.mosaic)
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.mosaic", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Tiles", effects: live.entries(over: nil)))
            // Change everything, then open the scene, then apply the preset.
            chain.order = .standard
            mosaic.isEnabled = false
            mosaic.blockSize = 2
            mosaic.shape = .square
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, mosaic: mosaic)
            XCTAssertEqual(mosaic.mosaic, Mosaic(isEnabled: true, blockSize: 20, shape: .hexagon))
            XCTAssertEqual(chain.order.effects.first, .mosaic)
            mosaic.isEnabled = false
            let preset = chain.presets.preset(named: "Tiles")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, mosaic: mosaic)
            XCTAssertTrue(mosaic.isEnabled, "the preset turns it back on")
            // A scene without a mosaic entry leaves the mosaic alone.
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, mosaic: mosaic)
            XCTAssertTrue(mosaic.isEnabled)
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testMosaicHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.mosaic, .off)
        let on = Mosaic(isEnabled: true, blockSize: 8, shape: .hexagon)
        AppCoordinator.apply(mosaic: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.mosaic, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.mosaicFrames, 1)
        AppCoordinator.apply(mosaic: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsMosaicPicture, "off returns the picture to the shared pool")
    }
}
