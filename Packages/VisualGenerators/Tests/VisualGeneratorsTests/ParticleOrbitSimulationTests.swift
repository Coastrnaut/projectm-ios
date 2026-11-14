// ParticleOrbitSimulationTests.swift — VIS-009-T03, T05 to T07: the particle orbit on the CPU (VIS-009-R2 to R7, R9;
// S1 to S4). The acceptance: a synthetic bass timeline drives the drawn radius, which settles on the mapped value
// (within 0.01 R), never shrinks for stronger bass, stays within 0.15…0.85 R and moves at most rate·Δt per step; with a
// MOD-002 binding on `visual.particleOrbit.radius` the radius follows the binding instead. The frame budget is a work
// bound (steps, particle steps, squares, vertices, storage addresses), never a wall-clock assertion. Frames are at
// exact 60 Hz times ⌊n·10⁹/60⌋ ns; the clock is injected. Pure Swift (every platform, Linux shape included).
import ParameterGraph
import VisualParameters
import XCTest
@testable import VisualGenerators

final class ParticleOrbitSimulationTests: XCTestCase {
    private typealias C = ParticleOrbitConfiguration

    private func frameTime(_ n: Int) -> UInt64 { UInt64(n) * 1_000_000_000 / 60 }

    /// Runs `frames` 60 Hz frames from frame `start`, setting the target from `bass(n)` before each.
    private func run(_ sim: ParticleOrbitSimulation, from start: Int, frames: Int, base: Double,
                     bass: (Int) -> Double) {
        for n in start..<(start + frames) {
            sim.setTarget(base: base, bass: bass(n))
            sim.advance(toNanoseconds: frameTime(n))
        }
    }

    // MARK: - S1: the radius follows the mapped bass

    func testDrawnRadiusTracksTheMappedBassMonotonicallyAndWithinBounds() {
        let sim = ParticleOrbitSimulation()
        let layout = ParticleOrbitLayout()
        let base = 0.5
        let levels: [Double] = [0, 0.25, 0.5, 1, 0]   // 0.5 s each
        var report: [String] = []
        var frame = 0
        for level in levels {
            run(sim, from: frame, frames: 30, base: base) { (_: Int) -> Double in level }
            frame += 30
            let mapped = C.targetRadius(base: base, bass: level, depth: C.defaultDepth)
            XCTAssertEqual(mapped, base * (1 + 0.4 * level), accuracy: 1e-12)
            XCTAssertEqual(sim.radius, mapped, accuracy: 0.01, "settled on the mapped radius for bass \(level)")
            // The drawn ring: every particle sits at the drawn radius × its offset.
            layout.layout(simulation: sim, width: 390, height: 844)
            XCTAssertEqual(layout.drawnRadius, sim.radius)
            let big = 195.0
            for k in 0..<sim.count {
                let c = layout.center(k + 1)
                let d = ((c.x - 195) * (c.x - 195) + (c.y - 422) * (c.y - 422)).squareRoot()
                XCTAssertEqual(d / big / sim.offset(k), sim.radius, accuracy: 1e-9)
            }
            report.append("bass \(level): mapped \(mapped), drawn \(sim.radius)")
        }
        print("VIS-009 radius tracking: " + report.joined(separator: "; "))

        // Monotonic: stronger steady bass never gives a smaller radius, at any frame or when settled.
        var settled: [Double] = []
        for i in 0...10 {
            let level = Double(i) / 10
            let a = ParticleOrbitSimulation()
            run(a, from: 0, frames: 30, base: base) { (_: Int) -> Double in level }
            settled.append(a.radius)
        }
        XCTAssertEqual(settled, settled.sorted(), "settled radius is monotone in the bass")
        let weak = ParticleOrbitSimulation(), strong = ParticleOrbitSimulation()
        for n in 0..<60 {
            run(weak, from: n, frames: 1, base: base) { (_: Int) -> Double in 0.3 }
            run(strong, from: n, frames: 1, base: base) { (_: Int) -> Double in 0.6 }
            XCTAssertLessThanOrEqual(weak.radius, strong.radius)
        }
    }

    func testRadiusStaysBoundedAndRateLimitedForAnyInput() {
        let inputs: [Double] = [5, -1, .nan, .infinity, -.infinity, 1, 0]
        for base in [C.radiusRange.lowerBound, C.radiusRange.upperBound] {
            for reduce in [false, true] {
                let sim = ParticleOrbitSimulation(configuration: C(reduceMotion: reduce))
                let limit = (reduce ? C.reducedRadiusRate : C.radiusRate) / 240 + 1e-12
                sim.advance(toNanoseconds: 0)
                var step: UInt64 = 0
                for input in inputs {
                    sim.setTarget(base: base, bass: input)
                    for _ in 0..<60 {   // one fixed step per advance: every step is observed
                        let before = sim.radius
                        step += 1
                        sim.advance(toNanoseconds: step * 1_000_000_000 / 240)
                        XCTAssertTrue((C.minimumRadius...C.maximumRadius).contains(sim.radius), "\(sim.radius)")
                        XCTAssertLessThanOrEqual(abs(sim.radius - before), limit)
                    }
                }
                XCTAssertEqual(sim.stepsRun, inputs.count * 60)
            }
        }
        XCTAssertEqual(C.targetRadius(base: 0.8, bass: 1, depth: 1), C.maximumRadius)
        XCTAssertEqual(C.targetRadius(base: .nan, bass: .nan, depth: .nan), 0.5)
        // The largest ring stays inside the output: 0.85 × 1.1 < 1.
        XCTAssertLessThan(C.maximumRadius * (1 + C.offsetSpread), 1)
    }

    // MARK: - S2: mapped bass through a MOD-002 binding

    func testABindingOnTheRadiusParameterReplacesTheBuiltInBass() throws {
        let modulator = AudioFeatureModulator(registry: try VisualParameterCatalog.makeRegistry())
        XCTAssertTrue(ParticleOrbitRadiusDrive.resolve(manual: 0.35, kick: 0.7, modulator: modulator) == (0.35, 0.7),
                      "unbound: the setting and the kick")
        XCTAssertTrue(ParticleOrbitRadiusDrive.resolve(manual: 0.35, kick: 0.7, modulator: nil) == (0.35, 0.7))
        try modulator.bind(AudioFeatureBinding(source: .kick, target: VisualParameterIDs.particleOrbitRadius,
                                               outputStart: 0.3, outputEnd: 0.7))
        let sim = ParticleOrbitSimulation()
        let bands = [Float](repeating: 0, count: 16)
        var frame = 0
        for kick in [0.0, 0.5, 1.0, 0.25] {
            for _ in 0..<30 {
                let t = frameTime(frame)
                bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                    modulator.advance(frame: AudioFeatureFrame(bands: b, kick: Float(kick)), timeNanoseconds: t)
                }
                let drive = ParticleOrbitRadiusDrive.resolve(manual: 0.5, kick: kick, modulator: modulator)
                XCTAssertEqual(drive.bass, 0, "bound: the built-in bass is off")
                sim.setTarget(base: drive.base, bass: drive.bass)
                sim.advance(toNanoseconds: t)
                frame += 1
            }
            XCTAssertEqual(sim.radius, 0.3 + 0.4 * kick, accuracy: 0.01, "follows the binding for kick \(kick)")
        }
    }

    // MARK: - S3: the frame budget as a work bound

    func testMaximumOrbitStaysWithinTheWorkBoundWithoutAllocating() {
        let sim = ParticleOrbitSimulation(configuration: C(particleCount: 256))
        let layout = ParticleOrbitLayout()
        let vertices = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: ParticleOrbitLayout.maximumVertexCount)
        defer { vertices.deallocate() }
        let simAddresses = sim.storageAddresses, layoutAddresses = layout.storageAddresses
        var worstSteps = 0, worstParticleSteps = 0, worstVertices = 0
        for n in 0..<600 {
            let steps0 = sim.stepsRun, work0 = sim.particleSteps
            if n % 30 == 0 { sim.enqueueBeat(atNanoseconds: frameTime(n)) }
            sim.setTarget(base: 0.5, bass: Double(n % 20) / 20)
            sim.advance(toNanoseconds: frameTime(n))
            layout.layout(simulation: sim, width: 1179, height: 2556)
            let v = layout.tessellate(into: vertices, capacity: ParticleOrbitLayout.maximumVertexCount, gain: 1)
            worstSteps = max(worstSteps, sim.stepsRun - steps0)
            worstParticleSteps = max(worstParticleSteps, sim.particleSteps - work0)
            worstVertices = max(worstVertices, v)
            XCTAssertLessThanOrEqual(layout.squareCount, 257)
            if n > 0 { XCTAssertEqual(sim.stepsRun - steps0, 4, "exactly 4 fixed steps per 60 Hz frame") }
        }
        XCTAssertEqual(worstSteps, 4)
        XCTAssertLessThanOrEqual(worstParticleSteps, 1_024)
        XCTAssertEqual(worstVertices, 1_542)
        XCTAssertLessThanOrEqual(worstVertices, ParticleOrbitLayout.maximumVertexCount)
        XCTAssertEqual(sim.storageAddresses, simAddresses, "no storage reallocated")
        XCTAssertEqual(layout.storageAddresses, layoutAddresses)
        print("VIS-009 work bound (256 particles, 600 frames at 60 Hz): ≤ \(worstSteps) steps, ≤ \(worstParticleSteps) particle steps, ≤ \(worstVertices) vertices per frame")
    }

    /// A baseline for the record (reported by XCTest, never asserted): 60 frames of the largest orbit.
    func testWorkBaselineMetricIsReportedNotAsserted() {
        let sim = ParticleOrbitSimulation(configuration: C(particleCount: 256))
        let layout = ParticleOrbitLayout()
        let vertices = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: ParticleOrbitLayout.maximumVertexCount)
        defer { vertices.deallocate() }
        var n = 0
        measure {
            for _ in 0..<60 {
                sim.setTarget(base: 0.5, bass: 0.5)
                sim.advance(toNanoseconds: frameTime(n))
                layout.layout(simulation: sim, width: 1179, height: 2556)
                _ = layout.tessellate(into: vertices, capacity: ParticleOrbitLayout.maximumVertexCount, gain: 1)
                n += 1
            }
        }
    }

    // MARK: - S4: determinism

    private func replay(seed: UInt64) -> ParticleOrbitSimulation {
        let sim = ParticleOrbitSimulation(configuration: C(seed: seed))
        for n in 0..<120 {
            if n % 25 == 3 { sim.enqueueBeat(atNanoseconds: frameTime(n) - 1_000_000) }
            sim.setTarget(base: 0.5, bass: Double((n * 7) % 11) / 10)
            sim.advance(toNanoseconds: frameTime(n))
        }
        return sim
    }

    func testSameSeedAndTimelineAreBitIdenticalAndAnotherSeedDiffers() {
        let a = replay(seed: C.defaultSeed), b = replay(seed: C.defaultSeed), c = replay(seed: 42)
        XCTAssertEqual(a.radius.bitPattern, b.radius.bitPattern)
        XCTAssertEqual(a.pulse.bitPattern, b.pulse.bitPattern)
        XCTAssertEqual(a.beatsApplied, 5)
        for k in 0..<a.count {
            XCTAssertEqual(a.phase(k).bitPattern, b.phase(k).bitPattern)
            XCTAssertEqual(a.offset(k).bitPattern, b.offset(k).bitPattern)
        }
        XCTAssertEqual(a.radius, c.radius, "the radius depends on the timeline, not the seed")
        XCTAssertTrue((0..<a.count).contains { a.phase($0) != c.phase($0) }, "another seed places particles elsewhere")
        // Reset replays the same sequence.
        a.reset()
        let d = replay(seed: C.defaultSeed)
        for n in 0..<120 {
            if n % 25 == 3 { a.enqueueBeat(atNanoseconds: frameTime(n) - 1_000_000) }
            a.setTarget(base: 0.5, bass: Double((n * 7) % 11) / 10)
            a.advance(toNanoseconds: frameTime(n))
        }
        XCTAssertEqual(a.radius.bitPattern, d.radius.bitPattern)
        XCTAssertEqual(a.phase(17).bitPattern, d.phase(17).bitPattern)
        // Changing the particle count keeps every slot's draws.
        let small = ParticleOrbitSimulation(configuration: C(particleCount: 16))
        let large = ParticleOrbitSimulation(configuration: C(particleCount: 256))
        XCTAssertEqual(small.phase(5), large.phase(5))
        XCTAssertEqual(small.offset(15), large.offset(15))
    }

    // MARK: - R5, R9: beats, Reduce Motion, edges

    func testBeatsPulseTheCentreAndDecayWithABoundedQueue() {
        let sim = ParticleOrbitSimulation()
        let layout = ParticleOrbitLayout()
        sim.advance(toNanoseconds: 0)
        layout.layout(simulation: sim, width: 200, height: 100)
        let rest = layout.side(0)
        XCTAssertEqual(rest, C.coreSize * 50, accuracy: 1e-9)
        XCTAssertTrue(sim.enqueueBeat(atNanoseconds: 0))
        sim.advance(toNanoseconds: frameTime(1))   // 4 steps: the pulse is set on the first, then decays 4 times
        XCTAssertEqual(sim.pulse, exp(-4.0 / 240 / C.pulseTimeConstant), accuracy: 1e-9)
        layout.layout(simulation: sim, width: 200, height: 100)
        XCTAssertGreaterThan(layout.side(0), rest)
        XCTAssertLessThanOrEqual(layout.side(0), rest * (1 + C.pulseAmplitude) + 1e-9)
        sim.advance(toNanoseconds: frameTime(1) + 200_000_000)
        XCTAssertEqual(sim.pulse, exp(-52.0 / 240 / C.pulseTimeConstant), accuracy: 1e-9)
        for i in 0..<20 { sim.enqueueBeat(atNanoseconds: frameTime(100) + UInt64(i)) }
        XCTAssertEqual(sim.pendingBeats, 16)
        XCTAssertEqual(sim.droppedBeats, 4)
        // Alphas are below ACC-012's cap.
        for k in 0..<layout.squareCount { XCTAssertLessThanOrEqual(layout.color(k).alpha, 0.8) }
    }

    func testReduceMotionHalvesTheTurnAndShrinksThePulse() {
        let normal = ParticleOrbitSimulation(), reduced = ParticleOrbitSimulation(configuration: C(reduceMotion: true))
        for sim in [normal, reduced] {
            sim.advance(toNanoseconds: 0)
            sim.enqueueBeat(atNanoseconds: 0)
            sim.advance(toNanoseconds: frameTime(1))
        }
        for k in 0..<8 {
            let start = ParticleOrbitSimulation().phase(k)
            var dn = normal.phase(k) - start, dr = reduced.phase(k) - start
            if dn < 0 { dn += 2 * .pi }
            if dr < 0 { dr += 2 * .pi }
            XCTAssertEqual(dr / dn, 0.5, accuracy: 1e-9)
        }
        let a = ParticleOrbitLayout(), b = ParticleOrbitLayout()
        a.layout(simulation: normal, width: 100, height: 100)
        b.layout(simulation: reduced, width: 100, height: 100)
        XCTAssertLessThan(b.side(0), a.side(0), "a gentler pulse")
        // Reduce Motion applied in place slows the response too.
        XCTAssertEqual(reduced.configuration.effectiveRadiusTimeConstant, C.reducedRadiusTimeConstant)
    }

    func testResetGapsBackwardsTimeAndSizes() {
        let sim = ParticleOrbitSimulation()
        sim.setTarget(base: 0.5, bass: 1)
        sim.advance(toNanoseconds: 10_000_000_000)
        sim.advance(toNanoseconds: 9_000_000_000)   // backwards: nothing
        XCTAssertEqual(sim.stepsRun, 0)
        sim.advance(toNanoseconds: 15_000_000_000)   // a 5 s gap: at most 240 steps, the rest skipped
        XCTAssertEqual(sim.stepsRun, 240)
        XCTAssertEqual(sim.skippedGaps, 1)
        XCTAssertEqual(sim.radius, 0.7, accuracy: 0.01)
        sim.reset()
        XCTAssertEqual(sim.radius, 0.5)
        XCTAssertEqual(sim.pulse, 0)
        XCTAssertNil(sim.anchorNanoseconds)
        XCTAssertEqual(sim.particleSteps, 0)
        let layout = ParticleOrbitLayout()
        layout.layout(simulation: sim, width: 0, height: 100)
        XCTAssertEqual(layout.squareCount, 0, "nothing at size 0")
        layout.layout(simulation: sim, width: 3, height: 2)
        XCTAssertEqual(layout.squareCount, sim.count + 1)
        XCTAssertGreaterThanOrEqual(layout.side(1), C.minimumSidePixels)
        XCTAssertGreaterThanOrEqual(layout.side(0), C.minimumSidePixels)
        // Configuration clamps.
        let wild = C(particleCount: 9_999, radius: .nan, bassDepth: -3, angularSpeed: .infinity, particleSize: 9)
        XCTAssertEqual(wild.particleCount, 256)
        XCTAssertEqual(wild.radius, C.defaultRadius)
        XCTAssertEqual(wild.bassDepth, 0)
        XCTAssertEqual(wild.angularSpeed, C.defaultSpeed)
        XCTAssertEqual(wild.particleSize, 0.1)
    }
}
