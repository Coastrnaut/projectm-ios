// WaterfallAppTests.swift — VIS-020-T09: the Spectrum Waterfall choice in the app (VIS-020-R8, R9, R11, R12): the choice
// is stored and restored, Bars applies and no key of its own is written; the host names itself, switches to and from
// the other noise-field modes in place (same generator, same history storage), and applies the palette and Reduce
// Motion; a scene captured while it is shown records no native layer. The host tests need a Metal device (the
// simulator renders with the host GPU).
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class WaterfallAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "WaterfallAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoiceIsStoredAndBarsApplies() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.visual = .spectrumWaterfall
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "spectrumWaterfall")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .spectrumWaterfall)
        XCTAssertTrue(VisualChoice.spectrumWaterfall.isNative)
        XCTAssertTrue(VisualChoice.spectrumWaterfall.usesBars, "Bars sets the band count feeding the columns")
        XCTAssertEqual(VisualChoice.spectrumWaterfall.title, "Spectrum Waterfall")
        let keys: Set<String> = Set(defaults.dictionaryRepresentation().keys).filter { (k: String) -> Bool in k.hasPrefix("settings.") }
        XCTAssertFalse(keys.contains { (k: String) -> Bool in k.lowercased().contains("waterfall") }, "no key of its own: \(keys)")
    }

    func testHostNamesItselfAndSwitchesModesInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .waterfall, barCount: .b64)
        XCTAssertEqual(host.view.accessibilityLabel, "Spectrum Waterfall visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "spectrumWaterfall")
        XCTAssertEqual(host.view.accessibilityValue, "Newest at top, Glow off")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.waterfall())
        let texture = ObjectIdentifier(generator.historyTexture)
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-020-R8")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .tunnel(pace: .beat))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertFalse(generator.configuration.waterfall)
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertFalse(generator.configuration.waterfall, "Noise Field draws the field")
        try host.apply(style: .waterfall)
        XCTAssertTrue(host.noiseFieldGenerator === generator, "in place")
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.waterfall(reduceMotion: true, palette: .colorBlindSafe),
                       "Reduce Motion and the palette kept")
        XCTAssertEqual(ObjectIdentifier(generator.historyTexture), texture, "the history texture is never replaced")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .waterfall)
        XCTAssertTrue(try XCTUnwrap(host.noiseFieldGenerator).configuration.reduceMotion, "a new generator gets Reduce Motion too")
    }

    /// VIS-020-R11: no SCN-001 kind for the waterfall; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .spectrumWaterfall)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
