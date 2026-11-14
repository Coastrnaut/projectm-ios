// ParticleFountainSimulationTests.swift — VIS-008-T03, T05, T08: the roadmap acceptance ("Fixed seed and event
// log produce repeatable particle counts and trajectories") and the simulation's rules on the CPU (VIS-008-R2 to
// R7, R9; S1 to S4, S6): a fixed seed and onset log replayed twice is bit-identical; 60 Hz, 30 Hz and irregular
// frames agree at shared times; another seed changes trajectories but not counts; burst sizes; the closed-form
// ballistic path; bounds and counters; death; Reduce Motion; reset, backwards time and long gaps; the layout's
// squares; the bus trigger. The clock is injected (integer nanoseconds). Pure Swift: runs in the Linux shape.
import AnalysisFeatures
import XCTest
@testable import VisualBandFeed
@testable import VisualGenerators

final class ParticleFountainSimulationTests: XCTestCase {
    /// An onset: seconds on the frame clock, strength, threshold.
    private typealias Onset = (seconds: Double, strength: Float, threshold: Float)

    /// The fixed event log: varied strengths, one at a frame time, two close together.
    private static let log: [Onset] = [(0.05, 0.40, 0.10), (0.37, 0.20, 0.12), (0.52, 0.90, 0.10), (0.55, 0.15, 0.10),
                                       (1.0, 0.30, 0.08), (1.234_567, 0.60, 0.20), (1.9, 0.11, 0.10), (2.4, 0.50, 0.06)]

    private static func ns(_ seconds: Double) -> UInt64 { UInt64((seconds * 1e9).rounded()) }

    private struct Snapshot: Equatable {
        var live: Int
        var spawned: Int
        var particles: [FountainParticle]
    }

    /// Replays `log` over `frames` (nanoseconds, increasing, the first is the anchor): before each frame, the
    /// onsets due by that frame are enqueued stamped with their own time; then the simulation advances. Returns a
    /// snapshot per frame time.
    private func replay(seed: UInt64 = ParticleFountainConfiguration.defaultSeed, reduceMotion: Bool = false,
                        drag: Double = ParticleFountainConfiguration.defaultDrag, log: [Onset] = ParticleFountainSimulationTests.log,
                        frames: [UInt64]) -> [UInt64: Snapshot] {
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(drag: drag, seed: seed,
                                                                                                 reduceMotion: reduceMotion))
        var next = 0
        var out: [UInt64: Snapshot] = [:]
        for frame in frames {
            while next < log.count, Self.ns(log[next].seconds) <= frame {
                XCTAssertTrue(simulation.enqueueOnset(atNanoseconds: Self.ns(log[next].seconds), strength: log[next].strength,
                                                      threshold: log[next].threshold))
                next += 1
            }
            simulation.advance(toNanoseconds: frame)
            out[frame] = Snapshot(live: simulation.liveCount, spawned: simulation.spawnedCount, particles: simulation.liveParticles)
        }
        return out
    }

    /// Frame times every `1/rate` s for `seconds` (integer nanoseconds, floor).
    private static func grid(rate: UInt64, seconds: UInt64) -> [UInt64] {
        (0...(rate * seconds)).map { (k: UInt64) -> UInt64 in k * 1_000_000_000 / rate }
    }

    /// The 30 Hz grid with 0, 1 or 2 extra frames at uneven points inside each interval.
    private static func irregular(seconds: UInt64) -> [UInt64] {
        let base = grid(rate: 30, seconds: seconds)
        var out: [UInt64] = []
        for (j, t) in base.enumerated() {
            out.append(t)
            guard j + 1 < base.count else { break }
            let gap = base[j + 1] - t
            if j % 3 >= 1 { out.append(t + gap * 3 / 10) }
            if j % 3 == 2 { out.append(t + gap * 71 / 100) }
        }
        return out
    }

    // MARK: - S1, S2: the acceptance

    func testFixedSeedAndLogReplayIsBitIdentical() {
        let frames = Self.grid(rate: 60, seconds: 4)
        let first = replay(frames: frames)
        let second = replay(frames: frames)
        var peak = 0
        for frame in frames {
            XCTAssertEqual(first[frame], second[frame], "frame at \(frame) ns")
            peak = max(peak, first[frame]?.live ?? 0)
        }
        let last = first[frames[frames.count - 1]]
        let expectedSpawned = Self.log.reduce(0) { (sum: Int, o: Onset) -> Int in
            sum + ParticleFountainConfiguration.burstSize(strength: o.strength, threshold: o.threshold, reduceMotion: false)
        }
        XCTAssertEqual(last?.spawned, expectedSpawned, "every onset of the log spawned its burst")
        XCTAssertGreaterThan(peak, 20)
        print("VIS-008 acceptance: \(Self.log.count) onsets → \(expectedSpawned) particles, peak \(peak) live; two replays identical")
    }

    func testFrameChunkingDoesNotChangeCountsOrTrajectories() {
        let sixty = replay(frames: Self.grid(rate: 60, seconds: 4))
        let thirty = replay(frames: Self.grid(rate: 30, seconds: 4))
        let uneven = replay(frames: Self.irregular(seconds: 4))
        var worst = 0.0
        var compared = 0
        for t in Self.grid(rate: 30, seconds: 4) {
            guard let a = thirty[t], let b = sixty[t], let c = uneven[t] else { return XCTFail("missing shared time \(t)") }
            XCTAssertEqual(a.live, b.live, "60 Hz count at \(t)")
            XCTAssertEqual(a.live, c.live, "irregular count at \(t)")
            XCTAssertEqual(a.spawned, b.spawned)
            XCTAssertEqual(a.spawned, c.spawned)
            guard a.live == b.live, a.live == c.live else { continue }
            for i in 0..<a.live {
                XCTAssertEqual(a.particles[i].sequence, b.particles[i].sequence)
                XCTAssertEqual(a.particles[i].sequence, c.particles[i].sequence)
                for other in [b.particles[i], c.particles[i]] {
                    worst = max(worst, abs(a.particles[i].x - other.x), abs(a.particles[i].y - other.y))
                }
                compared += 1
            }
        }
        XCTAssertLessThanOrEqual(worst, 1e-9)
        XCTAssertGreaterThan(compared, 1_000)
        print("VIS-008 chunking: \(compared) particle positions compared at 121 shared times; worst difference \(worst) R")
    }

    func testAnotherSeedKeepsCountsButChangesTrajectories() {
        let frames = Self.grid(rate: 60, seconds: 3)
        let a = replay(frames: frames)
        let b = replay(seed: 42, frames: frames)
        var differs = false
        for frame in frames {
            XCTAssertEqual(a[frame]?.spawned, b[frame]?.spawned, "the burst sizes do not depend on the seed")
            if a[frame]?.particles != b[frame]?.particles { differs = true }
        }
        XCTAssertTrue(differs)
        // The first particle's launch differs.
        let t = Self.ns(0.1)
        XCTAssertNotEqual(a[frames.first { $0 >= t }!]?.particles.first?.x, b[frames.first { $0 >= t }!]?.particles.first?.x)
    }

    // MARK: - S3: burst size

    func testBurstSizeGrowsWithStrengthWithinItsBounds() {
        var previous = 0
        for i in 0...40 {
            let s = Float(i) / 40
            let n = ParticleFountainConfiguration.burstSize(strength: s, threshold: 0.1, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(n, previous, "monotone in strength")
            XCTAssertTrue((4...24).contains(n))
            previous = n
        }
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 0.05, threshold: 0.1, reduceMotion: false), 4, "below threshold")
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 0.35, threshold: 0.1, reduceMotion: false), 24, "excess 0.25")
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 0.225, threshold: 0.1, reduceMotion: false), 14)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: .nan, threshold: 0.1, reduceMotion: false), 4)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: .infinity, threshold: 0.1, reduceMotion: false), 4)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 5, threshold: 0.1, reduceMotion: false), 24)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 5, threshold: 0.1, reduceMotion: true), 12)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 0.225, threshold: 0.1, reduceMotion: true), 7)
        XCTAssertEqual(ParticleFountainConfiguration.burstSize(strength: 0, threshold: 0.1, reduceMotion: true), 2)
    }

    // MARK: - S4: physics

    func testWithoutDragTheFixedStepFollowsTheClosedForm() {
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(drag: 0))
        simulation.advance(toNanoseconds: 0)
        simulation.enqueueOnset(atNanoseconds: 0, strength: 0.1, threshold: 0.1)
        let dt = ParticleFountainSimulation.stepSeconds
        let g = ParticleFountainConfiguration.defaultGravity
        simulation.advance(toNanoseconds: ParticleFountainSimulation.stepOffset(1))
        // After one step: v₁ = v₀ − gΔt, p₁ = v₁Δt, so v₀ = p₁/Δt + gΔt.
        let launches = simulation.liveParticles.map { (p: FountainParticle) -> (Double, Double) in (p.vx, p.y / dt + g * dt) }
        XCTAssertEqual(launches.count, 4)
        var worst = 0.0
        for n in [10, 60, 240, 480] as [UInt64] {
            simulation.advance(toNanoseconds: ParticleFountainSimulation.stepOffset(n))
            let steps = Double(n)
            for p in simulation.liveParticles {
                let (vx, vy0) = launches[p.sequence]
                let y: Double = vy0 * steps * dt - g * dt * dt * steps * (steps + 1) / 2
                worst = max(worst, abs(p.y - y), abs(p.x - vx * steps * dt), abs(p.vy - (vy0 - g * steps * dt)))
                XCTAssertEqual(p.age, steps * dt, accuracy: 1e-9)
            }
        }
        XCTAssertLessThanOrEqual(worst, 1e-9)
        for (vx, vy) in launches {
            let speed = (vx * vx + vy * vy).squareRoot()
            XCTAssertTrue((3.0 - 1e-9...4.0 + 1e-9).contains(speed), "speed \(speed)")
            XCTAssertLessThanOrEqual(abs(atan2(vx, vy)), ParticleFountainConfiguration.coneHalfAngle + 1e-9)
        }
    }

    func testWithDragARisingParticleOnlySlowsDown() {
        let simulation = ParticleFountainSimulation()
        simulation.advance(toNanoseconds: 0)
        simulation.enqueueOnset(atNanoseconds: 0, strength: 1, threshold: 0)
        var speeds = [Double](repeating: .infinity, count: 24)
        for k in 1...240 as ClosedRange<UInt64> {
            simulation.advance(toNanoseconds: ParticleFountainSimulation.stepOffset(k))
            for p in simulation.liveParticles where p.vy > 0 {
                let speed = (p.vx * p.vx + p.vy * p.vy).squareRoot()
                XCTAssertLessThan(speed, speeds[p.sequence], "particle \(p.sequence) at step \(k)")
                speeds[p.sequence] = speed
            }
        }
    }

    // MARK: - R4, R5: death and bounds

    func testParticlesDieByAgeFloorAndSidesAndTheCountStaysBounded() {
        let simulation = ParticleFountainSimulation()
        let addresses = simulation.storageAddresses
        simulation.advance(toNanoseconds: 0)
        var peak = 0
        // A full-strength onset every 50 ms (the detector's highest rate) for 10 s, 60 Hz frames, 4 onsets per frame
        // window at most, then 3 s of silence.
        var t: UInt64 = 0
        var nextOnset: UInt64 = 0
        let frame: UInt64 = 1_000_000_000 / 60
        while t < Self.ns(13) {
            t += frame
            while nextOnset <= t, nextOnset < Self.ns(10) {
                simulation.enqueueOnset(atNanoseconds: nextOnset, strength: 1, threshold: 0.06)
                nextOnset += Self.ns(0.05)
            }
            simulation.advance(toNanoseconds: t)
            peak = max(peak, simulation.liveCount)
            XCTAssertLessThanOrEqual(simulation.liveCount, ParticleFountainSimulation.capacity)
            for i in 0..<simulation.liveCount {
                let p = simulation.particle(i)
                XCTAssertTrue(p.age < p.life && p.y >= ParticleFountainConfiguration.floorHeight && abs(p.x) <= 3)
            }
        }
        XCTAssertEqual(peak, ParticleFountainSimulation.capacity, "the pool fills under the densest onsets")
        XCTAssertGreaterThan(simulation.droppedParticles, 0, "bursts that did not fit were counted")
        XCTAssertEqual(simulation.droppedOnsets, 0, "60 Hz frames never queue more than 32 onsets")
        XCTAssertEqual(simulation.liveCount, 0, "3 s after the last onset every particle is dead")
        XCTAssertEqual(simulation.spawnedCount + simulation.droppedParticles, 200 * 24)
        XCTAssertEqual(simulation.storageAddresses, addresses, "no buffer reallocated")
        // The queue bound: 40 onsets before one frame.
        let queued = ParticleFountainSimulation()
        for k in 0..<40 { queued.enqueueOnset(atNanoseconds: UInt64(k), strength: 1, threshold: 0) }
        XCTAssertEqual(queued.pendingOnsets, 32)
        XCTAssertEqual(queued.droppedOnsets, 8)
    }

    func testSideBoundKillsDriftingParticles() {
        // Weak gravity, no drag and a long life: particles near the cone's edges drift past |x| = 3, the rest land below the floor, all before their life ends.
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(gravity: 1, drag: 0, life: 10))
        simulation.advance(toNanoseconds: 0)
        simulation.enqueueOnset(atNanoseconds: 0, strength: 1, threshold: 0)
        var maxAgeAtDeath = 0.0
        var previous = simulation.liveParticles
        for k in 1...(240 * 10) as ClosedRange<UInt64> {
            simulation.advance(toNanoseconds: ParticleFountainSimulation.stepOffset(k))
            let now = Set(simulation.liveParticles.map(\.sequence))
            for p in previous where !now.contains(p.sequence) { maxAgeAtDeath = max(maxAgeAtDeath, p.age) }
            previous = simulation.liveParticles
            if simulation.liveCount == 0 && k > 1 { break }
        }
        XCTAssertEqual(simulation.liveCount, 0)
        XCTAssertLessThan(maxAgeAtDeath, 10, "every particle left the bounds before its life ended")
    }

    // MARK: - S6: Reduce Motion

    func testReduceMotionHalvesBurstsAndSlowsTheSameArc() {
        let frames = Self.grid(rate: 240, seconds: 4)
        let single: [Onset] = [(0.0, 1.0, 0.0)]
        let normal = replay(drag: 0, log: single, frames: frames)
        let reduced = replay(reduceMotion: true, drag: 0, log: single, frames: frames)
        let first = frames[1]
        XCTAssertEqual(normal[first]?.spawned, 24)
        XCTAssertEqual(reduced[first]?.spawned, 12)
        // Same seed, so the same draws: without drag vx is the launch's, exactly 0.7 times as fast.
        for i in 0..<12 {
            let a = try? XCTUnwrap(normal[first]?.particles.first { $0.sequence == i })
            let b = try? XCTUnwrap(reduced[first]?.particles.first { $0.sequence == i })
            XCTAssertEqual((b?.vx ?? 0) / (a?.vx ?? 1), 0.7, accuracy: 1e-12)
            XCTAssertEqual(b?.life ?? 0, 2.5 / 0.7, accuracy: 1e-12)
            XCTAssertEqual(b?.gravity ?? 0, 3.0 * 0.49, accuracy: 1e-12)
        }
        // With the default drag, the same arc: the highest point within 1 %.
        let dragged = replay(log: single, frames: frames)
        let draggedReduced = replay(reduceMotion: true, log: single, frames: frames)
        var apex = [Double](repeating: 0, count: 12), apexReduced = [Double](repeating: 0, count: 12)
        for frame in frames {
            for p in dragged[frame]?.particles ?? [] where p.sequence < 12 { apex[p.sequence] = max(apex[p.sequence], p.y) }
            for p in draggedReduced[frame]?.particles ?? [] { apexReduced[p.sequence] = max(apexReduced[p.sequence], p.y) }
        }
        for i in 0..<12 {
            XCTAssertGreaterThan(apex[i], 0.5)
            XCTAssertEqual(apexReduced[i] / apex[i], 1, accuracy: 0.01, "particle \(i)")
        }
    }

    // MARK: - Reset, backwards time, long gaps, configuration changes

    func testResetReplaysBackwardsTimeIsIgnoredAndLongGapsAreSkipped() {
        let simulation = ParticleFountainSimulation()
        func run() -> [FountainParticle] {
            simulation.advance(toNanoseconds: Self.ns(5))
            simulation.enqueueOnset(atNanoseconds: Self.ns(5.01), strength: 0.5, threshold: 0.1)
            simulation.advance(toNanoseconds: Self.ns(5.5))
            return simulation.liveParticles
        }
        let first = run()
        XCTAssertEqual(first.count, 24)
        simulation.reset()
        XCTAssertEqual(simulation.liveCount, 0)
        XCTAssertNil(simulation.anchorNanoseconds)
        XCTAssertEqual(run(), first, "a reset restores the seed")
        let before = simulation.liveParticles
        simulation.advance(toNanoseconds: Self.ns(5.2))
        XCTAssertEqual(simulation.liveParticles, before, "time going backwards does nothing")
        simulation.advance(toNanoseconds: Self.ns(60))
        XCTAssertEqual(simulation.skippedGaps, 1, "a 54.5 s gap runs at most 1 s of steps")
        XCTAssertEqual(simulation.anchorNanoseconds, Self.ns(60))
        XCTAssertEqual(simulation.stepIndex, 0)
        // Gravity changes apply to later bursts only.
        simulation.reset()
        simulation.advance(toNanoseconds: Self.ns(60))
        simulation.enqueueOnset(atNanoseconds: Self.ns(60), strength: 0, threshold: 0)
        simulation.advance(toNanoseconds: Self.ns(60.1))
        simulation.configuration.gravity = 4.5
        simulation.enqueueOnset(atNanoseconds: Self.ns(60.1), strength: 0, threshold: 0)
        simulation.advance(toNanoseconds: Self.ns(60.2))
        XCTAssertEqual(simulation.liveParticles.filter { $0.gravity == 3.0 }.count, 4)
        XCTAssertEqual(simulation.liveParticles.filter { $0.gravity == 4.5 }.count, 4)
        simulation.configuration.gravity = .nan
        XCTAssertEqual(simulation.configuration.gravity, 3.0, "non-finite → default")
    }

    func testSplitMix64ReferenceValues() {
        var rng = SplitMix64(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
        var unit = SplitMix64(seed: ParticleFountainConfiguration.defaultSeed)
        for _ in 0..<1_000 { XCTAssertTrue((0..<1).contains(unit.unit())) }
    }

    // MARK: - T05: layout

    func testLayoutPlacesSquaresAndFadesThem() {
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(palette: .mono))
        let layout = ParticleFountainLayout()
        let addresses = layout.storageAddresses
        layout.layout(simulation: simulation, width: 390, height: 844)
        XCTAssertEqual(layout.squareCount, 0, "silence: nothing drawn")
        simulation.advance(toNanoseconds: 0)
        simulation.enqueueOnset(atNanoseconds: 0, strength: 0.1, threshold: 0.1)
        simulation.advance(toNanoseconds: Self.ns(0.5))
        layout.layout(simulation: simulation, width: 390, height: 844)
        XCTAssertEqual(layout.squareCount, 4)
        let big = 195.0
        XCTAssertEqual(layout.sidePixels, 0.025 * big, accuracy: 1e-12)
        for k in 0..<layout.squareCount {
            let p = simulation.particle(k)
            let q = layout.quad(k)
            XCTAssertEqual((q[0] + q[2]) / 2, 195 + p.x * big, accuracy: 1e-9)
            XCTAssertEqual((q[1] + q[5]) / 2, 844 - 0.1 * big - p.y * big, accuracy: 1e-9)
            XCTAssertEqual(q[2] - q[0], layout.sidePixels, accuracy: 1e-9)
            XCTAssertEqual(Double(layout.color(k).alpha), ParticleFountainConfiguration.alpha(age: p.age, life: p.life), accuracy: 1e-6)
            XCTAssertLessThanOrEqual(layout.color(k).alpha, 0.8)
        }
        XCTAssertEqual(ParticleFountainConfiguration.alpha(age: 0, life: 2.5), 0)
        XCTAssertEqual(ParticleFountainConfiguration.alpha(age: 0.05, life: 2.5), 0.8 * (1 - 0.02), accuracy: 1e-12)
        XCTAssertEqual(ParticleFountainConfiguration.alpha(age: 2.5, life: 2.5), 0)
        var vertices = [SpectrumVertex](repeating: SpectrumVertex(), count: ParticleFountainLayout.maximumVertexCount)
        let count = vertices.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<SpectrumVertex>) -> Int in
            layout.tessellate(into: b.baseAddress!, capacity: b.count, gain: 1)
        }
        XCTAssertEqual(count, 24)
        layout.layout(simulation: simulation, width: 0, height: 100)
        XCTAssertEqual(layout.squareCount, 0, "nothing at size 0")
        layout.layout(simulation: simulation, width: 3, height: 2)
        XCTAssertEqual(layout.sidePixels, 2, "at least 2 px")
        XCTAssertTrue((0..<layout.squareCount).allSatisfy { (k: Int) -> Bool in layout.quad(k).allSatisfy(\.isFinite) })
        XCTAssertEqual(layout.storageAddresses, addresses, "no buffer reallocated")
    }

    // MARK: - T08: the bus trigger

    func testOnlyOnsetsLaunchBursts() {
        let time = AnalysisTimestamp(session: 1, sessionSample: 0, timelineSample: 0, hostNanoseconds: 0)
        func event(_ kind: AnalysisEventKind) -> AnalysisEvent { AnalysisEvent(id: 1, time: time, eventSample: 0, kind: kind) }
        let onset = ParticleFountainTrigger.onset(event(.onset(strength: 0.4, threshold: 0.1)))
        XCTAssertEqual(onset?.strength, 0.4)
        XCTAssertEqual(onset?.threshold, 0.1)
        XCTAssertNil(ParticleFountainTrigger.onset(event(.beat(bpm: 120, periodSamples: 22_050, confidence: 1))))
        XCTAssertNil(ParticleFountainTrigger.onset(event(.transient(band: .kick, strength: 6, threshold: 3, level: -10, confidence: 1))))
        XCTAssertNil(ParticleFountainTrigger.onset(event(.sessionStarted(.attached))))
    }
}
