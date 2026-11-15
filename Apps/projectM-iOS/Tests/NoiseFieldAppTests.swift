// NoiseFieldAppTests.swift — VIS-013-T12: the noise field choice in the app (VIS-013-R4, R8, R9, R11, R12): the three
// settings' defaults, persistence and safe reading; every key list; New Seed's deterministic sequence; the host names
// itself, changes frequency, octaves and seed in place (same generator), applies the palette and Reduce Motion (also to
// a generator a style change builds); a scene captured while it is shown records no native layer. The host tests need a
// Metal device (the simulator renders with the host GPU); they skip without one.
import LibraryBackup
import Metal
import ProceduralMaterials
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class NoiseFieldAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private static let keys = ["settings.noiseField.frequency", "settings.noiseField.octaves", "settings.noiseField.seed"]

    override func setUp() async throws {
        suite = "NoiseFieldAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.noiseFieldFrequency, .medium)
        XCTAssertEqual(settings.noiseFieldOctaves, 4)
        XCTAssertEqual(settings.noiseFieldSeed, 1301)
        XCTAssertEqual(NoiseFieldFrequency.allCases.map(\.title), ["Low", "Medium", "High"])
        XCTAssertEqual(NoiseFieldFrequency.allCases.map(\.cells), [2, 4, 8])
        XCTAssertEqual(NoiseFieldFrequency.medium.cells, NoiseFieldConfiguration.defaultFrequency)
        settings.visual = .noiseField
        settings.noiseFieldFrequency = .high
        settings.noiseFieldOctaves = 6
        settings.noiseFieldSeed = 0
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "noiseField")
        XCTAssertEqual(defaults.string(forKey: "settings.noiseField.frequency"), "high")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .noiseField)
        XCTAssertEqual(reloaded.noiseFieldFrequency, .high)
        XCTAssertEqual(reloaded.noiseFieldOctaves, 6)
        XCTAssertEqual(reloaded.noiseFieldSeed, 0, "seed 0 is a valid stored value")
        defaults.set("loud", forKey: AppSettings.noiseFieldFrequencyKey)
        defaults.set(9, forKey: AppSettings.noiseFieldOctavesKey)
        defaults.set(70_000, forKey: AppSettings.noiseFieldSeedKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.noiseFieldFrequency, .medium)
        XCTAssertEqual(bad.noiseFieldOctaves, 4)
        XCTAssertEqual(bad.noiseFieldSeed, 1301)
        bad.noiseFieldOctaves = 0
        XCTAssertEqual(bad.noiseFieldOctaves, 4, "out of range → default")
        XCTAssertTrue(VisualChoice.noiseField.isNative)
        XCTAssertFalse(VisualChoice.noiseField.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.noiseField.title, "Noise Field")
    }

    /// VIS-013-R9: FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeysAreInEveryList() {
        for key in Self.keys {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
    }

    /// VIS-013-R4: New Seed is SHD-006's deterministic sequence and never repeats the current seed.
    func testNewSeedIsDeterministic() {
        var expected = NoiseSeedSequence()
        var reference: [Int] = []
        var current = 1301
        for _ in 0..<3 {
            current = expected.next(after: current)
            reference.append(current)
        }
        NoiseFieldSeeds.sequence = NoiseSeedSequence()
        var got: [Int] = []
        current = 1301
        for _ in 0..<3 {
            let next = NoiseFieldSeeds.next(after: current)
            XCTAssertNotEqual(next, current)
            current = next
            got.append(next)
        }
        XCTAssertEqual(got, reference)
    }

    func testHostChangesSettingsInPlaceAndFollowsReduceMotion() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .noiseField(frequency: .medium, octaves: 4, seed: 1301),
                                               barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Noise Field visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "noiseField")
        XCTAssertEqual(host.view.accessibilityValue, "Medium frequency, 4 octaves, seed 1301, Glow off")
        XCTAssertNil(host.beatEvents, "the field reads bands, not beat events")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration.frequency, 4)
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "settings change in place")
        XCTAssertEqual(generator.configuration.frequency, 8)
        XCTAssertEqual(generator.configuration.octaves, 2)
        XCTAssertEqual(generator.configuration.seed, 7)
        XCTAssertEqual(host.view.accessibilityValue, "High frequency, 2 octaves, seed 7, Glow off")
        host.reduceMotion = true
        XCTAssertTrue(generator.configuration.reduceMotion)
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the field")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .noiseField(frequency: .low, octaves: 4, seed: 1301))
        let rebuilt = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertTrue(rebuilt.configuration.reduceMotion, "a new generator gets Reduce Motion too")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
    }

    /// VIS-013-R11: no SCN-001 kind for the field; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .noiseField)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
