// ReactionDiffusionModelTests.swift — VIS-012-T03 (VIS-012-R2, R5 to R9, R12; S1 to S3): the CPU model on every
// platform. Seeds are deterministic and the seed matters; stored settings decode with defaults; no frame runs more
// than 4 steps or 64 iterations at 10, 30, 60 and 120 fps; bass kicks and injections are bounded; Reduce Motion halves
// the iterations; the CPU reference keeps every value finite and within [0, 1] for every preset at Speed 16 with strong
// injections (the long run behind `VIS012_LONG=1`).
import Foundation
import VisualFluidReference
import XCTest
@testable import VisualGenerators

final class ReactionDiffusionModelTests: XCTestCase {
    private func seedCells(_ pattern: ReactionDiffusionPattern, seed: Int, n: Int = 64) -> [SIMD2<Float>] {
        var cells = [SIMD2<Float>](repeating: .zero, count: n * n)
        cells.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<SIMD2<Float>>) -> Void in
            ReactionDiffusionSeed.fill(pattern: pattern, seed: seed, gridSize: n, into: b.baseAddress!)
        }
        return cells
    }

    /// VIS-012-S1 on the CPU: same pattern and seed → the same texture; another seed moves the spots.
    func testSeedsAreDeterministicAndTheSeedMatters() {
        for pattern in ReactionDiffusionPattern.allCases {
            let a = seedCells(pattern, seed: 7)
            XCTAssertEqual(a, seedCells(pattern, seed: 7), "\(pattern)")
            let lit = a.filter { (c: SIMD2<Float>) -> Bool in c == SIMD2<Float>(0.5, 0.25) }.count
            XCTAssertGreaterThan(lit, 20, "\(pattern) seeds a region")
            XCTAssertTrue(a.allSatisfy { (c: SIMD2<Float>) -> Bool in c == SIMD2<Float>(1, 0) || c == SIMD2<Float>(0.5, 0.25) })
        }
        XCTAssertNotEqual(seedCells(.spots, seed: 1), seedCells(.spots, seed: 2), "a different seed gives different spots")
        XCTAssertNotEqual(seedCells(.square, seed: 1), seedCells(.ring, seed: 1))
    }

    func testStoredSettingsDecodeWithDefaultsAndReloadRules() {
        let s = ReactionDiffusionSettings(storedPreset: "maze", pattern: "ring", seed: 42, speed: 16)
        XCTAssertEqual(s, ReactionDiffusionSettings(preset: .maze, pattern: .ring, seed: 42, speed: 16))
        XCTAssertEqual(ReactionDiffusionSettings(storedPreset: "lava", pattern: nil, seed: 10_000, speed: 0), .default)
        XCTAssertEqual(ReactionDiffusionSettings(preset: .spots, seed: -1, speed: 17).seed, 1)
        XCTAssertEqual(ReactionDiffusionSettings(preset: .spots, seed: -1, speed: 17).speed, 8)
        XCTAssertTrue(s.reloads(from: ReactionDiffusionSettings(preset: .maze, pattern: .ring, seed: 43, speed: 16)))
        XCTAssertTrue(s.reloads(from: ReactionDiffusionSettings(preset: .coral, pattern: .ring, seed: 42, speed: 16)))
        XCTAssertFalse(s.reloads(from: ReactionDiffusionSettings(preset: .maze, pattern: .ring, seed: 42, speed: 3)), "Speed does not")
        let p = GrayScottParameters(feed: .nan, kill: 1, du: 5, dv: 0)
        XCTAssertEqual([p.feed, p.kill, p.du, p.dv], [0.01, 0.07, 1.0, 0.1])
        XCTAssertEqual(ReactionDiffusionPreset.coral.parameters, GrayScottParameters(feed: 0.0545, kill: 0.062, du: 1, dv: 0.5))
        let c = NoiseFieldConfiguration(wedges: 6, waterfall: true, fluidInk: true, reactionDiffusion: s)
        XCTAssertEqual([c.wedges, Int(c.tunnelPace)], [0, 0])
        XCTAssertFalse(c.waterfall || c.fluidInk, "reaction diffusion forces the other modes off")
    }

    /// VIS-012-S3: at most 4 steps and 64 iterations per frame; equal steps at shared times; a stall skips.
    func testIterationsPerFrameAreBounded() {
        var totals: [UInt64: UInt64] = [:]
        for fps: UInt64 in [10, 30, 60, 120] {
            let scheduler = ReactionDiffusionScheduler()
            scheduler.speed = 16
            var worst = 0
            for m: UInt64 in 0...(2 * fps) {
                scheduler.advance(toNanoseconds: 5_000_000_000 + m * 1_000_000_000 / fps)
                XCTAssertLessThanOrEqual(scheduler.plannedSteps, ReactionDiffusion.maximumStepsPerFrame)
                worst = max(worst, scheduler.plannedIterations)
            }
            XCTAssertLessThanOrEqual(worst, ReactionDiffusion.maximumIterationsPerFrame, "\(fps) fps")
            XCTAssertEqual(scheduler.totalIterations, scheduler.totalSteps * 16)
            totals[fps] = scheduler.totalSteps
            if fps == 10 { XCTAssertGreaterThan(scheduler.skippedGaps, 0, "6 steps owed per frame: the rest is skipped") }
        }
        XCTAssertEqual(totals[30], 120)
        XCTAssertEqual(totals[60], 120)
        XCTAssertEqual(totals[120], 120)
        XCTAssertEqual(ReactionDiffusion.maximumIterationsPerFrame, 64)
        XCTAssertEqual(ReactionDiffusion.iterationsPerStep(speed: 16, reduceMotion: true), 8)
        XCTAssertEqual(ReactionDiffusion.iterationsPerStep(speed: 3, reduceMotion: true), 2)
        XCTAssertEqual(ReactionDiffusion.iterationsPerStep(speed: 1, reduceMotion: true), 1)
        XCTAssertEqual(ReactionDiffusion.iterationsPerStep(speed: 99, reduceMotion: false), 16)
    }

    /// VIS-012-R8, R12: kicks need a fall below 0.4 and a rise above 0.6, spaced 0.25 s (1 s Reduce Motion); one
    /// injection per step; the queue holds 4.
    func testBassKicksAndInjectionsAreBounded() {
        for reduceMotion in [false, true] {
            let scheduler = ReactionDiffusionScheduler()
            scheduler.reduceMotion = reduceMotion
            var maxPerStep = 0
            for m: UInt64 in 0...120 {   // 2 s; bass on every other frame
                let t = 1_000_000_000 + m * 1_000_000_000 / 60
                scheduler.observeBass(m % 2 == 0 ? 1 : 0, atNanoseconds: t)
                scheduler.advance(toNanoseconds: t)
                for s in 0..<scheduler.plannedSteps { maxPerStep = max(maxPerStep, scheduler.injection(step: s) == nil ? 0 : 1) }
            }
            XCTAssertEqual(scheduler.kicks, reduceMotion ? 3 : 8, "Reduce Motion \(reduceMotion)")
            XCTAssertEqual(scheduler.appliedInjections + scheduler.pendingInjections, scheduler.kicks, "a kick applies at the next step that starts after it")
            XCTAssertEqual(maxPerStep, 1)
        }
        let scheduler = ReactionDiffusionScheduler()
        scheduler.observeBass(0.5, atNanoseconds: 0)
        XCTAssertEqual(scheduler.kicks, 0, "0.5 is not a kick")
        XCTAssertFalse(scheduler.observeBass(.nan, atNanoseconds: 1))
        for k in 0..<4 { XCTAssertTrue(scheduler.enqueue(atNanoseconds: UInt64(k), strength: 1)) }
        XCTAssertFalse(scheduler.enqueue(atNanoseconds: 9, strength: 1), "the queue holds 4")
        XCTAssertFalse(scheduler.enqueue(atNanoseconds: 9, strength: .infinity))
        let a = ReactionInjection.seeded(seed: 5, index: 3, strength: 2)
        XCTAssertEqual(a, ReactionInjection.seeded(seed: 5, index: 3, strength: 2))
        XCTAssertNotEqual(a, ReactionInjection.seeded(seed: 6, index: 3, strength: 2))
        XCTAssertEqual(a.amount, ReactionDiffusion.injectionAmount, "strength clamped to 1")
        XCTAssertTrue((0.1...0.9).contains(a.x) && (0.1...0.9).contains(a.y))
    }

    private func runReference(preset: ReactionDiffusionPreset, n: Int, iterations: Int) -> GrayScottSolver {
        let solver = GrayScottSolver(gridSize: n, parameters: preset.parameters)
        solver.seed(pattern: .spots, seed: 3)
        for k in 0..<iterations {   // a strong injection every 16 iterations (one per step at Speed 16)
            let injection: ReactionInjection? = k % 16 == 0 ? ReactionInjection.seeded(seed: 3, index: UInt64(k / 16), strength: 1) : nil
            solver.iterate(injection: injection)
            if k % 500 == 499 { XCTAssertTrue(solver.health().isHealthy, "\(preset) at \(k)") }
        }
        return solver
    }

    /// VIS-012-S2 on the reference: every preset at Speed 16 with strong injections stays finite and within [0, 1].
    func testReferenceNeverLeavesTheUnitRange() {
        let long = ProcessInfo.processInfo.environment["VIS012_LONG"] == "1"
        for preset in ReactionDiffusionPreset.allCases {
            let solver = runReference(preset: preset, n: long ? 128 : 32, iterations: long ? 20_000 : 3_000)
            XCTAssertEqual(solver.nonFiniteValues, 0, "\(preset)")
            let cells = solver.cells
            XCTAssertTrue(cells.allSatisfy { (c: SIMD2<Float>) -> Bool in
                c.x.isFinite && c.y.isFinite && (0...1).contains(c.x) && (0...1).contains(c.y)
            }, "\(preset)")
        }
    }

    /// VIS-012-R9: a corrupt value is mapped to 0 by the next iteration's guard (counted), never spread.
    func testGuardMapsANonFiniteCell() {
        let solver = GrayScottSolver(gridSize: 16)
        solver.seed(pattern: .square, seed: 1)
        solver.poke(3, 3, SIMD2<Float>(.nan, .infinity))
        XCTAssertFalse(solver.health().isHealthy)
        solver.iterate()
        XCTAssertGreaterThan(solver.nonFiniteValues, 0)
        XCTAssertTrue(solver.health().isHealthy)
    }

    /// VIS-012-R11: the bound is the brightest stop (≤ 0.8) × the fade-in ramp.
    func testBoundFollowsTheBrightestStopAndTheRamp() {
        var stops: [SIMD3<Float>] = [SIMD3(0.1, 0.2, 0.9), SIMD3(1, 0.5, 0)]
        let level = stops.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<SIMD3<Float>>) -> SIMD3<Float> in
            ReactionDiffusionBound.level(stops: b.baseAddress!, count: 2, ramp: 0.5)
        }
        XCTAssertEqual(level, SIMD3<Float>(0.4, 0.25, 0.4))
        XCTAssertEqual(ReactionDiffusion.ramp(elapsedNanoseconds: 0), 0)
        XCTAssertEqual(ReactionDiffusion.ramp(elapsedNanoseconds: 250_000_000), 0.25)
        XCTAssertEqual(ReactionDiffusion.ramp(elapsedNanoseconds: 5_000_000_000), 1)
    }
}
