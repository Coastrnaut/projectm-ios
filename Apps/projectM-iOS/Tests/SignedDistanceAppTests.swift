// SignedDistanceAppTests.swift — VIS-017-T10: the SDF Shapes choice in the app (VIS-017-R8, R10, R11): the Quality
// setting's default, persistence and safe reading; every key list; the host names itself, changes quality in place (same
// generator, the pose keeps turning), applies the palette and Reduce Motion, and switches with the other noise-field modes
// in place; a scene captured while it is shown records no native layer. The host tests need a Metal device (the simulator
// renders with the host GPU).
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class SignedDistanceAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SignedDistanceAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testQualityDefaultsPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.signedDistanceQuality, .medium)
        settings.visual = .signedDistance
        settings.signedDistanceQuality = .high
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "signedDistance")
        XCTAssertEqual(defaults.string(forKey: "settings.signedDistance.quality"), "high")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .signedDistance)
        XCTAssertEqual(reloaded.signedDistanceQuality, .high)
        defaults.set("ultra", forKey: AppSettings.signedDistanceQualityKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).signedDistanceQuality, .medium, "unknown → medium")
        defaults.set(3, forKey: AppSettings.signedDistanceQualityKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).signedDistanceQuality, .medium, "wrong type → medium")
        XCTAssertTrue(VisualChoice.signedDistance.isNative)
        XCTAssertFalse(VisualChoice.signedDistance.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.signedDistance.title, "SDF Shapes")
    }

    /// VIS-017-R8: an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertEqual(AppSettings.signedDistanceQualityKey, "settings.signedDistance.quality")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.signedDistance.quality"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.signedDistance.quality"))
    }

    func testHostChangesQualityInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .signedDistance(quality: .medium), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "SDF Shapes visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "signedDistance")
        XCTAssertEqual(host.view.accessibilityValue, "Medium quality, Glow off")
        XCTAssertFalse(NativeSpectrumStyle.signedDistance(quality: .medium).drainsAnalysisEvents, "bands only")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration.signedDistance?.quality, .medium)
        try host.apply(style: .signedDistance(quality: .low))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "quality changes in place")
        XCTAssertEqual(generator.configuration.signedDistance?.quality, .low)
        XCTAssertEqual(host.view.accessibilityValue, "Low quality, Glow off")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "ACC-001")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .signedDistance(quality: .high))
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion survives a quality change")
        XCTAssertEqual(generator.configuration.palette, .colorBlindSafe)
        // Switching with another noise-field mode keeps the generator.
        try host.apply(style: .tunnel(pace: .beat))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertNil(generator.configuration.signedDistance)
        try host.apply(style: .signedDistance(quality: .medium))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertEqual(generator.configuration.signedDistance?.quality, .medium)
        XCTAssertEqual(generator.configuration.tunnelPace, 0)
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
    }

    /// VIS-017-R10: no SCN-001 kind for the SDF shapes; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .signedDistance)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
