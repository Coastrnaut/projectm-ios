// HighTransientTestSupport.swift — test-only fixtures for ANL-009 (ANL-009-T02; research ANL-009-D5):
// high-band clicks (seeded white noise through two cascaded one-pole high-passes at 7 kHz, so the
// energy sits above ≈ 6 kHz, with a fast exponential decay) on hop-aligned starts, and continuous
// high-band noise. Deterministic: sample clocks and fixed seeds only. Reuses ANL-007's
// `TransientFixture` and `TransientTestSupport`. No Accelerate import, no C stdio globals.
import Foundation
@testable import AnalysisFeatures

enum HighTransientFixture {
    /// White noise high-passed twice at `cutoff` (one-pole each: 12 dB/octave below it), unit-ish scale.
    static func highPassedNoise(count: Int, seed: UInt64, cutoff: Double = 7_000) -> [Double] {
        let noise = TestSupport.noise(count: count, seed: seed, amplitude: 1)
        let rate = Double(TransientFixture.rate)
        let smoothing: Double = 1 - exp(-2 * Double.pi * cutoff / rate)
        var low1: Double = 0
        var low2: Double = 0
        var output = [Double](repeating: 0, count: count)
        for n in 0..<count {
            let input = Double(noise[n])
            low1 += smoothing * (input - low1)
            let stage1: Double = input - low1
            low2 += smoothing * (stage1 - low2)
            output[n] = stage1 - low2
        }
        return output
    }

    /// Adds a decaying high-band click at each start: peak `amplitude`, decay τ, `length` long.
    static func addClicks(into samples: inout [Float], amplitude: Float, starts: [Int], seed: UInt64 = 0x41A7,
                          decaySeconds: Double = 0.008, lengthSeconds: Double = 0.03) {
        let rate = Double(TransientFixture.rate)
        let length = Int(lengthSeconds * rate)
        let noise = highPassedNoise(count: length * max(starts.count, 1), seed: seed)
        let decayPerSample: Double = 1 / (decaySeconds * rate)
        for (c, start) in starts.enumerated() {
            var peak: Double = 0
            var burst = [Double](repeating: 0, count: length)
            for n in 0..<length {
                let envelope: Double = exp(-Double(n) * decayPerSample)
                let value: Double = noise[c * length + n] * envelope
                burst[n] = value
                peak = max(peak, abs(value))
            }
            let scale: Double = peak > 0 ? Double(amplitude) / peak : 0
            for n in 0..<length where start + n < samples.count {
                samples[start + n] += Float(burst[n] * scale)
            }
        }
    }

    /// `count` clicks at `dBFS` peak, 22 hops apart after 24 hops of silence, plus 0.1 s.
    static func clickTrain(count: Int = 4, dBFS: Double = -12) -> (samples: [Float], starts: [Int]) {
        let starts = TransientFixture.starts(count: count)
        var samples = [Float](repeating: 0, count: TransientFixture.firstStart + count * TransientFixture.periodSamples + TransientFixture.rate / 10)
        addClicks(into: &samples, amplitude: TransientFixture.amplitude(dBFS: dBFS), starts: starts)
        return (samples, starts)
    }

    /// Continuous high-passed noise at `dBFS` peak (approximately) from `start` to `seconds`.
    static func continuousNoise(seconds: Double, dBFS: Double, start: Int = TransientFixture.firstStart, seed: UInt64 = 0xC0FFEE) -> [Float] {
        let count = Int(seconds * Double(TransientFixture.rate))
        let noise = highPassedNoise(count: count, seed: seed)
        let peak: Double = noise.reduce(0) { (m: Double, v: Double) -> Double in max(m, abs(v)) }
        let scale: Double = peak > 0 ? Double(TransientFixture.amplitude(dBFS: dBFS)) / peak : 0
        var samples = [Float](repeating: 0, count: count)
        for n in start..<count { samples[n] = Float(noise[n] * scale) }
        return samples
    }

    /// The largest number of events in any 1 s span (sample − rate, sample].
    static func maximumEventsPerSecond(_ events: [TransientEvent]) -> Int {
        let window = Int64(TransientFixture.rate)
        var best = 0
        for (i, event) in events.enumerated() {
            let inWindow = events[...i].filter { (e: TransientEvent) -> Bool in event.sampleIndex - e.sampleIndex < window }.count
            best = max(best, inWindow)
        }
        return best
    }

    /// Through 2,048-point spectra at hop 512 (the bus) unless another geometry is given.
    static func run(_ samples: [Float], configuration: TransientDetectorConfiguration = .highTransient,
                    size: FFTSize = .n2048, hop: Int = TransientFixture.hop) throws
        -> (run: TransientTestSupport.Run, detector: BandTransientDetector) {
        let detector = BandTransientDetector(configuration: configuration)
        let run = try TransientTestSupport.run(samples, detector: detector, size: size, hop: hop)
        return (run, detector)
    }

    /// `.highTransient` with no event-rate cap (to show what the cap removes), optionally another refractory period.
    static func uncapped(refractorySeconds: Double? = nil) throws -> TransientDetectorConfiguration {
        let h = TransientDetectorConfiguration.highTransient
        return try TransientDetectorConfiguration(
            band: .highTransient, sampleRate: h.sampleRate, lowerFrequency: h.lowerFrequency, upperFrequency: h.upperFrequency,
            floorDecibels: h.floorDecibels, dominanceDecibels: h.dominanceDecibels, baselineSeconds: h.baselineSeconds,
            minimumRiseDecibels: h.minimumRiseDecibels, deviationMultiplier: h.deviationMultiplier,
            refractorySeconds: refractorySeconds ?? h.refractorySeconds, envelopeSeconds: h.envelopeSeconds, breadthWeight: h.breadthWeight,
            confidenceMarginDecibels: h.confidenceMarginDecibels, maximumEventsPerSecond: 0)
    }
}
