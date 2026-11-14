// TransientTestSupport.swift — test-only helpers for ANL-007 (ANL-007-T02): synthetic pulse trains on
// hop-aligned starts, sustained tones, seeded noise, and a runner through a `.silence` lead-in stream
// (2,048-point spectra, hop 512, 44.1 kHz: the bus's analysis) into a band transient detector.
// Deterministic: sample clocks only, fixed seeds. No Accelerate import, no C stdio globals.
import Foundation
import XCTest
@testable import AnalysisFeatures

enum TransientFixture {
    static let rate = 44_100
    static let hop = 512
    /// 22 hops ≈ 255 ms (≈ 235 BPM; short so the tests stay within owner rule 7's budget), every
    /// start on a hop boundary.
    static let periodSamples = 22 * 512
    /// The first pulse starts after 24 hops (≈ 279 ms of silence).
    static let firstStart = 24 * 512

    /// Peak amplitude for a level in dBFS.
    static func amplitude(dBFS: Double) -> Float {
        let exponent: Double = dBFS / 20
        return Float(pow(10, exponent))
    }

    /// Pulse start samples for `count` pulses.
    static func starts(count: Int, period: Int = periodSamples, first: Int = firstStart) -> [Int] {
        (0..<count).map { (i: Int) -> Int in first + i * period }
    }

    /// Adds a decaying sine burst at each start: a·sin(2π f t)·exp(−t/τ) for `length` seconds
    /// (τ = 80 ms, length 240 ms: the tail is 5 % of the peak when it ends, before the next pulse).
    static func addBursts(into samples: inout [Float], frequency: Double, amplitude: Float, starts: [Int],
                          decaySeconds: Double = 0.08, lengthSeconds: Double = 0.24) {
        let length = Int(lengthSeconds * Double(rate))
        let omega: Double = 2 * Double.pi * frequency / Double(rate)
        let decayPerSample: Double = 1 / (decaySeconds * Double(rate))
        for start in starts {
            for n in 0..<length where start + n < samples.count {
                let t = Double(n)
                let envelope: Double = exp(-t * decayPerSample)
                let wave: Double = sin(omega * t)
                let value: Float = amplitude * Float(wave * envelope)
                samples[start + n] += value
            }
        }
    }

    /// Adds a sustained sine from `start` to the end of `samples`.
    static func addTone(into samples: inout [Float], frequency: Double, amplitude: Float, start: Int = 0) {
        let omega: Double = 2 * Double.pi * frequency / Double(rate)
        for n in start..<samples.count {
            let phase: Double = omega * Double(n - start)
            samples[n] += amplitude * Float(sin(phase))
        }
    }

    /// Adds fixed-seed uniform noise in [−peak, peak) (ANL-001's LCG).
    static func addNoise(into samples: inout [Float], peak: Float, seed: UInt64) {
        let noise = TestSupport.noise(count: samples.count, seed: seed, amplitude: peak)
        for n in 0..<samples.count { samples[n] += noise[n] }
    }

    /// A low (55 Hz) pulse train: `count` pulses at `dBFS` peak, plus 0.1 s of trailing silence.
    static func kickTrain(count: Int = 4, dBFS: Double = -6) -> (samples: [Float], starts: [Int]) {
        let starts = starts(count: count)
        var samples = [Float](repeating: 0, count: firstStart + count * periodSamples + rate / 10)
        addBursts(into: &samples, frequency: 55, amplitude: amplitude(dBFS: dBFS), starts: starts)
        return (samples, starts)
    }
}

enum TransientTestSupport {
    struct Run {
        var events: [TransientEvent] = []
        var envelopes: [Float] = []
        var levels: [Float] = []
        var frames = 0
    }

    /// Mono `samples` through a `.silence` lead-in stream (2,048 / 512 / 44.1 kHz) and `detector`.
    static func run(_ samples: [Float], detector: BandTransientDetector, size: FFTSize = .n2048,
                    hop: Int = TransientFixture.hop) throws -> Run {
        let spectrum = try SpectrumConfiguration(size: size, hop: hop, sampleRate: Double(TransientFixture.rate))
        let stream = SpectrumStream(configuration: spectrum, backend: detector.resolvedBackend, clock: { 0 },
                                    leadIn: BandTransientDetector.recommendedLeadIn())
        var result = Run()
        samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            var offset = 0
            while offset < buffer.count {
                offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                while let frame = stream.nextFrame() {
                    result.frames += 1
                    if let event = detector.process(frame, magnitudes: stream.magnitudes) { result.events.append(event) }
                    result.envelopes.append(detector.envelope)
                    result.levels.append(detector.lastLevel)
                }
            }
        }
        return result
    }

    static func run(_ samples: [Float], configuration: TransientDetectorConfiguration = .kick) throws -> Run {
        try run(samples, detector: BandTransientDetector(configuration: configuration))
    }

    /// Counts events matched one-to-one to `starts` within ±`tolerance` samples, and the rest.
    static func match(_ events: [TransientEvent], starts: [Int], tolerance: Int = TransientFixture.hop) -> (hits: Int, misses: Int, extras: Int) {
        var used = [Bool](repeating: false, count: events.count)
        var hits = 0
        for start in starts {
            let found = events.indices.first { (i: Int) -> Bool in
                !used[i] && abs(events[i].sampleIndex - Int64(start)) <= Int64(tolerance)
            }
            if let found { used[found] = true; hits += 1 }
        }
        let extras = used.filter { (u: Bool) -> Bool in !u }.count
        return (hits, starts.count - hits, extras)
    }
}
