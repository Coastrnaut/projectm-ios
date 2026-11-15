// StarfieldAppTests.swift — VIS-016-T10: the starfield choice in the app (VIS-016-R6, R8, R10, R11): the Speed and Stars
// settings' defaults, persistence and safe reading; every key list; the host names itself, changes speed and density in
// place (same generator, stars not restarted), applies the palette and Reduce Motion, and resets the stars on its loop
// restart; a scene captured while it is shown records no native layer. The host tests need a Metal device (the
// simulator renders with the host GPU).
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class StarfieldAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "StarfieldAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSpeedAndDensityDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.starfieldSpeed, .medium)
        XCTAssertEqual(settings.starfieldDensity, 600)
        settings.visual = .starfield
        settings.starfieldSpeed = .fast
        settings.starfieldDensity = 2000
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "starfield")
        XCTAssertEqual(defaults.string(forKey: "settings.starfield.speed"), "fast")
        XCTAssertEqual(defaults.integer(forKey: "settings.starfield.density"), 2000)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .starfield)
        XCTAssertEqual(reloaded.starfieldSpeed, .fast)
        XCTAssertEqual(reloaded.starfieldDensity, 2000)
        settings.starfieldDensity = 5000
        XCTAssertEqual(settings.starfieldDensity, 600, "above the stepper's range → default")
        for bad in [50, 2100, 650] {
            defaults.set(bad, forKey: AppSettings.starfieldDensityKey)
            XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).starfieldDensity, 600, "\(bad) → 600")
        }
        defaults.set("warp", forKey: AppSettings.starfieldSpeedKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).starfieldSpeed, .medium, "unknown → medium")
        XCTAssertTrue(VisualChoice.starfield.isNative)
        XCTAssertFalse(VisualChoice.starfield.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.starfield.title, "Starfield")
    }

    /// VIS-016-R8: FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeysAreInEveryList() {
        for key in ["settings.starfield.speed", "settings.starfield.density"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
        XCTAssertEqual(AppSettings.starfieldSpeedKey, "settings.starfield.speed")
        XCTAssertEqual(AppSettings.starfieldDensityKey, "settings.starfield.density")
    }

    func testHostChangesSpeedAndDensityInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .starfield(speed: .medium, density: 600),
                                               barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Starfield visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "starfield")
        XCTAssertEqual(host.view.accessibilityValue, "Medium speed, 600 stars, Glow off")
        XCTAssertFalse(NativeSpectrumStyle.starfield(speed: .medium, density: 600).drainsAnalysisEvents, "bands only")
        let generator = try XCTUnwrap(host.starfieldGenerator)
        XCTAssertEqual(generator.configuration, StarfieldConfiguration(density: 600, speed: .medium))
        let initial = generator.simulation.allStars
        generator.simulation.advance(toNanoseconds: 0)
        generator.simulation.advance(toNanoseconds: 500_000_000)
        let flown = generator.simulation.allStars
        try host.apply(style: .starfield(speed: .fast, density: 2000))
        XCTAssertTrue(host.starfieldGenerator === generator, "speed and density change in place")
        XCTAssertEqual(generator.configuration.speed, .fast)
        XCTAssertEqual(generator.simulation.activeCount, 2000)
        XCTAssertEqual(generator.simulation.allStars, flown, "the stars keep flying (no restart)")
        XCTAssertEqual(host.view.accessibilityValue, "Fast speed, 2000 stars, Glow off")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-016-R6")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        generator.restartLoop()
        XCTAssertEqual(generator.simulation.allStars, initial, "the loop restart restores the initial positions")
        try host.apply(style: .circular)
        XCTAssertNil(host.starfieldGenerator)
        try host.apply(style: .starfield(speed: .slow, density: 100))
        let fresh = try XCTUnwrap(host.starfieldGenerator)
        XCTAssertTrue(fresh.configuration.reduceMotion, "a new generator gets Reduce Motion too")
        XCTAssertEqual(fresh.configuration.palette, .colorBlindSafe)
        XCTAssertEqual(fresh.simulation.allStars, initial, "re-entering the visual starts from the seeded positions")
    }

    /// VIS-016-R10: no SCN-001 kind for the starfield; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .starfield)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
