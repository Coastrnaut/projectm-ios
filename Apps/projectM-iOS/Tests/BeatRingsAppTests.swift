// BeatRingsAppTests.swift — VIS-006-T11: the beat rings choice in the app (VIS-006-R9 to R11): the setting's
// default, persistence and safe reading; every key list; the host names itself, subscribes to beat events only
// while beat rings are shown, changes the ring life in place (same generator), applies the palette and clears
// the rings on a loop restart; a scene captured while it is shown records no native layer. The host test needs a
// Metal device (the simulator renders with the host GPU); it skips without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class BeatRingsAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "BeatRingsAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testLifeDefaultsPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.beatRingsLife, .medium, "Medium ring life by default")
        XCTAssertEqual(BeatRingLife.allCases.map(\.title), ["Short", "Medium", "Long"])
        XCTAssertEqual(BeatRingLife.allCases.map(\.seconds), [1.0, 1.5, 2.5])
        XCTAssertEqual(BeatRingLife.medium.seconds, BeatRingConfiguration.defaultLife)
        settings.visual = .beatRings
        settings.beatRingsLife = .long
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "beatRings")
        XCTAssertEqual(defaults.string(forKey: "settings.beatRings.life"), "long")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .beatRings)
        XCTAssertEqual(reloaded.beatRingsLife, .long)
        defaults.set("forever", forKey: AppSettings.beatRingsLifeKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).beatRingsLife, .medium, "unknown → Medium")
        defaults.set(2, forKey: AppSettings.beatRingsLifeKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).beatRingsLife, .medium, "not a string → Medium")
        XCTAssertTrue(VisualChoice.beatRings.isNative)
        XCTAssertFalse(VisualChoice.beatRings.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.beatRings.title, "Beat Rings")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .beatRings),
                       "Beat Rings isn't available on this device. Showing projectM.")
    }

    /// VIS-006-R9: the key is an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertTrue(AppSettings.allKeys.contains("settings.beatRings.life"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.beatRings.life"))
    }

    func testHostSubscribesNamesItselfAndChangesLifeInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .beatRings(life: .medium), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Beat Rings visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "beatRings")
        XCTAssertEqual(host.view.accessibilityValue, "Medium ring life, Glow off")
        XCTAssertNotNil(host.beatEvents, "beat rings read the analysis bus's events")
        let generator = try XCTUnwrap(host.beatRingGenerator)
        XCTAssertEqual(generator.configuration.life, 1.5)
        try host.apply(style: .beatRings(life: .short))
        XCTAssertTrue(host.beatRingGenerator === generator, "the ring life changes in place")
        XCTAssertEqual(generator.configuration.life, 1.0)
        XCTAssertEqual(host.view.accessibilityValue, "Short ring life, Glow off")
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to beat rings")
        // Reduce flashing's rate cap reaches the host's frames through the frame context (VIS-006-R5).
        host.reduceFlashing = true
        let context = host.frameContext(timeNanoseconds: 1_000_000_000, frameDuration: 1.0 / 60)
        XCTAssertTrue(generator.emitRing(atNanoseconds: 1_000_000_000, flashConfiguration: context.flashConfiguration))
        XCTAssertFalse(generator.emitRing(atNanoseconds: 1_250_000_000, flashConfiguration: context.flashConfiguration),
                       "a quarter second later is inside Reduce flashing's 1/3 s cap")
        XCTAssertEqual(generator.field.storedCount, 1)
        host.resume()
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(generator.field.storedCount, 0, "the loop start clears the rings")
        try host.apply(style: .circular)
        XCTAssertNil(host.beatEvents, "no subscription once beat rings are gone")
        XCTAssertNil(host.beatRingGenerator)
        XCTAssertTrue(host.isRunning, "switching kinds keeps the loop running")
        try host.apply(style: .beatRings(life: .long))
        XCTAssertNotNil(host.beatEvents)
        XCTAssertEqual(host.beatRingGenerator?.configuration.life, 2.5)
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        host.pause()
    }

    /// VIS-006-R10: no SCN-001 kind for beat rings; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .beatRings)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
