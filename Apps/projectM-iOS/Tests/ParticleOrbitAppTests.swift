// ParticleOrbitAppTests.swift — VIS-009-T13: the particle orbit choice in the app (VIS-009-R4, R9 to R12): the
// Radius setting's default, persistence and safe reading; every key list; the host names itself, subscribes to the
// analysis bus, changes the radius in place (same generator), applies the palette and Reduce Motion (also to a
// generator a style change builds), and a loop start clears queued beats; "mapped bass": unbound the drive is the
// setting and the kick envelope, bound the modulator's value with the built-in bass off; a scene captured while it is
// shown records no native layer. Deterministic: kick values and frame times are passed in. The host tests need a Metal
// device (the simulator renders with the host GPU); they skip without one.
import LibraryBackup
import Metal
import ParameterGraph
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParticleOrbitAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ParticleOrbitAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingDefaultsPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.particleOrbitRadius, .medium, "Medium by default")
        XCTAssertEqual(ParticleOrbitRadius.allCases.map(\.title), ["Small", "Medium", "Large"])
        XCTAssertEqual(ParticleOrbitRadius.allCases.map(\.value), [0.35, 0.5, 0.65])
        XCTAssertEqual(ParticleOrbitRadius.medium.value, ParticleOrbitConfiguration.defaultRadius, "the setting's default is the parameter's default")
        settings.visual = .particleOrbit
        settings.particleOrbitRadius = .large
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "particleOrbit")
        XCTAssertEqual(defaults.string(forKey: "settings.particleOrbit.radius"), "large")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .particleOrbit)
        XCTAssertEqual(reloaded.particleOrbitRadius, .large)
        defaults.set("huge", forKey: AppSettings.particleOrbitRadiusKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleOrbitRadius, .medium, "unknown → Medium")
        defaults.set(3, forKey: AppSettings.particleOrbitRadiusKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleOrbitRadius, .medium, "not a string → Medium")
        XCTAssertTrue(VisualChoice.particleOrbit.isNative)
        XCTAssertFalse(VisualChoice.particleOrbit.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.particleOrbit.title, "Particle Orbit")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .particleOrbit),
                       "Particle Orbit isn't available on this device. Showing projectM.")
    }

    /// VIS-009-R10: the key is an FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertTrue(AppSettings.allKeys.contains("settings.particleOrbit.radius"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.particleOrbit.radius"))
    }

    func testHostSubscribesChangesRadiusInPlaceAndFollowsReduceMotion() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleOrbit(radius: .medium), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Particle Orbit visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "particleOrbit")
        XCTAssertEqual(host.view.accessibilityValue, "Medium radius, Glow off")
        XCTAssertNotNil(host.beatEvents, "the centre pulse reads the analysis bus's beats")
        let generator = try XCTUnwrap(host.particleOrbitGenerator)
        XCTAssertEqual(generator.configuration.radius, 0.5)
        XCTAssertFalse(generator.configuration.reduceMotion)
        try host.apply(style: .particleOrbit(radius: .small))
        XCTAssertTrue(host.particleOrbitGenerator === generator, "the radius changes in place")
        XCTAssertEqual(generator.configuration.radius, 0.35)
        XCTAssertEqual(host.view.accessibilityValue, "Small radius, Glow off")
        host.reduceMotion = true
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion: half speed, smaller pulse, slower radius")
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the orbit")
        // An empty bus drains to nothing; a queued beat is cleared by a loop start.
        host.drainBeatEvents(context: host.frameContext(timeNanoseconds: 1_000_000_000, frameDuration: 1.0 / 60))
        XCTAssertEqual(generator.simulation.pendingBeats, 0)
        generator.enqueueBeat(atNanoseconds: 2_000_000_000)
        XCTAssertEqual(generator.simulation.pendingBeats, 1)
        host.resume()
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(generator.simulation.pendingBeats, 0, "the loop start clears beats heard while stopped")
        XCTAssertEqual(generator.simulation.pulse, 0)
        try host.apply(style: .circular)
        XCTAssertNil(host.beatEvents, "no subscription once the orbit is gone")
        XCTAssertNil(host.particleOrbitGenerator)
        try host.apply(style: .particleOrbit(radius: .large))
        let rebuilt = try XCTUnwrap(host.particleOrbitGenerator)
        XCTAssertNotNil(host.beatEvents)
        XCTAssertEqual(rebuilt.configuration.radius, 0.65)
        XCTAssertTrue(rebuilt.configuration.reduceMotion, "a new generator gets Reduce Motion too")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        host.pause()
    }

    /// VIS-009-R4: unbound, the drive is the Radius setting and the kick; with a MOD-002 binding on the radius the base
    /// is the modulator's value and the built-in bass is off (bass never counts twice).
    func testDriveFollowsTheKickUnboundAndTheBindingWhenBound() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleOrbit(radius: .medium), barCount: .b32)
        let generator = try XCTUnwrap(host.particleOrbitGenerator)
        host.driveParticleOrbit(kick: 0)
        XCTAssertEqual(generator.simulation.targetRadius, 0.5, accuracy: 1e-9, "silence: the setting")
        host.driveParticleOrbit(kick: 0.5)
        XCTAssertEqual(generator.simulation.targetRadius, 0.5 * (1 + 0.4 * 0.5), accuracy: 1e-9, "the kick swells the ring")
        try host.bind(AudioFeatureBinding(source: .kick, target: VisualParameterIDs.particleOrbitRadius, outputStart: 0.3, outputEnd: 0.7))
        let bands = [Float](repeating: 0, count: 32)
        for frame in 0..<60 {
            let time = UInt64(frame) * 16_666_667
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: 0, timeNanoseconds: time)
            }
        }
        host.driveParticleOrbit(kick: 1)
        XCTAssertEqual(generator.simulation.targetRadius, 0.3, accuracy: 0.01, "bound: the binding's value, the built-in kick ignored")
        XCTAssertTrue(host.unbind(VisualParameterIDs.particleOrbitRadius))
        host.driveParticleOrbit(kick: 1)
        XCTAssertEqual(generator.simulation.targetRadius, 0.5 * 1.4, accuracy: 1e-9, "unbound again: the setting and the kick")
    }

    /// VIS-009-R11: no SCN-001 kind for the orbit; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .particleOrbit)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
