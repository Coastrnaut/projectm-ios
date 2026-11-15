// FX-017-T14: the film grain setting, its readouts and ACC-005 slider, the keys' policies, scene and preset round trips
// through the app's effect-chain paths, Reduce Motion's static grain, and a real host's compositor (FX-017-R4, R9 to
// R11, S5, S6).
import Compositor
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class FilmGrainSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withGrainDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "FilmGrainSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testFilmGrainOffByDefaultPersistedAndClamped() {
        withGrainDefaults { (defaults: UserDefaults) -> Void in
            let setting = FilmGrainSetting(defaults: defaults)
            XCTAssertEqual(setting.grain, .off)
            for key in FilmGrainSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
            var reported: [FilmGrain] = []
            setting.onChange = { (value: FilmGrain) -> Void in reported.append(value) }
            setting.isEnabled = true
            setting.opacity = 0.55
            setting.size = 3
            setting.isColor = true
            setting.seed = 42
            setting.isAnimated = true
            XCTAssertEqual(reported.count, 6)
            let expected = FilmGrain(isEnabled: true, opacity: 0.55, size: 3, isColor: true, seed: 42, isAnimated: true)
            XCTAssertEqual(reported.last, expected)
            XCTAssertEqual(FilmGrainSetting(defaults: defaults).grain, expected, "kept across a relaunch")
            setting.opacity = 7
            XCTAssertEqual(setting.opacity, 1, "out of range → nearest bound")
            setting.opacity = .nan
            XCTAssertEqual(setting.opacity, 0.3, "NaN → the default")
            setting.size = 0
            XCTAssertEqual(setting.size, 1)
            setting.seed = 20_000
            XCTAssertEqual(setting.seed, 9_999)
            XCTAssertEqual(FilmGrainSetting(defaults: defaults).seed, 9_999, "the clamped value is what is stored")
        }
        withGrainDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(1, forKey: FilmGrainSetting.enabledKey)   // a number, not a Bool
            defaults.set("grainy", forKey: FilmGrainSetting.opacityKey)
            defaults.set(2.6, forKey: FilmGrainSetting.sizeKey)
            defaults.set("yes", forKey: FilmGrainSetting.colorKey)
            defaults.set(-5, forKey: FilmGrainSetting.seedKey)
            defaults.set(true, forKey: FilmGrainSetting.animatedKey)
            let setting = FilmGrainSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "only a Bool turns it on")
            XCTAssertEqual(setting.opacity, FilmGrain.defaultOpacity)
            XCTAssertEqual(setting.size, 3, "rounded")
            XCTAssertFalse(setting.isColor)
            XCTAssertEqual(setting.seed, 0)
            XCTAssertTrue(setting.isAnimated)
        }
    }

    func testFilmGrainReadoutSpokenValueAndSliderStep() {
        withGrainDefaults { (defaults: UserDefaults) -> Void in
            XCTAssertEqual(FilmGrainSetting.percentText(0.3), "30%")
            XCTAssertEqual(FilmGrainSetting.percentText(0), "0%")
            XCTAssertEqual(FilmGrainSetting.sizeText(2), "2 px")
            XCTAssertEqual(SpokenValueFormatter.text(0.3, unit: .percent(decimals: 0)), "30 percent")
            XCTAssertEqual(FilmGrainParameterSpecs.opacity.stepCount, 100)
            let setting = FilmGrainSetting(defaults: defaults)
            let down = AccessibleParameterAdjuster.adjust(FilmGrainParameterSpecs.opacity,
                                                          target: FilmGrainSection.opacityTarget(setting), direction: .decrement)
            XCTAssertTrue(down.moved)
            XCTAssertEqual(setting.opacity, 0.29, accuracy: 1e-9, "one VoiceOver step is 1%")
        }
    }

    func testFilmGrainKeysAreBackedUpErasedAndNamed() {
        XCTAssertEqual(FilmGrainSetting.allKeys, ["settings.filmGrain.enabled", "settings.filmGrain.opacity", "settings.filmGrain.size",
                                                  "settings.filmGrain.color", "settings.filmGrain.seed", "settings.filmGrain.animated"])
        let included = Set(LibrarySettingsPolicy.includedKeys)
        for key in FilmGrainSetting.allKeys { XCTAssertTrue(included.contains(key), "\(key) is backed up and erased") }
        XCTAssertEqual(EffectChainSetting.name(.filmGrain), "Film grain")
        XCTAssertEqual(OutputEffectOrder.standard.effects.last, .filmGrain, "last, after Vignette")
    }

    func testFilmGrainReduceMotionMakesTheGrainStatic() {
        let moving = FilmGrain(isEnabled: true, opacity: 0.5, seed: 3, isAnimated: true)
        XCTAssertFalse(moving.effective(reduceMotion: true).isAnimated)
        XCTAssertEqual(moving.effective(reduceMotion: true).seed, 3, "only the motion changes")
        XCTAssertTrue(moving.effective(reduceMotion: false).isAnimated)
    }

    func testFilmGrainSceneAndPresetRoundTripThroughTheAppPaths() {
        withGrainDefaults { (defaults: UserDefaults) -> Void in
            let chain = EffectChainSetting(defaults: defaults)
            let grade = ColorGradeSetting(defaults: defaults)
            let trails = MotionFeedbackSetting(defaults: defaults)
            let grain = FilmGrainSetting(defaults: defaults)
            grain.isEnabled = true
            grain.opacity = 0.8
            grain.size = 2
            grain.seed = 1_234
            chain.order = OutputEffectOrder([.filmGrain, .trails, .grade])
            var live = SceneEffectSettings(order: chain.order, grade: grade.grade, gradeEnabled: grade.isEnabled,
                                           trails: trails.feedback)
            live.filmGrain = grain.grain
            let written: [SceneEffectEntry]? = SceneAutosaveCapture.effects(live, carry: nil)
            XCTAssertEqual(written?.map(\.kind), ["fx.filmGrain", "fx.trails", "fx.grade"])
            XCTAssertTrue(chain.savePreset(name: "Grain", effects: live.entries(over: nil)))
            chain.order = .standard
            grain.isEnabled = false
            grain.seed = 5
            grain.size = 1
            SceneAutosaveCapture.applyEffects(written, chain: chain, grade: grade, trails: trails, filmGrain: grain)
            XCTAssertEqual(grain.grain, FilmGrain(isEnabled: true, opacity: 0.8, size: 2, seed: 1_234))
            XCTAssertEqual(chain.order.effects.first, .filmGrain)
            grain.isEnabled = false
            let preset = chain.presets.preset(named: "Grain")
            SceneAutosaveCapture.applyEffects(preset?.effects, chain: chain, grade: grade, trails: trails, filmGrain: grain)
            XCTAssertTrue(grain.isEnabled, "the preset turns it back on")
            let older = [SceneEffectEntry(kind: "fx.trails", enabled: false)]
            SceneAutosaveCapture.applyEffects(older, chain: chain, grade: grade, trails: trails, filmGrain: grain)
            XCTAssertTrue(grain.isEnabled, "a scene without a grain entry leaves it alone")
            XCTAssertEqual(chain.order, .standard)
        }
    }

    func testFilmGrainHostCompositorTakesTheValue() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertEqual(host.compositor.filmGrain, .off)
        let on = FilmGrain(isEnabled: true, opacity: 0.7, seed: 9)
        AppCoordinator.apply(filmGrain: on, to: [host.compositor])
        XCTAssertEqual(host.compositor.filmGrain, on)
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNotNil(host.compositor.encodeScene(width: 64, height: 48, commandBuffer: commands,
                                                    presentationTimeNanoseconds: 1_000_000_000, contentScale: 2,
                                                    reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(host.compositor.filmGrainFrames, 1)
        AppCoordinator.apply(filmGrain: .off, to: [host.compositor])
        XCTAssertFalse(host.compositor.holdsFilmGrainPicture, "off returns the picture to the shared pool")
    }
}
