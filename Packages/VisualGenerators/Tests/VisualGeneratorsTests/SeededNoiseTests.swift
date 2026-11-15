// SeededNoiseTests.swift — VIS-013-T02 (VIS-013-R2, R7): the shared seeded noise (SHD-006 contract N2) is
// deterministic, bounded and seed-sensitive, the warp is skipped at amount 0, and the GPU text holds the three
// shared functions. ProceduralMaterials' NoiseTextureReferenceTests pin its values through the same code. Pure Swift.
import XCTest
@testable import VisualGenerators

final class SeededNoiseTests: XCTestCase {
    private func field(seed: UInt32, octaves: Int) -> [Float] {
        var out: [Float] = []
        for y in 0..<16 {
            for x in 0..<16 {
                let q: SIMD2<Float> = SeededNoise.domainPoint(x: Float(x) + 0.5, y: Float(y) + 0.5, width: 16, height: 16, scale: 4)
                out.append(SeededNoise.warped(q, octaves: octaves, lacunarity: 2.03, gain: 0.5, seed: seed, warpAmount: 0.8,
                                              warpFrequency: 1))
            }
        }
        return out
    }

    func testValuesAreBoundedDeterministicAndSeedSensitive() {
        let a: [Float] = field(seed: 1301, octaves: 4)
        XCTAssertEqual(a, field(seed: 1301, octaves: 4), "same seed and settings, same values")
        XCTAssertTrue(a.allSatisfy { (v: Float) -> Bool in v >= 0 && v <= 1 })
        let b: [Float] = field(seed: 1302, octaves: 4)
        let differing: Int = zip(a, b).filter { (pair: (Float, Float)) -> Bool in abs(pair.0 - pair.1) > 1e-3 }.count
        XCTAssertGreaterThan(differing, a.count / 2, "a different seed changes most values")
    }

    func testHashAndFinalizerMatchSHD006() {
        XCTAssertEqual(SeededNoise.mix(0), 0)
        XCTAssertEqual(SeededNoise.key(seed: 7, octave: 2, field: 1), 7 | (2 << 16) | (1 << 19))
        let h: Float = SeededNoise.hash(cellX: 3, cellY: -2, key: 99)
        XCTAssertTrue(h >= 0 && h < 1)
        XCTAssertEqual(SeededNoise.hash(cellX: 3 + 4096, cellY: -2, key: 99), h, "cells wrap every 4096")
    }

    func testZeroWarpIsPlainFBmAndDomainPointIsCentred() {
        let q = SIMD2<Float>(1.3, -0.7)
        XCTAssertEqual(SeededNoise.warped(q, octaves: 3, lacunarity: 2.03, gain: 0.5, seed: 5, warpAmount: 0, warpFrequency: 1),
                       SeededNoise.fbm(q, octaves: 3, lacunarity: 2.03, gain: 0.5, seed: 5, field: 0))
        XCTAssertEqual(SeededNoise.domainPoint(x: 50, y: 25, width: 100, height: 50, scale: 4), SIMD2<Float>(0, 0))
        XCTAssertEqual(SeededNoise.domainPoint(x: 50, y: 25, width: 100, height: 50, scale: 4, phase: 2), SIMD2<Float>(2, 1))
    }

    func testTheGPUTextHoldsTheSharedFunctions() {
        for name in ["static float mat_nhash(int2 cell, uint key)", "static float mat_snoise(float2 q, uint key)",
                     "static float mat_sfbm(float2 q, int octaves"] {
            XCTAssertTrue(SeededNoiseShader.functions.contains(name), name)
        }
        XCTAssertFalse(SeededNoiseShader.functions.contains("#include"), "functions only")
    }
}
