// AcceptanceSweeps.swift — the full acceptance cross-products of ANL-001 and ANL-004, on demand
// (owner rule 7, 2026-11-13). The default test run checks representative cases
// (`FixtureAcceptanceTests`, `OnsetAcceptanceTests`); these sweeps repeat the same rules over every
// fixture × FFT size × hop × rate × backend. Run in Release; exit status 1 on any failure:
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench --anl001-sweep
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench --anl004-sweep
// Public API only (no @testable import); the rules mirror the tests' assertions.
import AnalysisFeatures
import AudioCore

private var allBackends: [SpectrumBackend] {
    SpectrumBackend.isAcceleratedAvailable ? [.accelerated, .portable] : [.portable]
}

private struct SweepFailures {
    var count = 0
    mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { count += 1; print("FAIL \(message())") }
    }
}

/// Fixed-seed uniform noise in [-peak, peak) (the tests' 64-bit LCG).
private func lcgNoise(count: Int, peak: Float, seed: UInt64 = 0x5EED) -> [Float] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * peak
    }
}

// MARK: - ANL-001

/// Every sine check (sine-split per channel) × 2 rates × 5 sizes × every backend: whole loop, every
/// frame within one bin of the documented bin, the first window exactly on it, values finite, a
/// repeated run bit-identical; every sweep × 2 rates × 5 sizes × every backend: finite and identical.
func runANL001Sweep() -> Int32 {
    var failures = SweepFailures()
    var runs = 0
    func analyse(_ stereo: [Float], _ configuration: SpectrumConfiguration, _ backend: SpectrumBackend) -> [Float] {
        let stream = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 })
        var magnitudes: [Float] = []
        stereo.withUnsafeBufferPointer { buffer in
            let frames = buffer.count / 2
            var offset = 0
            while offset < frames {
                offset += stream.append(interleaved: buffer.baseAddress! + 2 * offset, frames: frames - offset, channels: 2)
                while stream.nextFrame() != nil { magnitudes.append(contentsOf: stream.magnitudes) }
            }
        }
        return magnitudes
    }
    for fixture in ReferenceToneCatalog.fixtures {
        var checks: [(ChannelMode, Double?, String)] = []
        switch fixture.signal {
        case .sine(let tone):
            if let left = tone.left, let right = tone.right, left != right {
                checks = [(.left, left, " L"), (.right, right, " R")]
            } else {
                checks = [(.mid, tone.left ?? tone.right, "")]
            }
        case .sweep: checks = [(.mid, nil, "")]
        default: continue
        }
        for rate in ReferenceToneCatalog.variantRates {
            guard let stereo = try? fixture.loop(sampleRate: rate, channels: 2) else {
                failures.check(false, "\(fixture.id) \(rate): loop"); continue
            }
            for (mode, frequency, suffix) in checks {
                for size in FFTSize.allCases {
                    guard let configuration = try? SpectrumConfiguration(size: size, sampleRate: Double(rate), channelMode: mode) else { continue }
                    for backend in allBackends {
                        let label = "\(backend) \(fixture.id)\(suffix) \(rate) Hz N=\(size.rawValue)"
                        let first = analyse(stereo, configuration, backend)
                        let second = analyse(stereo, configuration, backend)
                        runs += 1
                        failures.check(first.allSatisfy { $0.isFinite && $0 >= 0 }, "\(label): finite")
                        failures.check(first.map(\.bitPattern) == second.map(\.bitPattern), "\(label): repeated run differs")
                        guard let frequency else { continue }
                        let bins = size.binCount
                        let expected = ReferenceToneCatalog.nearestBin(frequency: frequency, fftSize: size.rawValue, sampleRate: rate)
                        var worst = 0
                        for f in 0..<(first.count / bins) {
                            var peak = 0
                            for k in 1..<bins where first[f * bins + k] > first[f * bins + peak] { peak = k }
                            if f == 0 { failures.check(peak == expected, "\(label): first window peak \(peak), documented \(expected)") }
                            worst = max(worst, abs(peak - expected))
                        }
                        failures.check(worst <= 1, "\(label): a frame peaked \(worst) bins away")
                    }
                }
            }
        }
    }
    print("ANL-001 sweep: \(runs) whole-loop runs (each twice), \(failures.count) failures")
    return failures.count == 0 ? 0 : 1
}

// MARK: - ANL-004

private struct OnsetRun {
    var events: [OnsetEvent] = []
    var nonZeroFlux = 0
}

private func onsetRun(_ samples: [Float], size: FFTSize, hop: Int, rate: Int, backend: SpectrumBackend) -> OnsetRun? {
    guard let spectrum = try? SpectrumConfiguration(size: size, hop: hop, sampleRate: Double(rate)),
          let configuration = try? OnsetDetectorConfiguration(sampleRate: Double(rate)) else { return nil }
    let stream = SpectrumStream(configuration: spectrum, backend: backend, clock: { 0 }, leadIn: .silence)
    let detector = SpectralFluxOnsetDetector(configuration: configuration, backend: backend)
    var result = OnsetRun()
    samples.withUnsafeBufferPointer { buffer in
        var offset = 0
        while offset < buffer.count {
            offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
            while let frame = stream.nextFrame() {
                if let event = detector.process(frame, magnitudes: stream.magnitudes) { result.events.append(event) }
                if detector.lastFlux.bitPattern != 0 { result.nonZeroFlux += 1 }
            }
        }
    }
    return result
}

/// Each onset takes the first unused event within ±tolerance; returns (misses, unmatched, max |error|).
private func matchOnsets(_ events: [OnsetEvent], _ onsets: [Int64], tolerance: Int) -> (Int, Int, Int64) {
    var used = [Bool](repeating: false, count: events.count)
    var misses = 0, start = 0
    var maxError: Int64 = 0
    for onset in onsets {
        var found: Int?
        var i = start
        while i < events.count, events[i].sampleIndex <= onset + Int64(tolerance) {
            if !used[i], abs(events[i].sampleIndex - onset) <= Int64(tolerance) { found = i; break }
            i += 1
        }
        if let found {
            used[found] = true
            maxError = max(maxError, abs(events[found].sampleIndex - onset))
            start = found + 1
        } else {
            misses += 1
        }
    }
    return (misses, used.filter { !$0 }.count, maxError)
}

/// The pulse matrix (3 fixtures × 2 rates × 5 sizes × hops N/2, N/4, N/8 × every backend; 90 lines
/// per backend), silence and −80/−70 dBFS noise (0 events, every detection value 0) and every sine
/// and sweep (at most the start event) at 5 sizes × hops N/2, N/4 × 2 rates on the first backend.
func runANL004Sweep() -> Int32 {
    var failures = SweepFailures()
    var lines = 0
    for id in ["pulse-120", "pulse-120-accent", "pulse-132"] {
        guard let fixture = ReferenceToneCatalog.fixture(id: id) else { failures.check(false, id); continue }
        for rate in ReferenceToneCatalog.variantRates {
            guard let loop = try? fixture.loop(sampleRate: rate, channels: 1) else { continue }
            let onsets = fixture.onsetFrames(sampleRate: rate)
            for backend in allBackends {
                for size in FFTSize.allCases {
                    for hop in [2, 4, 8].map({ size.rawValue / $0 }) {
                        guard let run = onsetRun(loop, size: size, hop: hop, rate: rate, backend: backend) else { continue }
                        let (misses, unmatched, maxError) = matchOnsets(run.events, onsets, tolerance: hop)
                        failures.check(misses == 0 && unmatched == 0, "\(backend) \(id) \(rate) N=\(size.rawValue) hop=\(hop): misses \(misses), false \(unmatched)")
                        print("ANL-004 matrix: \(backend) | \(id) | \(rate) | \(size.rawValue) | \(hop) | \(onsets.count) | \(run.events.count) | \(misses) | \(unmatched) | \(maxError)")
                        lines += 1
                    }
                }
            }
        }
    }
    failures.check(lines == 90 * allBackends.count, "pulse matrix has \(lines) lines")
    let backend = allBackends[0]
    var quietRuns = 0, toneRuns = 0
    for rate in ReferenceToneCatalog.variantRates {
        var quiet: [(String, [Float])] = [
            ("noise -80 dBFS", lcgNoise(count: 10 * rate, peak: 1e-4)),
            ("noise -70 dBFS", lcgNoise(count: 10 * rate, peak: 3e-4, seed: 0xBEEF)),
        ]
        if let silence = try? ReferenceToneCatalog.fixture(id: "silence")?.loop(sampleRate: rate, channels: 1) {
            quiet.insert(("silence", silence), at: 0)
        }
        var tones: [(String, [Float])] = []
        for fixture in ReferenceToneCatalog.fixtures {
            switch fixture.signal {
            case .sine, .sweep:
                guard let stereo = try? fixture.loop(sampleRate: rate, channels: 2) else { continue }
                tones.append((fixture.id, (0..<(stereo.count / 2)).map { (stereo[2 * $0] + stereo[2 * $0 + 1]) * 0.5 }))
            default: continue
            }
        }
        for size in FFTSize.allCases {
            for hop in [size.rawValue / 2, size.rawValue / 4] {
                for (name, signal) in quiet {
                    guard let run = onsetRun(signal, size: size, hop: hop, rate: rate, backend: backend) else { continue }
                    failures.check(run.events.isEmpty && run.nonZeroFlux == 0, "\(name) \(rate) N=\(size.rawValue) hop=\(hop): \(run.events.count) events, \(run.nonZeroFlux) non-zero detection values")
                    quietRuns += 1
                }
                for (name, signal) in tones {
                    guard let run = onsetRun(signal, size: size, hop: hop, rate: rate, backend: backend) else { continue }
                    let startOnly = run.events.count <= 1 && run.events.allSatisfy { abs($0.sampleIndex) <= Int64(hop) }
                    failures.check(startOnly, "\(name) \(rate) N=\(size.rawValue) hop=\(hop): events at \(run.events.map(\.sampleIndex))")
                    toneRuns += 1
                }
            }
        }
    }
    print("ANL-004 sweep: \(lines) pulse runs, \(quietRuns) silence/noise runs, \(toneRuns) tone runs, \(failures.count) failures")
    return failures.count == 0 ? 0 : 1
}
