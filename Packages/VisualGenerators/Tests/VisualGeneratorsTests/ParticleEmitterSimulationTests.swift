// ParticleEmitterSimulationTests.swift — SHD-007-T05, the roadmap acceptance: "Ten-second seeded run matches expected
// spawn count and lifetime bounds" (SHD-007-R3 to R6, S1 to S3; contracts/particle-emitter.md E1). A pure
// simulation on an injected frame clock (no GPU, no wall clock): 10 s at 60 Hz and at a seeded jittery frame rate.
import XCTest
@testable import VisualGenerators

final class ParticleEmitterSimulationTests: XCTestCase {
    private static let anchor: UInt64 = 1_000_000_000
    private static let tenSeconds: UInt64 = 10_000_000_000
    private static let frame60 = 1.0 / 60

    /// Seed S, rate 37.5/s, lifetime [0.8, 1.6] s, a circle, box bounds with bounce.
    private static let acceptance = ParticleEmitterSettings(shape: .circle, shapeWidth: 0.5, rate: 37.5, minimumSpeed: 2,
                                                            maximumSpeed: 4, direction: 10, spread: 30, minimumLifetime: 0.8,
                                                            maximumLifetime: 1.6, gravity: 3, bounds: .box, boxHalfWidth: 1,
                                                            boxHeight: 2.5, action: .bounce, restitution: 0.6, seed: 0x5EED_0007)

    /// Frame times after the anchor: 60 Hz (frame i at ⌊i·10⁹/60⌋) up to exactly 10 s.
    private static var sixtyHertz: [UInt64] { (1...600).map { (i: Int) -> UInt64 in UInt64(i) * tenSeconds / 600 } }

    /// Seeded frame gaps of 5…40 ms, the last frame clipped to exactly 10 s.
    private static func jittery(seed: UInt64) -> [UInt64] {
        var rng = SplitMix64(seed: seed)
        var t: UInt64 = 0
        var out: [UInt64] = []
        while t < tenSeconds {
            let gap: UInt64 = 5_000_000 + rng.next() % 35_000_001
            t = min(t + gap, tenSeconds)
            out.append(t)
        }
        return out
    }

    private struct Run {
        let simulation: ParticleFountainSimulation
        var outsideBounds = 0
        var maximumLive = 0
        var storageChanged = false
    }

    /// Runs `settings` over `frames` (offsets after the anchor), checking the bounds and the pool after every frame.
    private func run(_ settings: ParticleEmitterSettings, frames: [UInt64], reduceMotion: Bool = false) -> Run {
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(reduceMotion: reduceMotion,
                                                                                                 emitter: settings))
        let storage = simulation.storageAddresses
        var result = Run(simulation: simulation)
        let box = ParticleFountainSimulation.box(settings)
        simulation.advance(toNanoseconds: Self.anchor)   // sets the anchor
        for offset in frames {
            simulation.advance(toNanoseconds: Self.anchor + offset)
            result.maximumLive = max(result.maximumLive, simulation.liveCount)
            guard settings.bounds != .none else { continue }
            for i in 0..<simulation.liveCount {
                let p = simulation.particle(i)
                if p.x < box.left || p.x > box.right || p.y < box.bottom || p.y > box.top { result.outsideBounds += 1 }
            }
        }
        result.storageChanged = simulation.storageAddresses != storage
        return result
    }

    func testTenSecondSeededRunMatchesSpawnCountAndLifetimeBounds() {
        let settings = Self.acceptance
        let steps = UInt64(ParticleFountainConfiguration.stepsPerSecond) * 10
        XCTAssertEqual(settings.expectedSpawns(steps: steps), 375, "⌊37.5 × 10⌋")
        for frames in [Self.sixtyHertz, Self.jittery(seed: 42)] {
            let r = run(settings, frames: frames)
            let s = r.simulation
            XCTAssertEqual(s.stepIndex, steps, "10 s of 1/240 s steps")
            XCTAssertEqual(s.spawnAttempts, 375, "exact spawn count")
            XCTAssertEqual(s.spawnedCount, 375)
            XCTAssertEqual(s.droppedParticles, 0)
            XCTAssertGreaterThan(s.expiredCount, 300, "most particles lived out their lifetime")
            XCTAssertEqual(s.expiredCount + s.liveCount, s.spawnedCount, "bounce: every death is by age")
            XCTAssertEqual(s.boundKills, 0)
            XCTAssertGreaterThan(s.bounces, 0, "the box was hit")
            XCTAssertGreaterThanOrEqual(s.minimumAgeAtExpiry, 0.8, "never dies before the lifetime minimum")
            XCTAssertLessThanOrEqual(s.maximumAgeAtExpiry, 1.6 + Self.frame60, "dies within one frame of the maximum")
            XCTAssertLessThan(s.minimumAgeAtExpiry, 0.9, "draws reach the low end")
            XCTAssertGreaterThan(s.maximumAgeAtExpiry, 1.5, "draws reach the high end")
            for i in 0..<s.liveCount {
                let p = s.particle(i)
                XCTAssertTrue(p.life >= 0.8 && p.life <= 1.6, "lifetime drawn within [0.8, 1.6]: \(p.life)")
            }
            XCTAssertEqual(r.outsideBounds, 0, "no particle outside the box in any frame")
            XCTAssertLessThanOrEqual(r.maximumLive, ParticleFountainSimulation.capacity)
            XCTAssertFalse(r.storageChanged, "the fixed pool is never reallocated")
            XCTAssertEqual(ParticleFountainSimulation.capacity, 512)
        }
    }

    func testFrameTimingDoesNotChangeTheRunAndSeedsDo() {
        let a = run(Self.acceptance, frames: Self.sixtyHertz).simulation
        let b = run(Self.acceptance, frames: Self.jittery(seed: 7)).simulation
        let again = run(Self.acceptance, frames: Self.sixtyHertz).simulation
        XCTAssertEqual(a.liveParticles, b.liveParticles, "60 Hz and jittery frames give the same particles")
        XCTAssertEqual(a.liveParticles, again.liveParticles, "the same seed reproduces the run")
        XCTAssertEqual(a.minimumAgeAtExpiry, b.minimumAgeAtExpiry)
        XCTAssertEqual(a.maximumAgeAtExpiry, b.maximumAgeAtExpiry)
        var other = Self.acceptance
        other.seed += 1
        let c = run(other, frames: Self.sixtyHertz).simulation
        XCTAssertEqual(c.spawnAttempts, 375, "the count does not depend on the seed")
        XCTAssertNotEqual(a.liveParticles, c.liveParticles, "another seed gives another run")
    }

    func testAFullPoolDropsButTheAttemptsStayExact() {
        let settings = ParticleEmitterSettings(rate: 240, minimumLifetime: 10, maximumLifetime: 10, bounds: .box)
        let frames = (1...300).map { (i: Int) -> UInt64 in UInt64(i) * Self.tenSeconds / 600 }   // 5 s
        let r = run(settings, frames: frames)
        XCTAssertEqual(r.simulation.spawnAttempts, 1200)
        XCTAssertEqual(r.simulation.spawnedCount, 512)
        XCTAssertEqual(r.simulation.droppedParticles, 688)
        XCTAssertEqual(r.maximumLive, 512, "the pool is full, never larger")
        XCTAssertEqual(r.outsideBounds, 0)
        XCTAssertFalse(r.storageChanged)
    }

    func testRateZeroReduceMotionAndKill() {
        let none = run(ParticleEmitterSettings(rate: 0), frames: Self.sixtyHertz).simulation
        XCTAssertEqual(none.spawnAttempts, 0)
        XCTAssertEqual(none.spawnedCount, 0)

        let slow = run(Self.acceptance, frames: Self.sixtyHertz, reduceMotion: true).simulation
        XCTAssertEqual(Self.acceptance.expectedSpawns(steps: 2400, reduceMotion: true), 187)
        XCTAssertEqual(slow.spawnAttempts, 187, "Reduce Motion halves the rate")
        XCTAssertGreaterThanOrEqual(slow.minimumAgeAtExpiry, 0.8 / 0.7, "lifetime ÷ 0.7")

        var kill = Self.acceptance
        kill.action = .kill
        kill.bounds = .floor
        let r = run(kill, frames: Self.sixtyHertz)
        XCTAssertEqual(r.simulation.spawnAttempts, 375)
        XCTAssertGreaterThan(r.simulation.boundKills, 0, "particles falling through the floor are removed")
        XCTAssertEqual(r.simulation.bounces, 0)
        XCTAssertEqual(r.outsideBounds, 0, "none is ever below the floor")
        XCTAssertEqual(r.simulation.expiredCount + r.simulation.boundKills + r.simulation.liveCount, 375)
    }

    func testOnsetBurstsUseTheEmitterAndResetRestoresItsSeed() {
        let settings = ParticleEmitterSettings(shape: .rectangle, shapeWidth: 1, shapeHeight: 0.4, rate: 0,
                                               minimumLifetime: 3, maximumLifetime: 3, seed: 99)
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(emitter: settings))
        simulation.advance(toNanoseconds: Self.anchor)
        simulation.enqueueOnset(atNanoseconds: Self.anchor, strength: 1, threshold: 0)
        simulation.advance(toNanoseconds: Self.anchor + 10_000_000)
        XCTAssertEqual(simulation.spawnedCount, 24, "VIS-008's burst size")
        let first = simulation.liveParticles
        XCTAssertTrue(first.allSatisfy { (p: FountainParticle) -> Bool in p.life == 3 }, "the emitter's lifetime")
        XCTAssertGreaterThan(Set(first.map { (p: FountainParticle) -> Double in p.x }).count, 20, "spread over the rectangle")
        simulation.reset()
        simulation.advance(toNanoseconds: Self.anchor)
        simulation.enqueueOnset(atNanoseconds: Self.anchor, strength: 1, threshold: 0)
        simulation.advance(toNanoseconds: Self.anchor + 10_000_000)
        XCTAssertEqual(simulation.liveParticles, first, "the reset restores the emitter's seed")
    }
}
