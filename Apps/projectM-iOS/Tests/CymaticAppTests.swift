// CymaticAppTests.swift — VIS-019-T10: the Cymatic Lines choice in the app (VIS-019-R10, R12, R13): the Bands setting's
// default, persistence and safe reading; every key list; the host names itself, changes the range in place (same
// generator, the blend continues), applies the palette and Reduce Motion, and switches with the other noise-field modes in
// place; a scene captured while it is shown records no native layer. The host tests need a Metal device (the simulator
// renders with the host GPU).
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class CymaticAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "CymaticAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBandsDefaultPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.cymaticBands, .all)
        settings.visual = .cymatic
        settings.cymaticBands = .mid
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "cymatic")
        XCTAssertEqual(defaults.string(forKey: "settings.cymatic.bands"), "mid")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .cymatic)
        XCTAssertEqual(reloaded.cymaticBands, .mid)
        defaults.set("treble", forKey: AppSettings.cymaticBandsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cymaticBands, .all, "unknown → all")
        defaults.set(2, forKey: AppSettings.cymaticBandsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cymaticBands, .all, "wrong type → all")
        XCTAssertTrue(VisualChoice.cymatic.isNative)
        XCTAssertFalse(VisualChoice.cymatic.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.cymatic.title, "Cymatic Lines")
    }

    /// VIS-019-R10: an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertEqual(AppSettings.cymaticBandsKey, "settings.cymatic.bands")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.cymatic.bands"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.cymatic.bands"))
    }

    func testHostChangesTheRangeInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .cymatic(bands: .all), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Cymatic Lines visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "cymatic")
        XCTAssertEqual(host.view.accessibilityValue, "All bands, Glow off")
        XCTAssertFalse(NativeSpectrumStyle.cymatic(bands: .all).drainsAnalysisEvents, "bands only")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration.cymatic?.bands, .all)
        try host.apply(style: .cymatic(bands: .low))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "the range changes in place")
        XCTAssertEqual(generator.configuration.cymatic?.bands, .low)
        XCTAssertEqual(host.view.accessibilityValue, "Low bands, Glow off")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "ACC-001")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .cymatic(bands: .high))
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion survives a range change")
        XCTAssertEqual(generator.configuration.palette, .colorBlindSafe)
        // Switching with other noise-field modes keeps the generator.
        try host.apply(style: .signedDistance(quality: .low))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.cymatic)
        try host.apply(style: .cymatic(bands: .mid))
        XCTAssertNil(generator.configuration.signedDistance)
        XCTAssertEqual(generator.configuration.cymatic?.bands, .mid)
        try host.apply(style: .noiseField(frequency: .medium, octaves: 4, seed: 1301))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.cymatic, "back to the plain field")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
    }

    /// VIS-019-R12: no SCN-001 kind for the cymatic lines; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .cymatic)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
