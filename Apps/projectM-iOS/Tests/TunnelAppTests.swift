// TunnelAppTests.swift — VIS-015-T09: the tunnel choice in the app (VIS-015-R4, R8, R9, R11, R12): the Pace setting's
// default, persistence and safe reading; every key list; the host names itself, changes the pace in place (same
// generator, the speed eases), hands the generator the tempo it reads each frame (SHOW-011's snapshot mapping), switches
// to and from Noise Field and Kaleidoscope in place, and applies the palette and Reduce Motion; a scene captured while it
// is shown records no native layer. The host tests need a Metal device (the simulator renders with the host GPU).
import LibraryBackup
import Metal
import PerformanceControl
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class TunnelAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "TunnelAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testPaceDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.tunnelPace, .beat)
        settings.visual = .tunnel
        settings.tunnelPace = .half
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "tunnel")
        XCTAssertEqual(defaults.string(forKey: "settings.tunnel.pace"), "half")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .tunnel)
        XCTAssertEqual(reloaded.tunnelPace, .half)
        defaults.set("warp9", forKey: AppSettings.tunnelPaceKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).tunnelPace, .beat, "unknown → beat")
        defaults.set(3, forKey: AppSettings.tunnelPaceKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).tunnelPace, .beat, "not a string → beat")
        XCTAssertTrue(VisualChoice.tunnel.isNative)
        XCTAssertFalse(VisualChoice.tunnel.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.tunnel.title, "Tunnel")
    }

    /// VIS-015-R9: an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeyIsInEveryList() {
        let key = "settings.tunnel.pace"
        XCTAssertEqual(AppSettings.tunnelPaceKey, key)
        XCTAssertTrue(AppSettings.allKeys.contains(key))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key))
    }

    func testHostReadsTheTempoAndChangesPaceInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .tunnel(pace: .beat), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Tunnel visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "tunnel")
        XCTAssertEqual(host.view.accessibilityValue, "1 ring per beat, Glow off")
        let generator = try XCTUnwrap(host.noiseFieldGenerator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.tunnel(pace: .beat))
        // The tempo, as AppCoordinator.connectLFOs maps SHOW-011's snapshot: a manual tap tempo is read each frame.
        let tempo = TempoCoordinator(clock: { 0 }, stateClock: { 0 }, announce: { (_: String) -> Void in })
        tempo.updateEstimate(TempoEstimate(bpm: 128, confidence: 0.9, beatNanoseconds: nil))
        host.tunnelTempo = { [weak tempo] () -> TunnelTempo in
            guard let snapshot = tempo?.snapshot else { return .none }
            return TunnelTempo(bpm: snapshot.bpm, confidence: snapshot.confidence)
        }
        host.driveTunnel()
        XCTAssertEqual(generator.tempo.validBPM, 128, "a confident estimate")
        tempo.updateEstimate(TempoEstimate(bpm: 128, confidence: 0.2, beatNanoseconds: nil))
        host.driveTunnel()
        XCTAssertNil(generator.tempo.validBPM, "an unsure estimate is no tempo")
        host.tunnelTempo = nil
        host.driveTunnel()
        XCTAssertEqual(generator.tempo, .none)
        try host.apply(style: .tunnel(pace: .double))
        XCTAssertTrue(host.noiseFieldGenerator === generator, "the pace changes in place")
        XCTAssertEqual(generator.configuration.tunnelPace, 2)
        XCTAssertEqual(host.view.accessibilityValue, "2 rings per beat, Glow off")
        host.reduceMotion = true
        host.palette = .colorBlindSafe
        XCTAssertTrue(generator.configuration.reduceMotion, "VIS-015-R8")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13")
        try host.apply(style: .noiseField(frequency: .high, octaves: 2, seed: 7))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertFalse(generator.configuration.isTunnel, "Noise Field draws the field")
        try host.apply(style: .kaleidoscope(wedges: 5))
        try host.apply(style: .tunnel(pace: .half))
        XCTAssertTrue(host.noiseFieldGenerator === generator)
        XCTAssertEqual(generator.configuration, NoiseFieldConfiguration.tunnel(pace: .half, reduceMotion: true, palette: .colorBlindSafe),
                       "the tunnel's own settings, Reduce Motion and the palette kept")
        try host.apply(style: .circular)
        XCTAssertNil(host.noiseFieldGenerator)
        try host.apply(style: .tunnel(pace: .beat))
        XCTAssertTrue(try XCTUnwrap(host.noiseFieldGenerator).configuration.reduceMotion, "a new generator gets Reduce Motion too")
    }

    /// VIS-015-R11: no SCN-001 kind for the tunnel; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .tunnel)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
