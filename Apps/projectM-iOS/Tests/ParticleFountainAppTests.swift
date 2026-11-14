// ParticleFountainAppTests.swift — VIS-008-T11: the particle fountain choice in the app (VIS-008-R9 to R12): the
// setting's default, persistence and safe reading; every key list; the host names itself, subscribes to the analysis
// bus, changes gravity in place (same generator, later bursts), applies the palette and Reduce Motion (also to a
// generator a style change builds), and a loop start clears particles and pending onsets; a scene captured while it
// is shown records no native layer. The bus's onset mapping is ParticleFountainTrigger's package test (the bus's
// publish is internal to AnalysisFeatures). The host test needs a Metal device (the simulator renders with the host
// GPU); it skips without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ParticleFountainAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ParticleFountainAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingDefaultsPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.particleGravity, .medium, "Medium by default")
        XCTAssertEqual(ParticleGravity.allCases.map(\.title), ["Low", "Medium", "High"])
        XCTAssertEqual(ParticleGravity.allCases.map(\.value), [2.0, 3.0, 4.5])
        settings.visual = .particleFountain
        settings.particleGravity = .high
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "particleFountain")
        XCTAssertEqual(defaults.string(forKey: "settings.particleFountain.gravity"), "high")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .particleFountain)
        XCTAssertEqual(reloaded.particleGravity, .high)
        defaults.set("heavy", forKey: AppSettings.particleGravityKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleGravity, .medium, "unknown → Medium")
        defaults.set(3, forKey: AppSettings.particleGravityKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleGravity, .medium, "not a string → Medium")
        XCTAssertTrue(VisualChoice.particleFountain.isNative)
        XCTAssertFalse(VisualChoice.particleFountain.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.particleFountain.title, "Particle Fountain")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .particleFountain),
                       "Particle Fountain isn't available on this device. Showing projectM.")
    }

    /// VIS-008-R10: the key is an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertTrue(AppSettings.allKeys.contains("settings.particleFountain.gravity"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.particleFountain.gravity"))
    }

    func testHostSubscribesChangesGravityInPlaceAndFollowsReduceMotion() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleFountain(gravity: .medium), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Particle Fountain visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "particleFountain")
        XCTAssertEqual(host.view.accessibilityValue, "Medium gravity, Glow off")
        XCTAssertNotNil(host.beatEvents, "the fountain reads the analysis bus's onsets")
        let generator = try XCTUnwrap(host.particleFountainGenerator)
        XCTAssertEqual(generator.configuration.gravity, 3.0)
        XCTAssertFalse(generator.configuration.reduceMotion)
        try host.apply(style: .particleFountain(gravity: .low))
        XCTAssertTrue(host.particleFountainGenerator === generator, "gravity changes in place")
        XCTAssertEqual(generator.configuration.gravity, 2.0)
        XCTAssertEqual(host.view.accessibilityValue, "Low gravity, Glow off")
        host.reduceMotion = true
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion halves and slows later bursts")
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the fountain")
        // An empty bus drains to nothing; queued onsets and particles are cleared by a loop start.
        host.drainBeatEvents(context: host.frameContext(timeNanoseconds: 1_000_000_000, frameDuration: 1.0 / 60))
        XCTAssertEqual(generator.simulation.pendingOnsets, 0)
        generator.enqueueOnset(atNanoseconds: 1_000_000_000, strength: 1, threshold: 0)
        generator.simulation.advance(toNanoseconds: 1_000_000_000)
        generator.simulation.advance(toNanoseconds: 1_100_000_000)
        XCTAssertEqual(generator.simulation.liveCount, 12, "a Reduce Motion burst: 24 halved")
        generator.enqueueOnset(atNanoseconds: 1_100_000_000, strength: 1, threshold: 0)
        host.resume()
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(generator.simulation.liveCount, 0, "the loop start clears the particles")
        XCTAssertEqual(generator.simulation.pendingOnsets, 0, "and the pending onsets")
        try host.apply(style: .circular)
        XCTAssertNil(host.beatEvents, "no subscription once the fountain is gone")
        XCTAssertNil(host.particleFountainGenerator)
        try host.apply(style: .particleFountain(gravity: .high))
        let rebuilt = try XCTUnwrap(host.particleFountainGenerator)
        XCTAssertNotNil(host.beatEvents)
        XCTAssertEqual(rebuilt.configuration.gravity, 4.5)
        XCTAssertTrue(rebuilt.configuration.reduceMotion, "a new generator gets Reduce Motion too")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        try host.apply(style: .beatRings(life: .medium))
        XCTAssertNotNil(host.beatEvents, "beat rings keep the subscription")
        host.pause()
    }

    /// VIS-008-R11: no SCN-001 kind for the fountain; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .particleFountain)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
