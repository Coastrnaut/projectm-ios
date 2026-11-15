// SHD-006-T05, T07 (US2, US3; SHD-006-R2, R4, R6; S2, S3): the CPU reference of Noise Flow's seeded noise — exact
// integer hash, seeds give different fields, warp 0 is the unwarped noise, each control changes the field
// monotonically, and the "Randomize seed" sequence is deterministic. Plain Swift: runs in the Linux shape.
@testable import ProceduralMaterials
import ParameterGraph
import XCTest

final class NoiseTextureReferenceTests: XCTestCase {
    private typealias Reference = NoiseTextureReference
    private let side = 64

    private func field(_ s: NoiseTextureSettings) -> [Float] {
        Reference.field(width: side, height: side, settings: s)
    }

    private func energy(_ s: NoiseTextureSettings) -> Double {
        Reference.highFrequencyEnergy(field(s), width: side, height: side)
    }

    private func differingFraction(_ a: [Float], _ b: [Float]) -> Double {
        let differing: Int = zip(a, b).filter { (pair: (Float, Float)) -> Bool in abs(pair.0 - pair.1) > 1.0 / 255 }.count
        return Double(differing) / Double(a.count)
    }

    func testHashIsExactIntegerArithmetic() {
        XCTAssertEqual(Reference.mix(0), 0, "the finalizer keeps 0")
        XCTAssertEqual(Reference.key(seed: 65535, octave: 7, field: 2), 0xFFFF | (7 << 16) | (2 << 19))
        let a: Float = Reference.hash(cellX: 3, cellY: -5, key: 42)
        XCTAssertEqual(a, Reference.hash(cellX: 3, cellY: -5, key: 42), "deterministic")
        XCTAssertEqual(a, Reference.hash(cellX: 3 + 4096, cellY: -5 - 4096, key: 42), "cells wrap every 4096")
        XCTAssertNotEqual(a, Reference.hash(cellX: 3, cellY: -5, key: 43))
        var values: Set<Float> = []
        for x in Int32(0)..<64 { values.insert(Reference.hash(cellX: x, cellY: 0, key: 0)) }
        XCTAssertGreaterThan(values.count, 60, "the lattice is not constant")
        XCTAssertTrue(values.allSatisfy { (v: Float) -> Bool in v >= 0 && v < 1 })
    }

    /// S2 on the CPU: four seeds, pairwise different in at least 25 % of the values; one seed twice is identical.
    func testSeedsGiveDifferentFieldsAndOneSeedIsStable() {
        let seeds: [UInt32] = [0, 1, 4242, 65535]
        let fields: [[Float]] = seeds.map { (seed: UInt32) -> [Float] in field(NoiseTextureSettings(seed: seed)) }
        XCTAssertEqual(fields[2], field(NoiseTextureSettings(seed: 4242)))
        for i in 0..<fields.count {
            for j in (i + 1)..<fields.count {
                XCTAssertGreaterThan(differingFraction(fields[i], fields[j]), 0.25, "seeds \(seeds[i]) and \(seeds[j])")
            }
        }
    }

    func testWarpZeroIsTheUnwarpedNoiseAndLowCostIgnoresWarp() {
        let flat = NoiseTextureSettings(seed: 9, octaves: 5, warpAmount: 0)
        let q = SIMD2<Float>(1.37, -2.11)
        XCTAssertEqual(Reference.value(at: q, settings: flat), Reference.fbm(q, settings: flat, octaves: 5, field: 0))
        let warped = NoiseTextureSettings(seed: 9, octaves: 5, warpAmount: 2)
        XCTAssertEqual(Reference.value(at: q, settings: warped, lite: true), Reference.fbm(q, settings: flat, octaves: 3, field: 0))
    }

    /// S3: more octaves, a higher lacunarity and a higher gain each add high-frequency energy (strictly).
    func testOctavesLacunarityAndGainAddFinerDetail() {
        let octaves: [Double] = [1, 2, 4, 8].map { (n: Int) -> Double in energy(NoiseTextureSettings(octaves: n, warpAmount: 0)) }
        let lacunarity: [Double] = [Float(1.5), 2.5, 3.5].map { (l: Float) -> Double in
            energy(NoiseTextureSettings(octaves: 4, lacunarity: l, warpAmount: 0))
        }
        let gain: [Double] = [Float(0.3), 0.5, 0.7].map { (g: Float) -> Double in
            energy(NoiseTextureSettings(octaves: 4, gain: g, warpAmount: 0))
        }
        for (name, series) in [("octaves", octaves), ("lacunarity", lacunarity), ("gain", gain)] {
            for i in 1..<series.count { XCTAssertGreaterThan(series[i], series[i - 1], "\(name): \(series)") }
        }
    }

    /// S3: more warp moves the field further from the unwarped one; the warp frequency changes the field.
    func testWarpAmountAndFrequency() {
        let base: [Float] = field(NoiseTextureSettings(seed: 5, octaves: 4, warpAmount: 0))
        let distances: [Double] = [Float(0.5), 1, 2].map { (amount: Float) -> Double in
            let warped: [Float] = field(NoiseTextureSettings(seed: 5, octaves: 4, warpAmount: amount))
            return zip(base, warped).reduce(0.0) { (s: Double, p: (Float, Float)) -> Double in s + Double(abs(p.0 - p.1)) } / Double(base.count)
        }
        XCTAssertGreaterThan(distances[0], 0)
        for i in 1..<distances.count { XCTAssertGreaterThan(distances[i], distances[i - 1], "\(distances)") }
        let slow: [Float] = field(NoiseTextureSettings(seed: 5, octaves: 4, warpAmount: 1, warpFrequency: 0.5))
        let fast: [Float] = field(NoiseTextureSettings(seed: 5, octaves: 4, warpAmount: 1, warpFrequency: 3))
        XCTAssertGreaterThan(differingFraction(slow, fast), 0.25)
    }

    func testSettingsFromMaterialValuesClampLikeTheShader() throws {
        let definition = ProceduralMaterialCatalog.definition(.noiseFlow)
        var values = MaterialParameterValues(definition)
        XCTAssertEqual(NoiseTextureSettings(values: values), NoiseTextureSettings())
        try values.set(.integer(65535), for: definition.parameterID("seed"))
        try values.set(.integer(8), for: definition.parameterID("octaves"))
        try values.set(.continuous(9), for: definition.parameterID("lacunarity"))
        try values.set(.continuous(0.25), for: definition.parameterID("warpFrequency"))
        let s = NoiseTextureSettings(values: values)
        XCTAssertEqual(s.seed, 65535)
        XCTAssertEqual(s.octaves, 8)
        XCTAssertEqual(s.lacunarity, 3.5)
        XCTAssertEqual(s.warpFrequency, 0.25)
        XCTAssertEqual(NoiseTextureSettings(seed: 99_999, octaves: 12, gain: 2).seed, 65535)
        XCTAssertEqual(NoiseTextureSettings(seed: 99_999, octaves: 12, gain: 2).octaves, 8)
        XCTAssertEqual(NoiseTextureSettings(seed: 99_999, octaves: 12, gain: 2).gain, 0.8)
    }

    /// R6: "Randomize seed" is a fixed sequence (no system random source), in range, never the current seed.
    func testSeedSequenceIsDeterministicAndSkipsTheCurrentSeed() {
        var a = NoiseSeedSequence()
        var b = NoiseSeedSequence()
        var current = 0
        var seen: [Int] = []
        for _ in 0..<20 {
            let next: Int = a.next(after: current)
            XCTAssertEqual(next, b.next(after: current))
            XCTAssertNotEqual(next, current)
            XCTAssertTrue(NoiseSeedSequence.seedRange.contains(next))
            seen.append(next)
            current = next
        }
        XCTAssertGreaterThan(Set(seen).count, 18, "varied")
        var c = NoiseSeedSequence()
        let first: Int = c.next(after: -1)
        var d = NoiseSeedSequence()
        XCTAssertNotEqual(d.next(after: first), first, "the current seed is skipped")
        XCTAssertEqual(d.counter, 3, "one counter value was skipped")
    }
}
