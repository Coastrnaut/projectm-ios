// KaleidoscopeAppTests.swift — VIS-014-T09: the kaleidoscope choice in the app (VIS-014-R4, R8, R9, R11, R12): the
// Wedges setting's default, persistence and safe reading; every key list; the host names itself, changes the wedge count
// in place (same generator), switches to and from Noise Field in place with the fold turned on and off, and applies the
// palette and Reduce Motion; a scene captured while it is shown records no native layer. The host tests need a Metal
// device (the simulator renders with the host GPU); they skip without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class KaleidoscopeAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "KaleidoscopeAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testWedgesDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.kaleidoscopeWedges, 6)
        settings.visual = .kaleidoscope
        settings.kaleidoscopeWedges = 24
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "kaleidoscope")
        XCTAssertEqual(defaults.integer(forKey: "settings.kaleidoscope.wedges"), 24)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .kaleidoscope)
        XCTAssertEqual(reloaded.kaleidoscopeWedges, 24)
        defaults.set(1, forKey: AppSettings.kaleidoscopeWedgesKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).kaleidoscopeWedges, 6, "outside 2…24 → 6")
        defaults.set("many", forKey: AppSettings.kaleidoscopeWedgesKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.kaleidoscopeWedges, 6, "not a number → 6")
        bad.kaleidoscopeWedges = 25
        XCTAssertEqual(bad.kaleidoscopeWedges, 6, "out of range → default")
        XCTAssertTrue(VisualChoice.kaleidoscope.isNative)
        XCTAssertFalse(VisualChoice.kaleidoscope.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.kaleidoscope.title, "Kaleidoscope")
    }

    /// VIS-014-R9: an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeyIsInEveryList() {
        let key = "settings.kaleidoscope.wedges"
        XCTAssertEqual(AppSettings.kaleidoscopeWedgesKey, key)
        XCTAssertTrue(AppSettings.allKeys.contains(key))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key))
    }

    func testHostChangesWedgesInPlaceAndSwitchesWithTheNoiseField() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .kaleidoscope(wedges: 6), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Kaleidoscope visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "kaleidoscope")
        XCTAssertEqual(host.view.accessibilityValue, "6 wedges, Glow off")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.kaleidoscope(wedges: 6))
        try host.apply(style: .kaleidoscope(wedges: 9))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "the wedge count changes in place")
        XCTAssertEqual(generator.configuration.wedges, 9)
        XCTAssertEqual(host.view.accessibilityValue, "9 wedges, Glow off")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-014-R8")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertEqual(generator.configuration.wedges, 0, "Noise Field draws unfolded")
        XCTAssertEqual(generator.configuration.frequency, 8)
        try host.apply(style: .kaleidoscope(wedges: 3))
        XCTAssertEqual(generator.configuration.wedges, 3)
        XCTAssertEqual(generator.configuration.frequency, 4, "the kaleidoscope's own source settings")
        XCTAssertEqual(generator.configuration.seed, 1301)
        XCTAssertTrue(generator.configuration.reduceMotion, "kept across the switch")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .kaleidoscope(wedges: 12))
        let rebuilt = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(rebuilt.configuration.wedges, 12)
        XCTAssertTrue(rebuilt.configuration.reduceMotion, "a new generator gets Reduce Motion too")
    }

    /// VIS-014-R11: no SCN-001 kind for the kaleidoscope; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .kaleidoscope)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
