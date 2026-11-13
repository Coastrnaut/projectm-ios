// BandTestSupport.swift — test-only oracle for ANL-002 (ANL-002-T02): band edges, bin intervals,
// overlap weights and bin ownership recomputed in Double from the spec's formulas (ANL-002-R2, R3;
// research ANL-002-D2) without calling `BandLayout`, and the multi-tone fixture built from the AUD-016
// tone generator (research ANL-002-D7). No Accelerate, AVFAudio or SwiftUI (runs on Linux).
import XCTest
import AudioCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum BandOracle {
    /// The multi-tone fixture: the catalog's four sine frequencies plus two upper tones.
    static let toneFrequencies: [Double] = [100, 440, 1_000, 1_500, 5_000, 12_000]
    static let toneAmplitude = 0.15

    static func upperEdge(sampleRate: Double) -> Double { min(20_000, sampleRate / 2) }

    /// `20 · (upper/20)^(i/B)`, i = 0…B.
    static func edges(count: Int, sampleRate: Double) -> [Double] {
        let upper = upperEdge(sampleRate: sampleRate)
        return (0...count).map { 20 * pow(upper / 20, Double($0) / Double(count)) }
    }

    /// The frequency interval bin `k` covers; nil for DC.
    static func binInterval(_ k: Int, size: Int, sampleRate: Double) -> (lo: Double, hi: Double)? {
        guard k >= 1, k <= size / 2 else { return nil }
        let delta = sampleRate / Double(size)
        let lo = k == 1 ? 0 : (Double(k) - 0.5) * delta
        let hi = k == size / 2 ? Double(k) * delta : (Double(k) + 0.5) * delta
        return (lo, hi)
    }

    /// Fraction of bin `k`'s interval inside [lo, hi].
    static func weight(bin k: Int, lo: Double, hi: Double, size: Int, sampleRate: Double) -> Double {
        guard let interval = binInterval(k, size: size, sampleRate: sampleRate) else { return 0 }
        let overlap = min(hi, interval.hi) - max(lo, interval.lo)
        return overlap > 0 ? overlap / (interval.hi - interval.lo) : 0
    }

    /// The band with the largest share of bin `k` (lower band on a tie); nil if none.
    static func ownerBand(ofBin k: Int, edges: [Double], size: Int, sampleRate: Double) -> Int? {
        var best: Int?
        var bestWeight = 0.0
        for b in 0..<(edges.count - 1) {
            let w = weight(bin: k, lo: edges[b], hi: edges[b + 1], size: size, sampleRate: sampleRate)
            if w > bestWeight { best = b; bestWeight = w }
        }
        return best
    }

    /// Mono sum of the fixture's sines (AUD-016 `ToneGenerator`), in `toneFrequencies` order, Float.
    static func multiTone(sampleRate: Int, frames: Int) throws -> [Float] {
        var sum = [Float](repeating: 0, count: frames)
        let format = try ToneFormat(sampleRate: sampleRate, channels: 1)
        for frequency in toneFrequencies {
            let generator = try ToneGenerator(signal: .sine(SineTone(frequency: frequency, amplitude: toneAmplitude)), format: format)
            let tone = generator.interleaved(frames: frames)
            for i in 0..<frames { sum[i] += tone[i] }
        }
        return sum
    }
}
