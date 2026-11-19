// ParticleEmitterEditorTests.swift — SHD-007-T10 (R7, R8): the stored emitter's defaults, persistence and lenient
// reading; Reset; the slider writes keep min ≤ max; the fountain style carries the emitter only while the switch is on
// and the host applies it (same generator, restarted on a new seed); the preview's run depends only on the frame index
// and the settings. The host test needs a Metal device (the simulator renders with the host GPU); it skips without one.
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ParticleEmitterEditorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ParticleEmitterEditorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoicePersistsReadsLenientlyAndResets() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.particleEmitter, ParticleEmitterChoice(), "off with defaults")
        XCTAssertNil(settings.particleEmitter.effective)
        XCTAssertNil(defaults.object(forKey: AppSettings.particleEmitterKey), "absent at the defaults")
        var choice = ParticleEmitterChoice(enabled: true)
        choice.settings.shape = .circle
        choice.settings.rate = 75.5
        choice.settings.bounds = .box
        settings.particleEmitter = choice
        XCTAssertNotNil(defaults.data(forKey: "settings.particleFountain.emitter"))
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.particleEmitterKey))
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.particleEmitter, choice, "persisted")
        XCTAssertEqual(reloaded.particleEmitter.effective?.rate, 75.5)

        defaults.set(Data("not json".utf8), forKey: AppSettings.particleEmitterKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleEmitter, ParticleEmitterChoice())
        defaults.set(Data(#"{"enabled":true,"settings":{"rate":9999,"shape":"star"}}"#.utf8), forKey: AppSettings.particleEmitterKey)
        let lenient = AppSettings(defaults: defaults, systemReduceMotion: false).particleEmitter
        XCTAssertTrue(lenient.enabled)
        XCTAssertEqual(lenient.settings.rate, 240, "clamped")
        XCTAssertEqual(lenient.settings.shape, .point, "unknown → default")

        reloaded.particleEmitter = ParticleEmitterChoice()   // Reset to defaults
        XCTAssertNil(defaults.object(forKey: AppSettings.particleEmitterKey), "Reset removes the key")
    }

    func testSliderWritesKeepRangesOrdered() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let editing = ParticleEmitterEditing(settings: settings)
        editing.binding(\.minimumLifetime, upperPartner: \.maximumLifetime).wrappedValue = 4
        XCTAssertEqual(settings.particleEmitter.settings.minimumLifetime, 4)
        XCTAssertEqual(settings.particleEmitter.settings.maximumLifetime, 4, "the max follows the min up")
        editing.binding(\.maximumSpeed, lowerPartner: \.minimumSpeed).wrappedValue = 1
        XCTAssertEqual(settings.particleEmitter.settings.minimumSpeed, 1, "the min follows the max down")
        editing.binding(\.rate).wrappedValue = 500
        XCTAssertEqual(settings.particleEmitter.settings.rate, 240, "clamped")
        let target = editing.target(editing.binding(\.spread))
        target.set(45)
        XCTAssertEqual(target.get(), 45)
        XCTAssertEqual(ParticleEmitterSliders.rate.id, "particleEmitterRate")
    }

    func testFountainStyleCarriesTheEmitterOnlyWhenOnAndTheHostAppliesIt() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let emitter = ParticleEmitterSettings(rate: 60, seed: 11)
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleFountain(gravity: .medium), barCount: .b32)
        let fountain = try XCTUnwrap(host.particleFountainGenerator)
        XCTAssertNil(fountain.configuration.emitter, "VIS-008 unchanged without the emitter")
        try host.apply(style: .particleFountain(gravity: .medium, emitter: emitter))
        XCTAssertTrue(host.particleFountainGenerator === fountain, "in place, no rebuild")
        XCTAssertEqual(fountain.configuration.emitter, emitter)
        XCTAssertEqual(NativeSpectrumHost.accessibilityValue(style: .particleFountain(gravity: .medium, emitter: emitter), glowEnabled: false,
                                                             glowUnavailable: false), "Custom emitter, Glow off")
        try host.apply(style: .particleFountain(gravity: .medium, emitter: nil))
        XCTAssertNil(fountain.configuration.emitter, "off again")
        let built = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleFountain(gravity: .low, emitter: emitter), barCount: .b32)
        XCTAssertEqual(built.particleFountainGenerator?.configuration.emitter, emitter, "a built generator gets it too")
    }

    func testPreviewRunDependsOnlyOnFramesAndSettings() {
        let settings = ParticleEmitterSettings(shape: .line, rate: 30, bounds: .box, seed: 5)
        let a = ParticleEmitterPreview(settings: settings)
        let b = ParticleEmitterPreview(settings: settings)
        a.advance(frames: 60)
        for _ in 0..<60 { b.advance() }
        XCTAssertEqual(a.simulation.spawnedCount, 60, "⌊30 × 2 s⌋")
        XCTAssertEqual(a.simulation.liveParticles, b.simulation.liveParticles, "one jump or 60 steps: the same run")
        XCTAssertEqual(a.summary, b.summary)
        a.configure(ParticleEmitterSettings(shape: .line, rate: 30, bounds: .box, seed: 6))
        XCTAssertEqual(a.frame, 0, "a change restarts the run")
        XCTAssertEqual(a.simulation.liveCount, 0)
        a.advance(frames: 60)
        XCTAssertNotEqual(a.simulation.liveParticles, b.simulation.liveParticles, "another seed, another run")
    }

    #if DEBUG
    /// QA-011 SHD-008-T18 (device finding 2026-11-18): the DEBUG bounds probe counts a young particle by where it
    /// spawned, not where its first steps took it; every spawn of a path emitter is inside the path (SHD-008-R7).
    func testTheBoundsProbeCountsSpawnPointsInsideThePath() throws {
        let triangle = try VectorPath([VectorPoint(x: 0.2, y: 0.8), VectorPoint(x: 0.5, y: 0.2), VectorPoint(x: 0.8, y: 0.8)])
        let preview = ParticleEmitterPreview(settings: ParticleEmitterSettings(shape: .path, rate: 240, seed: 7, path: triangle))
        var newest = 0, inside = 0
        for _ in 0..<60 {
            preview.advance()
            let line: String = preview.boundsProbe
            func number(_ key: String) -> Int {
                line.split(separator: " ").first { $0.hasPrefix(key + "=") }.flatMap { Int($0.dropFirst(key.count + 1)) } ?? -1
            }
            newest += number("newest")
            inside += number("newestInPath")
        }
        XCTAssertGreaterThan(newest, 20, "young particles seen")
        XCTAssertEqual(inside, newest, "every spawn point lies inside the triangle")
    }
    #endif
}
