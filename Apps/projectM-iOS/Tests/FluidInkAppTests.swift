// FluidInkAppTests.swift — VIS-011-T10: the Fluid Ink choice in the app (VIS-011-R2, R11, R12): the choice is stored and
// restored, Bars does not apply and no key of its own is written; the host names itself, subscribes to the analysis
// bus and queues onsets into the generator, switches to and from the other noise-field modes in place (same generator,
// same fluid storage), and applies the palette and Reduce Motion; a scene captured while it is shown records no native
// layer. The host tests need a Metal device (the simulator renders with the host GPU).
import AnalysisFeatures
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class FluidInkAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "FluidInkAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoiceIsStoredWithoutAKeyOfItsOwn() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.visual = .fluidInk
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "fluidInk")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .fluidInk)
        XCTAssertTrue(VisualChoice.fluidInk.isNative)
        XCTAssertFalse(VisualChoice.fluidInk.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.fluidInk.title, "Fluid Ink")
        let keys: Set<String> = Set(defaults.dictionaryRepresentation().keys).filter { (k: String) -> Bool in k.hasPrefix("settings.") }
        XCTAssertFalse(keys.contains { (k: String) -> Bool in k.lowercased().contains("fluid") }, "no key of its own: \(keys)")
        XCTAssertFalse(AppSettings.allKeys.contains { (k: String) -> Bool in k.lowercased().contains("fluid") })
        XCTAssertTrue(NativeSpectrumStyle.fluidInk.drainsAnalysisEvents, "onsets reach it (ANL-016)")
    }

    func testHostNamesItselfQueuesOnsetsAndSwitchesModesInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .fluidInk, barCount: .b64)
        XCTAssertEqual(host.view.accessibilityLabel, "Fluid Ink visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "fluidInk")
        XCTAssertEqual(host.view.accessibilityValue, "Ink from sudden sounds, Glow off")
        XCTAssertNotNil(host.beatEvents, "the host subscribes to the analysis bus")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.fluidInk())
        let pass = try XCTUnwrap(generator.fluidPass, "made when the host builds it, off the frame loop")
        XCTAssertTrue(generator.enqueueImpulse(atNanoseconds: 1, strength: 0.8, threshold: 0.3))
        XCTAssertEqual(generator.fluidScheduler.pendingImpulses, 1)
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-011-R11")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .tunnel(pace: .beat))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertFalse(generator.configuration.fluidInk)
        XCTAssertNil(host.beatEvents, "the tunnel does not subscribe")
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertFalse(generator.configuration.fluidInk, "Noise Field draws the field")
        try host.apply(style: .fluidInk)
        XCTAssertTrue(host.noiseFieldGenerator === generator, "in place")
        XCTAssertNotNil(host.beatEvents)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.fluidInk(reduceMotion: true, palette: .colorBlindSafe),
                       "Reduce Motion and the palette kept")
        XCTAssertTrue(generator.fluidPass === pass, "the fluid's storage is never replaced")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .fluidInk)
        XCTAssertTrue(try XCTUnwrap(host.noiseFieldGenerator).configuration.reduceMotion, "a new generator gets Reduce Motion too")
    }

    /// VIS-011-R12: no SCN-001 kind for fluid ink; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .fluidInk)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
