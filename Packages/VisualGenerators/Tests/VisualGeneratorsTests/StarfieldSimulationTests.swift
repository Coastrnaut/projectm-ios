// StarfieldSimulationTests.swift — VIS-016-T03: the starfield's acceptance on the CPU (VIS-016-R2 to R4, R6; S1, S2).
// "Density limit is enforced": 5000 requested gives exactly 2000 active, never more over a run, and the pool's storage
// never moves or grows. "Deterministic reset reproduces star positions": after a run, reset restores every star bit for
// bit; 60 Hz and jittery frame times agree bit for bit at shared times; another seed differs. Clocks are injected; no
// wall-clock assertion. Pure Swift (every platform, Linux shape included).
import XCTest
@testable import VisualGenerators

final class StarfieldSimulationTests: XCTestCase {
    private typealias C = StarfieldConfiguration

    private func frameTime(_ n: Int) -> UInt64 { UInt64(n) * 1_000_000_000 / 60 }

    /// Bit patterns of every star, so equality is bit for bit (no tolerance, -0.0 ≠ 0.0).
    private func bits(_ sim: StarfieldSimulation) -> [UInt64] {
        sim.allStars.flatMap { (s: Star) -> [UInt64] in [s.x.bitPattern, s.y.bitPattern, s.z.bitPattern] }
    }

    // MARK: - S1: the density limit

    func testDensityAboveTheCapGivesExactlyTheCapAndNeverMore() {
        XCTAssertEqual(C.activeCount(requested: 5000), 2000)
        XCTAssertEqual(C.activeCount(requested: 2000), 2000)
        XCTAssertEqual(C.activeCount(requested: 600), 600)
        XCTAssertEqual(C.activeCount(requested: 0), 1)
        XCTAssertEqual(C.activeCount(requested: Int.max), 2000)
        XCTAssertEqual(C.activeCount(requested: Int.min), 1)
        let sim = StarfieldSimulation(configuration: C(density: 5000, speed: .fast))
        XCTAssertEqual(sim.configuration.density, 2000, "stored clamped")
        XCTAssertEqual(sim.activeCount, 2000)
        let layout = StarfieldLayout()
        let address = sim.storageAddress
        var maxActive = 0, maxDrawn = 0
        for n in 0...300 {   // 5 s at 60 Hz, full bass every other second
            if n == 150 { sim.configuration.density = 9999 }   // a second request above the cap mid-run
            sim.setBass((n / 60) % 2 == 0 ? 1 : 0)
            sim.advance(toNanoseconds: frameTime(n))
            if n % 30 == 0 { layout.layout(simulation: sim, width: 390, height: 844) }
            maxActive = max(maxActive, sim.activeCount)
            maxDrawn = max(maxDrawn, layout.squareCount)
        }
        XCTAssertEqual(maxActive, 2000)
        XCTAssertLessThanOrEqual(maxDrawn, 2000)
        XCTAssertGreaterThan(maxDrawn, 500, "most of the field is drawn")
        XCTAssertEqual(sim.storageAddress, address, "the pool never moves or grows")
        XCTAssertEqual(sim.allStars.count, StarfieldSimulation.capacity)
        XCTAssertGreaterThan(sim.respawnCount, 0, "stars passed the viewer and respawned")
        // Density below the cap draws only the first stars, and a change does not move any star.
        let before = bits(sim)
        sim.configuration.density = 300
        XCTAssertEqual(bits(sim), before)
        layout.layout(simulation: sim, width: 390, height: 844)
        XCTAssertLessThanOrEqual(layout.squareCount, 300)
        XCTAssertTrue((0..<layout.squareCount).allSatisfy { (k: Int) -> Bool in layout.starIndex(k) < 300 })
    }

    // MARK: - S2: deterministic reset

    func testResetRestoresTheInitialPositionsBitForBit() {
        let sim = StarfieldSimulation(configuration: C(speed: .fast))
        let initial = bits(sim)
        XCTAssertEqual(initial, bits(StarfieldSimulation(configuration: C(speed: .slow, reduceMotion: true))),
                       "the initial positions depend only on the seed")
        for n in 0...120 {
            sim.setBass(0.7)
            sim.advance(toNanoseconds: 5_000_000_000 + frameTime(n))   // the frame clock need not start at 0
        }
        XCTAssertEqual(sim.stepsRun, 480)
        XCTAssertNotEqual(bits(sim), initial)
        sim.reset()
        XCTAssertEqual(bits(sim), initial, "reset reproduces every star bit for bit")
        XCTAssertNil(sim.anchorNanoseconds)
        XCTAssertEqual(sim.bass, 0)
        // A seed change resets too (to the new seed's positions), and the old seed comes back exactly.
        sim.advance(toNanoseconds: 0); sim.advance(toNanoseconds: frameTime(30))
        sim.configuration.seed = 42
        let other = bits(sim)
        XCTAssertNotEqual(other, initial, "a different seed gives different positions")
        XCTAssertEqual(other, bits(StarfieldSimulation(configuration: C(seed: 42))))
        sim.configuration.seed = C.defaultSeed
        XCTAssertEqual(bits(sim), initial)
    }

    func testSixtyHertzAndJitteryFramesAgreeBitForBitAtSharedTimes() {
        let steady = StarfieldSimulation(configuration: C(speed: .fast))
        let jittery = StarfieldSimulation(configuration: C(speed: .fast))
        let otherSeed = StarfieldSimulation(configuration: C(speed: .fast, seed: 7))
        var rng = SplitMix64(seed: 99)
        var jitterTime: UInt64 = 0
        steady.advance(toNanoseconds: 0); jittery.advance(toNanoseconds: 0); otherSeed.advance(toNanoseconds: 0)
        for second in 1...3 {   // shared times: every 0.5 s
            for half in 0..<2 {
                let shared = UInt64(second - 1) * 1_000_000_000 + UInt64(half + 1) * 500_000_000
                for n in 1...30 {   // 60 Hz up to the shared time
                    steady.advance(toNanoseconds: shared - 500_000_000 + frameTime(n))
                }
                while true {   // 4…40 ms frames, then exactly the shared time
                    let next = jitterTime + 4_000_000 + rng.next() % 36_000_000
                    guard next < shared else { break }
                    jittery.advance(toNanoseconds: next)
                    jitterTime = next
                }
                jittery.advance(toNanoseconds: shared)
                jitterTime = shared
                otherSeed.advance(toNanoseconds: shared)
                XCTAssertEqual(steady.stepsRun, jittery.stepsRun)
                XCTAssertEqual(bits(steady), bits(jittery), "identical at \(shared) ns")
                XCTAssertNotEqual(bits(otherSeed), bits(steady), "another seed differs at \(shared) ns")
            }
        }
        XCTAssertEqual(steady.stepsRun, 720)
    }

    // MARK: - Flight, respawn, speed

    func testStarsApproachAtTheSetSpeedAndRespawnAtTheFarPlane() {
        let sim = StarfieldSimulation(configuration: C(speed: .medium))
        sim.advance(toNanoseconds: 0)
        let before = sim.allStars
        sim.advance(toNanoseconds: frameTime(6))   // 0.1 s = 24 steps
        let dz = 24 * 0.2 * StarfieldSimulation.stepSeconds
        var respawned = 0
        for (i, s) in before.enumerated() {
            let now = sim.star(i)
            if s.z - dz >= C.near {
                XCTAssertEqual(now.z, s.z - dz, accuracy: 1e-12)
                XCTAssertEqual(now.x, s.x)
            } else {
                respawned += 1
                XCTAssertGreaterThan(now.z, C.far - dz - 1e-12, "back at the far plane")
                XCTAssertLessThanOrEqual(abs(now.x), C.lateralSpread)
            }
            XCTAssertTrue(now.z >= C.near && now.z <= C.far, "depth in range")
        }
        XCTAssertEqual(respawned, sim.respawnCount)
        // Speeds: the three choices, the bass boost and its cap, Reduce Motion half, never NaN.
        XCTAssertEqual(C(speed: .slow).effectiveSpeed(bass: 0), 0.1)
        XCTAssertEqual(C(speed: .fast).effectiveSpeed(bass: 0), 0.4)
        XCTAssertEqual(C(speed: .medium).effectiveSpeed(bass: 1), 0.3, accuracy: 1e-12)
        XCTAssertEqual(C(speed: .fast).effectiveSpeed(bass: 1), C.maximumSpeed, "capped")
        XCTAssertEqual(C(speed: .fast, reduceMotion: true).effectiveSpeed(bass: 1), C.maximumSpeed / 2)
        XCTAssertEqual(C(speed: .medium).effectiveSpeed(bass: .nan), 0.2)
        // A long stall runs at most 1 s of steps and is counted; time going backwards does nothing.
        let steps = sim.stepsRun
        sim.advance(toNanoseconds: 10_000_000_000)
        XCTAssertEqual(sim.stepsRun, steps + 240)
        XCTAssertEqual(sim.skippedGaps, 1)
        let held = bits(sim)
        sim.advance(toNanoseconds: 1)
        XCTAssertEqual(bits(sim), held)
    }
}
