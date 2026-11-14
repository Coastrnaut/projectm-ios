// MidTransientTestSupport.swift — test-only fixtures for ANL-008 (ANL-008-T02; research ANL-008-D5):
// mid-band noise bursts (seeded white noise, one-pole low-pass near 1 kHz, ring-modulated by a 2 kHz
// carrier, so the energy sits near 1–3 kHz) on hop-aligned starts. Deterministic: sample clocks and
// fixed seeds only. Reuses ANL-007's `TransientFixture` and `TransientTestSupport`. No Accelerate
// import, no C stdio globals.
import Foundation
@testable import AnalysisFeatures

enum MidTransientFixture {
    /// Adds a decaying mid-band noise burst at each start: peak `amplitude`, decay τ, `length` long.
    static func addNoiseBursts(into samples: inout [Float], amplitude: Float, starts: [Int], seed: UInt64 = 0xB0B,
                               decaySeconds: Double = 0.03, lengthSeconds: Double = 0.12) {
        let rate = Double(TransientFixture.rate)
        let length = Int(lengthSeconds * rate)
        let noise = TestSupport.noise(count: length * max(starts.count, 1), seed: seed, amplitude: 1)
        let smoothing: Double = 1 - exp(-2 * Double.pi * 1_000 / rate)
        let omega: Double = 2 * Double.pi * 2_000 / rate
        let decayPerSample: Double = 1 / (decaySeconds * rate)
        for (b, start) in starts.enumerated() {
            var burst = [Double](repeating: 0, count: length)
            var lowPassed: Double = 0
            var peak: Double = 0
            for n in 0..<length {
                let input = Double(noise[b * length + n])
                lowPassed += smoothing * (input - lowPassed)
                let t = Double(n)
                let carrier: Double = cos(omega * t)
                let envelope: Double = exp(-t * decayPerSample)
                let value: Double = lowPassed * carrier * envelope
                burst[n] = value
                peak = max(peak, abs(value))
            }
            let scale: Double = peak > 0 ? Double(amplitude) / peak : 0
            for n in 0..<length where start + n < samples.count {
                samples[start + n] += Float(burst[n] * scale)
            }
        }
    }

    /// `count` mid-band bursts at `dBFS` peak, 22 hops apart after 24 hops of silence, plus 0.1 s.
    static func burstTrain(count: Int = 4, dBFS: Double = -12) -> (samples: [Float], starts: [Int]) {
        let starts = TransientFixture.starts(count: count)
        var samples = [Float](repeating: 0, count: TransientFixture.firstStart + count * TransientFixture.periodSamples + TransientFixture.rate / 10)
        addNoiseBursts(into: &samples, amplitude: TransientFixture.amplitude(dBFS: dBFS), starts: starts)
        return (samples, starts)
    }

    static func run(_ samples: [Float]) throws -> TransientTestSupport.Run {
        try TransientTestSupport.run(samples, detector: BandTransientDetector(configuration: .midTransient))
    }
}
