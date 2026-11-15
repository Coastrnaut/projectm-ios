// ParticleEmitterSettingsTests.swift — SHD-007-T03: every emitter value is clamped to its range, non-finite values
// take their defaults, inverted ranges are ordered, decoding is lenient, the rate resolves to 0.001 (SHD-007-R2).
import Foundation
import XCTest
@testable import VisualGenerators

final class ParticleEmitterSettingsTests: XCTestCase {
    func testValuesAreClampedAndOrdered() {
        let s = ParticleEmitterSettings(shapeWidth: 9, shapeHeight: -1, rate: 1000, minimumSpeed: 20, maximumSpeed: 1,
                                        direction: 400, spread: -5, minimumLifetime: 50, maximumLifetime: 0, gravity: -2,
                                        boxHalfWidth: 0, boxHeight: 99, restitution: 3)
        XCTAssertEqual(s.shapeWidth, 2)
        XCTAssertEqual(s.shapeHeight, 0)
        XCTAssertEqual(s.rate, 240)
        XCTAssertEqual(s.minimumSpeed, 1)
        XCTAssertEqual(s.maximumSpeed, 8, "clamped, then ordered")
        XCTAssertEqual(s.direction, 180)
        XCTAssertEqual(s.spread, 0)
        XCTAssertEqual(s.minimumLifetime, 0.1)
        XCTAssertEqual(s.maximumLifetime, 10)
        XCTAssertEqual(s.gravity, 0)
        XCTAssertEqual(s.boxHalfWidth, 0.2)
        XCTAssertEqual(s.boxHeight, 5)
        XCTAssertEqual(s.restitution, 1)
        let n = ParticleEmitterSettings(rate: .nan, minimumLifetime: .infinity, gravity: -.infinity)
        XCTAssertEqual(n.rate, 30)
        XCTAssertEqual(n.minimumLifetime, 1.5)
        XCTAssertEqual(n.gravity, 3)
        XCTAssertEqual(ParticleFountainConfiguration(emitter: ParticleEmitterSettings()).emitter, ParticleEmitterSettings())
        var configuration = ParticleFountainConfiguration(emitter: ParticleEmitterSettings())
        configuration.emitter?.rate = 999
        XCTAssertEqual(configuration.clamped().emitter?.rate, 240, "the configuration clamps its emitter")
    }

    func testRateResolution() {
        XCTAssertEqual(ParticleEmitterSettings(rate: 37.5).rateMilli, 37_500)
        XCTAssertEqual(ParticleEmitterSettings(rate: 0.0004).rateMilli, 0)
        XCTAssertEqual(ParticleEmitterSettings(rate: 12.3456).expectedSpawns(steps: 2400), 123)
        XCTAssertEqual(ParticleEmitterSettings(rate: 240).expectedSpawns(steps: 240), 240, "one per step at most")
    }

    func testCodingRoundTripsAndIsLenient() throws {
        let s = ParticleEmitterSettings(shape: .rectangle, rate: 12.5, bounds: .box, action: .kill, seed: UInt64.max)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ParticleEmitterSettings.self, from: data), s)
        let partial = Data(#"{"shape":"hexagon","rate":"fast","gravity":50,"spread":12,"seed":-3}"#.utf8)
        let p = try JSONDecoder().decode(ParticleEmitterSettings.self, from: partial)
        XCTAssertEqual(p.shape, .point, "unknown shape → default")
        XCTAssertEqual(p.rate, 30, "wrong type → default")
        XCTAssertEqual(p.gravity, 10, "clamped")
        XCTAssertEqual(p.spread, 12)
        XCTAssertEqual(p.seed, ParticleEmitterSettings.defaultSeed, "a negative seed → default")
        XCTAssertEqual(try JSONDecoder().decode(ParticleEmitterSettings.self, from: Data("{}".utf8)), ParticleEmitterSettings())
    }
}
