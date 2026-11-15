// FluidInkSolverTests.swift — VIS-011-T03: the CPU half of the acceptance (VIS-011-R2 to R7, S1, S2). A maximum-strength
// impulse every frame for 60 simulated seconds keeps the reference solver finite, within its caps and with bounded,
// non-growing kinetic energy; 30 and 120 fps frame clocks give bit-identical states at shared times; the scheduler's
// caps, the impulse mapping, the non-finite reset and the ink bound. Pure Swift: runs on Linux too. Clocks are injected
// (frame counts × integer nanoseconds). `VIS011_LONG=1` adds a 5-minute run and Reduce Motion at 120 fps.
import Foundation
import XCTest
@testable import VisualGenerators
import VisualFluidReference

/// Drives a scheduler and a reference solver with an injected frame clock (tests).
final class FluidInkCPUDriver {
    let scheduler = FluidStepScheduler()
    let solver: FluidInkSolver
    var bound = FluidInkBound()
    private(set) var energies: [Float] = []
    private(set) var worst = FluidInkHealth()
    let start: UInt64 = 1_000_000_000

    init(gridSize: Int = 32, reduceMotion: Bool = false) {
        solver = FluidInkSolver(gridSize: gridSize)
        scheduler.reduceMotion = reduceMotion
        for k in 0..<FluidStepScheduler.paletteCount {
            let t = Float(k) / 15
            scheduler.palette[k] = SIMD3<Float>(1 - t, 0.5, t)
        }
    }

    /// The time of frame `m` at `fps` (exact integer arithmetic, as the shared-time test needs).
    func time(frame m: UInt64, fps: UInt64) -> UInt64 { start + m * 1_000_000_000 / fps }

    /// Runs frame `m`; `impulse` enqueues a maximum-strength onset at the frame's time first.
    func frame(_ m: UInt64, fps: UInt64, impulse: Bool, recordHealthEvery: Int = 0) {
        let t = time(frame: m, fps: fps)
        if impulse { scheduler.enqueue(atNanoseconds: t, strength: 1, threshold: 0) }
        let steps = scheduler.advance(toNanoseconds: t)
        let speedCap = FluidInk.effectiveSpeedCap(reduceMotion: scheduler.reduceMotion)
        for s in 0..<steps {
            var splats: [FluidSplat] = []
            var sum = SIMD3<Float>(0, 0, 0)
            for k in 0..<scheduler.splatCount(step: s) {
                let splat = scheduler.splat(step: s, k)
                splats.append(splat)
                sum += SIMD3<Float>(splat.red, splat.green, splat.blue)
            }
            solver.step(splats: splats, speedCap: speedCap)
            bound.step(splatSum: sum)
            if recordHealthEvery > 0, solver.steps % recordHealthEvery == 0 { record() }
        }
    }

    func record() {
        let h = solver.health
        energies.append(h.kineticEnergy)
        worst.maxSpeed = max(worst.maxSpeed, h.maxSpeed)
        worst.maxInk = max(worst.maxInk, h.maxInk)
        worst.kineticEnergy = max(worst.kineticEnergy, h.kineticEnergy)
        worst.nonFinite = worst.nonFinite || h.nonFinite
    }
}

final class FluidInkSolverTests: XCTestCase {
    /// The acceptance on the reference solver: 60 s at 60 fps, a maximum-strength impulse every frame.
    func testRepeatedStrongImpulsesStayFiniteBoundedAndDoNotGrow() {
        assertStable(seconds: 60, fps: 60, reduceMotion: false)
    }

    func testLongRunsAndReduceMotionStayStable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VIS011_LONG"] == "1", "on-demand sweep (VIS011_LONG=1)")
        assertStable(seconds: 300, fps: 60, reduceMotion: false)
        assertStable(seconds: 60, fps: 120, reduceMotion: true)
    }

    private func assertStable(seconds: UInt64, fps: UInt64, reduceMotion: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let driver = FluidInkCPUDriver(reduceMotion: reduceMotion)
        for m in 0...(seconds * fps) { driver.frame(m, fps: fps, impulse: true, recordHealthEvery: 6) }
        let cap = FluidInk.effectiveSpeedCap(reduceMotion: reduceMotion)
        let w = driver.worst
        XCTAssertFalse(w.nonFinite, file: file, line: line)
        XCTAssertEqual(driver.solver.nonFiniteResets, 0, "the guard never had to act", file: file, line: line)
        XCTAssertLessThanOrEqual(w.maxSpeed, cap * 1.0001, file: file, line: line)
        XCTAssertLessThanOrEqual(w.maxInk, FluidInk.inkCap, file: file, line: line)
        XCTAssertGreaterThan(w.maxInk, 0.3, "the impulses did inject ink", file: file, line: line)
        XCTAssertGreaterThan(w.kineticEnergy, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(w.kineticEnergy, FluidInkHealth.energyBound(speedCap: cap), file: file, line: line)
        // Not growing: the last 10 s mean is at most 1.25 × the 10 s before (records every 6 steps = 10 per second).
        let e = driver.energies
        XCTAssertGreaterThanOrEqual(e.count, 200, file: file, line: line)
        let last = e.suffix(100).reduce(0, +) / 100
        let before = e.dropLast(100).suffix(100).reduce(0, +) / 100
        XCTAssertLessThanOrEqual(last, 1.25 * before, "energy \(before) → \(last)", file: file, line: line)
        XCTAssertLessThanOrEqual(driver.bound.level.max(), FluidInk.inkCap, file: file, line: line)
    }

    /// VIS-011-S2: 30 fps and 120 fps frame clocks, the same impulses at shared times → bit-identical states.
    func testThirtyAndOneHundredTwentyFramesPerSecondMatchAtSharedTimes() {
        let slow = FluidInkCPUDriver(), fast = FluidInkCPUDriver()
        for m: UInt64 in 0...60 {   // 2 s
            slow.frame(m, fps: 30, impulse: m % 3 == 0)
            for q: UInt64 in (m == 0 ? 0 : 4 * m - 3)...(4 * m) {
                fast.frame(q, fps: 120, impulse: q == 4 * m && m % 3 == 0)
            }
            XCTAssertEqual(slow.solver.steps, fast.solver.steps)
            if m % 15 == 0 {
                for j in stride(from: 0, to: 32, by: 3) {
                    for i in stride(from: 0, to: 32, by: 3) {
                        XCTAssertEqual(slow.solver.velocity(i, j), fast.solver.velocity(i, j))
                        XCTAssertEqual(slow.solver.inkColor(i, j), fast.solver.inkColor(i, j))
                    }
                }
            }
        }
        XCTAssertEqual(slow.solver.steps, 120)
        XCTAssertEqual(slow.scheduler.appliedImpulses, fast.scheduler.appliedImpulses)
        XCTAssertGreaterThan(slow.solver.health.maxInk, 0.05)
    }

    func testImpulseMappingIgnoresInvalidOnsets() {
        XCTAssertEqual(FluidImpulse.strength(onset: 0.2, threshold: 0.3), 0.4, "below threshold: the floor")
        XCTAssertEqual(FluidImpulse.strength(onset: 0.55, threshold: 0.3) ?? 0, 0.7, accuracy: 1e-6)
        XCTAssertEqual(FluidImpulse.strength(onset: 9, threshold: 0), 1, "clamped")
        XCTAssertNil(FluidImpulse.strength(onset: .nan, threshold: 0.3))
        XCTAssertNil(FluidImpulse.strength(onset: 0.5, threshold: .infinity))
        let s = FluidStepScheduler()
        XCTAssertFalse(s.enqueue(atNanoseconds: 0, strength: .nan, threshold: 0))
        XCTAssertEqual(s.pendingImpulses, 0)
    }

    func testSchedulerCapsStepsImpulsesQueueAndSkipsStalls() {
        let s = FluidStepScheduler()
        XCTAssertEqual(s.advance(toNanoseconds: 1_000), 0, "the first call anchors")
        XCTAssertEqual(s.advance(toNanoseconds: 500), 0, "time backwards: nothing")
        for _ in 0..<20 { s.enqueue(atNanoseconds: 1_000, strength: 1, threshold: 0) }
        XCTAssertEqual(s.pendingImpulses, FluidInk.queueCapacity)
        XCTAssertEqual(s.droppedImpulses, 4, "a full queue refuses")
        XCTAssertEqual(s.advance(toNanoseconds: 1_000 + FluidInk.stepOffset(1)), 1)
        XCTAssertEqual(s.splatCount(step: 0), 2, "two impulses per step")
        let a = s.splat(step: 0, 0), b = s.splat(step: 0, 1)
        let speedA = (a.velocityX * a.velocityX + a.velocityY * a.velocityY).squareRoot()
        let speedB = (b.velocityX * b.velocityX + b.velocityY * b.velocityY).squareRoot()
        XCTAssertEqual(speedA, FluidInk.splatSpeed, accuracy: 1e-5)
        XCTAssertEqual(speedB, 0.5 * FluidInk.splatSpeed, accuracy: 1e-5, "the 1.5 strength budget scales the second")
        XCTAssertEqual(s.pendingImpulses, 0)
        XCTAssertEqual(s.droppedImpulses, 4 + 14)
        XCTAssertEqual(s.advance(toNanoseconds: 1_000 + FluidInk.stepOffset(30)), FluidInk.maximumStepsPerFrame, "spiral-of-death guard")
        XCTAssertEqual(s.skippedGaps, 1, "the rest of the gap is skipped")
        XCTAssertEqual(s.advance(toNanoseconds: 1_000 + FluidInk.stepOffset(30) + FluidInk.stepOffset(1)), 1, "re-anchored")
    }

    func testReduceMotionSpacesImpulsesAndSlowsThem() {
        let s = FluidStepScheduler()
        s.reduceMotion = true
        s.advance(toNanoseconds: 0)
        for m: UInt64 in 1...60 {
            s.enqueue(atNanoseconds: FluidInk.stepOffset(m - 1), strength: 1, threshold: 0)
            let steps = s.advance(toNanoseconds: FluidInk.stepOffset(m))
            for k in 0..<steps where s.splatCount(step: k) > 0 {
                let v = s.splat(step: k, 0)
                XCTAssertEqual((v.velocityX * v.velocityX + v.velocityY * v.velocityY).squareRoot(),
                               FluidInk.splatSpeed * FluidInk.reduceMotionScale, accuracy: 1e-5)
            }
        }
        XCTAssertEqual(s.appliedImpulses, 2, "one per 0.5 s in 1 s")
        XCTAssertEqual(FluidInk.effectiveSpeedCap(reduceMotion: true), 0.5 * FluidInk.speedCap)
    }

    func testNonFiniteValueIsClearedAndHealthFlagsReset() {
        let driver = FluidInkCPUDriver(gridSize: 16)
        for m: UInt64 in 0...10 { driver.frame(m, fps: 60, impulse: true) }
        XCTAssertGreaterThan(driver.solver.health.maxInk, 0)
        driver.solver.corruptForTesting(.nan)
        driver.frame(11, fps: 60, impulse: false)
        XCTAssertEqual(driver.solver.nonFiniteResets, 0, "every pass maps a non-finite value to 0: nothing spreads")
        XCTAssertFalse(driver.solver.health.nonFinite)
        let health = FluidInkHealth(maxSpeed: 0.1, maxInk: 0.2, kineticEnergy: 0.01, nonFinite: true)
        XCTAssertTrue(health.needsReset(speedCap: FluidInk.speedCap), "a flag from the GPU readback resets")
        XCTAssertTrue(FluidInkHealth(maxSpeed: 0.5, maxInk: 0, kineticEnergy: 0).needsReset(speedCap: FluidInk.speedCap))
        XCTAssertTrue(FluidInkHealth(maxSpeed: 0, maxInk: .nan, kineticEnergy: 0).needsReset(speedCap: FluidInk.speedCap))
        XCTAssertFalse(FluidInkHealth(maxSpeed: 0.45, maxInk: 0.8, kineticEnergy: 0.05).needsReset(speedCap: FluidInk.speedCap))
    }

    /// VIS-011-R10: the bound is never below the solver's largest ink, and it reaches 0 in silence.
    func testInkBoundIsAnUpperBound() {
        let driver = FluidInkCPUDriver(gridSize: 16)
        for m: UInt64 in 0...240 {
            driver.frame(m, fps: 60, impulse: m < 90 && m % 7 == 0)
            let h = driver.solver.health
            XCTAssertGreaterThanOrEqual(driver.bound.level.max() + 1e-6, h.maxInk, "frame \(m)")
        }
        var bound = FluidInkBound()
        bound.step(splatSum: SIMD3<Float>(5, 5, 5))
        XCTAssertLessThanOrEqual(bound.level.max(), FluidInk.inkCap)
        for _ in 0..<4000 { bound.step(splatSum: .zero) }
        XCTAssertLessThan(bound.level.max(), 1e-6)
    }

    func testSeededSplatsReplayAndStayInside() {
        let palette = UnsafeMutablePointer<SIMD3<Float>>.allocate(capacity: 16)
        defer { palette.deallocate() }
        palette.initialize(repeating: SIMD3<Float>(1, 1, 1), count: 16)
        for index: UInt64 in 0..<50 {
            let a = FluidSplat.seeded(index: index, strength: 1, reduceMotion: false, palette: palette, paletteCount: 16)
            XCTAssertEqual(a, FluidSplat.seeded(index: index, strength: 1, reduceMotion: false, palette: palette, paletteCount: 16))
            XCTAssertTrue((0.15...0.85).contains(a.centerX) && (0.15...0.85).contains(a.centerY))
            XCTAssertEqual(a.red, FluidInk.splatInk, accuracy: 1e-6)
        }
    }
}
