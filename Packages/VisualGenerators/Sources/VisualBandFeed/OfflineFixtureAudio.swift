// OfflineFixtureAudio.swift — REC-013 the built-in export audio (research REC-013-D6, D7). Builds on Linux.
//
// Seeded synthetic music, 44.1 kHz interleaved stereo Float32: a 55 Hz kick with a 150 ms decay every 0.5 s
// (120 BPM), an A-minor chord (220, 261.63, 329.63 Hz, 0.12 each; the root and fifth left, the third right) and a
// 30 ms noise hit on every off-beat whose level (0.1…0.3) and samples come from the seed (SplitMix64). The same seed
// gives the same samples; another seed gives other noise.
import Foundation
import VisualGenerators

public enum OfflineFixtureAudio {
    public static let defaultSeconds = 10
    public static let sampleRate = OfflineFrameClock.sampleRate

    /// `seconds` of fixture audio for `seed` (interleaved stereo).
    public static func samples(seed: UInt64, seconds: Double = Double(defaultSeconds)) -> [Float] {
        let frames = max(Int((seconds * Double(sampleRate)).rounded()), 0)
        var out = [Float](repeating: 0, count: frames * 2)
        var rng = SplitMix64(seed: seed)
        let beat = sampleRate / 2                 // 0.5 s
        let hitLength = sampleRate * 3 / 100      // 30 ms
        var hitLevel: Float = 0
        let rate = Double(sampleRate)
        for i in 0..<frames {
            let t = Double(i) / rate
            let sinceBeat = Double(i % beat) / rate
            let kick = Float(0.6 * exp(-sinceBeat / 0.15) * sin(2 * Double.pi * 55 * sinceBeat))
            let root = Float(0.12 * sin(2 * Double.pi * 220 * t))
            let third = Float(0.12 * sin(2 * Double.pi * 261.63 * t))
            let fifth = Float(0.12 * sin(2 * Double.pi * 329.63 * t))
            let offset = (i + beat / 2) % beat        // 0 at each off-beat
            if offset == 0 { hitLevel = Float(0.1 + 0.2 * rng.unit()) }
            var noise: Float = 0
            if offset < hitLength { noise = hitLevel * Float(rng.unit() * 2 - 1) }
            out[2 * i] = kick + root + fifth + noise
            out[2 * i + 1] = kick + third + noise
        }
        return out
    }
}
