// TessellationAppTests.swift — VIS-018-T11: the Tessellation choice in the app (VIS-018-R10, R12, R13): the settings'
// defaults, persistence and safe reading; every key list; the host names itself, changes settings in place (same
// generator, the drift keeps going), applies Reduce Motion, and the colour-blind-safe palette wins over the tessellation's
// own (US3 scenario 3); switching with the other noise-field modes is in place; a scene captured while it is shown records
// no native layer. The host tests need a Metal device (the simulator renders with the host GPU).
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class TessellationAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "TessellationAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.tessellation, TessellationSettings(tiling: .hexagon, tiles: 6, symmetry: 6, mirror: false, palette: .spectrum))
        settings.visual = .tessellation
        settings.tessellation.tiling = .truncatedSquare
        settings.tessellation.tiles = 12
        settings.tessellation.symmetry = 4
        settings.tessellation.mirror = true
        settings.tessellation.palette = .mono
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "tessellation")
        XCTAssertEqual(defaults.string(forKey: "settings.tessellation.tiling"), "truncatedSquare")
        XCTAssertEqual(defaults.integer(forKey: "settings.tessellation.tiles"), 12)
        XCTAssertEqual(defaults.integer(forKey: "settings.tessellation.symmetry"), 4)
        XCTAssertTrue(defaults.bool(forKey: "settings.tessellation.mirror"))
        XCTAssertEqual(defaults.string(forKey: "settings.tessellation.palette"), "mono")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .tessellation)
        XCTAssertEqual(reloaded.tessellation, settings.tessellation)
        defaults.set("rhombus", forKey: "settings.tessellation.tiling")
        defaults.set(40, forKey: "settings.tessellation.tiles")
        defaults.set(5, forKey: "settings.tessellation.symmetry")
        defaults.set("pink", forKey: "settings.tessellation.mirror")
        defaults.set("neon", forKey: "settings.tessellation.palette")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).tessellation, .default, "bad values → defaults")
        settings.tessellation.tiles = 1
        XCTAssertEqual(settings.tessellation.tiles, 6, "out of range → 6")
        XCTAssertTrue(VisualChoice.tessellation.isNative)
        XCTAssertFalse(VisualChoice.tessellation.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.tessellation.title, "Tessellation")
    }

    /// VIS-018-R10: FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeysAreInEveryList() {
        let keys = ["settings.tessellation.tiling", "settings.tessellation.tiles", "settings.tessellation.symmetry",
                    "settings.tessellation.mirror", "settings.tessellation.palette"]
        XCTAssertEqual(AppSettings.tessellationKeys, keys)
        for key in keys {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
    }

    func testHostChangesSettingsInPlaceAndThePaletteRules() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .tessellation(.default), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Tessellation visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "tessellation")
        XCTAssertEqual(host.view.accessibilityValue, "Hexagons, 6 tiles, 6-fold symmetry, Spectrum palette, Glow off")
        XCTAssertFalse(NativeSpectrumStyle.tessellation(.default).drainsAnalysisEvents, "bands only")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        let squares = TessellationSettings(tiling: .square, tiles: 9, symmetry: 4, mirror: true, palette: .ice)
        try host.apply(style: .tessellation(squares))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "settings change in place")
        XCTAssertEqual(generator.configuration.tessellation, squares)
        XCTAssertEqual(host.view.accessibilityValue, "Squares, 9 tiles, mirrored 4-fold symmetry, Ice palette, Glow off")
        XCTAssertEqual(generator.configuration.effectivePalette, .ice, "the tessellation's own palette")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "ACC-001")
        XCTAssertEqual(generator.configuration.effectivePalette, .colorBlindSafe, "ACC-003-R13 wins (US3 scenario 3)")
        try host.apply(style: .tessellation(.default))
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion survives a settings change")
        XCTAssertEqual(generator.configuration.palette, .colorBlindSafe)
        // Switching with another noise-field mode keeps the generator.
        try host.apply(style: .signedDistance(quality: .low))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.tessellation)
        try host.apply(style: .tessellation(squares))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.signedDistance)
        try host.apply(style: .noiseField(frequency: .medium, octaves: 4, seed: 1))
        XCTAssertNil(generator.configuration.tessellation, "back to the plain field")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
    }

    /// VIS-018-R12: no SCN-001 kind for the tessellation; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .tessellation)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
