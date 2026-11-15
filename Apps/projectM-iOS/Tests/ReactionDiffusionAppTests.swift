// ReactionDiffusionAppTests.swift — VIS-012-T10: the Reaction Diffusion choice in the app (VIS-012-R6, R12 to R14): the
// choice and its four settings are stored and restored (bad values read the defaults); the host names itself, builds
// the reaction mode with the stored settings, needs no bus subscription, switches to and from the other noise-field
// modes in place (same generator, same storage) and re-seeds on a seed change but not on a Speed change; a scene
// captured while it is shown records no native layer. The host tests need a Metal device (the simulator renders with
// the host GPU).
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ReactionDiffusionAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ReactionDiffusionAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoiceAndSettingsPersistWithSafeDefaults() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.reactionDiffusion, .default, "Coral, Centre Square, seed 1, speed 8")
        settings.visual = .reactionDiffusion
        settings.reactionPreset = .mitosis
        settings.reactionPattern = .stripes
        settings.reactionSeed = 9999
        settings.reactionSpeed = 16
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "reactionDiffusion")
        XCTAssertEqual(defaults.string(forKey: "settings.reactionDiffusion.preset"), "mitosis")
        XCTAssertEqual(defaults.string(forKey: "settings.reactionDiffusion.pattern"), "stripes")
        XCTAssertEqual(defaults.integer(forKey: "settings.reactionDiffusion.seed"), 9999)
        XCTAssertEqual(defaults.integer(forKey: "settings.reactionDiffusion.speed"), 16)
        let relaunched = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(relaunched.visual, .reactionDiffusion)
        XCTAssertEqual(relaunched.reactionDiffusion, ReactionDiffusionSettings(preset: .mitosis, pattern: .stripes, seed: 9999, speed: 16),
                       "a relaunch decodes the same settings, so the same initial pattern")
        relaunched.reactionSpeed = 17
        XCTAssertEqual(relaunched.reactionSpeed, 8, "out of range → default")
        defaults.set("lava", forKey: AppSettings.reactionPresetKey)
        defaults.set(3, forKey: AppSettings.reactionPatternKey)
        defaults.set("many", forKey: AppSettings.reactionSeedKey)
        defaults.set(0, forKey: AppSettings.reactionSpeedKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).reactionDiffusion, .default)
        XCTAssertTrue(VisualChoice.reactionDiffusion.isNative)
        XCTAssertFalse(VisualChoice.reactionDiffusion.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.reactionDiffusion.title, "Reaction Diffusion")
        for key in [AppSettings.reactionPresetKey, AppSettings.reactionPatternKey, AppSettings.reactionSeedKey, AppSettings.reactionSpeedKey] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
        }
        XCTAssertFalse(NativeSpectrumStyle.reactionDiffusion(.default).drainsAnalysisEvents, "bass comes from the bands")
    }

    func testHostBuildsTheModeAndSwitchesInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let stored = ReactionDiffusionSettings(preset: .maze, pattern: .ring, seed: 12, speed: 4)
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .reactionDiffusion(stored), barCount: .b64)
        XCTAssertEqual(host.view.accessibilityLabel, "Reaction Diffusion visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "reactionDiffusion")
        XCTAssertEqual(host.view.accessibilityValue, "Maze, Ring, seed 12, speed 4, Glow off")
        XCTAssertNil(host.beatEvents, "no bus subscription")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.reactionDiffusion(stored))
        let pass = try XCTUnwrap(generator.reactionPass, "made when the host builds it, off the frame loop")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-012-R12")
        try host.apply(style: .tunnel(pace: .beat))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.reactionDiffusion)
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertNil(generator.configuration.reactionDiffusion, "Noise Field draws the field")
        var faster = stored
        faster.speed = 16
        try host.apply(style: .reactionDiffusion(faster))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "in place")
        XCTAssertEqual(generator.configuration,
                       NoiseFieldConfiguration.reactionDiffusion(faster, reduceMotion: true, palette: .colorBlindSafe),
                       "Reduce Motion and the palette kept")
        XCTAssertTrue(generator.reactionPass === pass, "the storage is never replaced")
        XCTAssertEqual(host.view.accessibilityValue, "Maze, Ring, seed 12, speed 16, Glow off")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .reactionDiffusion(stored))
        XCTAssertTrue(try XCTUnwrap(host.noiseFieldGenerator).configuration.reduceMotion, "a new generator gets Reduce Motion too")
    }

    /// VIS-012-R14: no SCN-001 kind for reaction diffusion; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .reactionDiffusion)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
