// SHD-008-T13 (US3; SHD-008-R7, R8, S4): the particle emitter's `path` spawn shape. A pure seeded 10 s run on an
// injected frame clock with speed 0 and gravity 0, so every live particle sits exactly where it was born: after every
// frame every live particle lies inside the concave L-shaped path (mapped to R as width × height around the emitter
// point) and none in its notch; spawn attempts equal SHD-007's formula; two runs are identical. Settings keep the
// path exactly through JSON; an invalid stored path reads as the default.
import Foundation
import XCTest
@testable import VisualGenerators

final class VectorPathEmitterTests: XCTestCase {
    private static let anchor: UInt64 = 1_000_000_000
    private static let tenSeconds: UInt64 = 10_000_000_000

    private static func settings() throws -> ParticleEmitterSettings {
        ParticleEmitterSettings(shape: .path, shapeWidth: 1.6, shapeHeight: 1.2, rate: 60, minimumSpeed: 0, maximumSpeed: 0,
                                minimumLifetime: 0.5, maximumLifetime: 1.5, gravity: 0, bounds: .none, seed: 0x5EED_0008,
                                path: try VectorPath(VectorPathTests.lShape))
    }

    private static func frames(jittery: Bool) -> [UInt64] {
        guard jittery else { return (1...600).map { (i: Int) -> UInt64 in UInt64(i) * tenSeconds / 600 } }
        var rng = SplitMix64(seed: 42)
        var t: UInt64 = 0
        var out: [UInt64] = []
        while t < tenSeconds {
            t = min(t + 5_000_000 + rng.next() % 35_000_001, tenSeconds)
            out.append(t)
        }
        return out
    }

    /// The particle's point back in the path's unit square.
    private static func unit(_ p: FountainParticle, _ s: ParticleEmitterSettings) -> VectorPoint {
        VectorPoint(x: p.x / s.shapeWidth + 0.5, y: 0.5 - p.y / s.shapeHeight)
    }

    private func run(_ s: ParticleEmitterSettings, jittery: Bool) -> (sim: ParticleFountainSimulation, outside: Int, notch: Int,
                                                                       seen: Int, positions: [Double]) {
        let sim = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(emitter: s))
        sim.advance(toNanoseconds: Self.anchor)
        var outside = 0, notch = 0, seen = 0
        var positions: [Double] = []
        for offset in Self.frames(jittery: jittery) {
            sim.advance(toNanoseconds: Self.anchor + offset)
            for i in 0..<sim.liveCount {
                let q: VectorPoint = Self.unit(sim.particle(i), s)
                seen += 1
                if !s.path.contains(q) && !VectorPathTests.onBoundary(q) { outside += 1 }
                if q.x > 0.5 + 1e-9 && q.y < 0.5 - 1e-9 { notch += 1 }
            }
            if sim.liveCount > 0 { positions.append(sim.particle(0).x) }
        }
        return (sim, outside, notch, seen, positions)
    }

    func testTenSecondSeededRunSpawnsEveryParticleInsideThePath() throws {
        let s = try Self.settings()
        let steps = UInt64(ParticleFountainConfiguration.stepsPerSecond) * 10
        XCTAssertEqual(s.expectedSpawns(steps: steps), 600)
        var runs: [[Double]] = []
        for jittery in [false, true] {
            let r = run(s, jittery: jittery)
            XCTAssertEqual(r.sim.spawnAttempts, 600, "SHD-007's exact count")
            XCTAssertEqual(r.sim.spawnedCount, 600)
            XCTAssertGreaterThan(r.seen, 10_000)
            XCTAssertEqual(r.outside, 0, "every particle inside the path")
            XCTAssertEqual(r.notch, 0, "none in the notch")
            runs.append(r.positions)
        }
        XCTAssertEqual(run(s, jittery: false).positions, runs[0], "same seed, same run")
    }

    func testSettingsKeepThePathAndAnInvalidStoredPathReadsAsTheDefault() throws {
        let s = try Self.settings()
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(ParticleEmitterSettings.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.path.points, s.path.points)
        XCTAssertEqual(back.shape, .path)
        let bowTie = Data(#"{"shape":"path","rate":12,"path":{"points":[{"x":0.1,"y":0.1},{"x":0.9,"y":0.9},{"x":0.9,"y":0.1},{"x":0.1,"y":0.9}]}}"#.utf8)
        let damaged = try JSONDecoder().decode(ParticleEmitterSettings.self, from: bowTie)
        XCTAssertEqual(damaged.path, .default)
        XCTAssertEqual(damaged.rate, 12, "the other fields still read")
        let old = try JSONDecoder().decode(ParticleEmitterSettings.self, from: Data(#"{"shape":"circle"}"#.utf8))
        XCTAssertEqual(old.path, .default, "settings saved before SHD-008")
        XCTAssertEqual(ParticleEmitterSettings().path, .default)
    }
}
