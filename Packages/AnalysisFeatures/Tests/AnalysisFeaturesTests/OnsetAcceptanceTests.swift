// OnsetAcceptanceTests.swift — the roadmap acceptance of ANL-004 against the AUD-016 fixtures
// (ANL-004-T10, T11, T13, T15, T17; ANL-004-R15, R17, S1 to S5):
//   "Impulse train produces onset events within one analysis hop and no false silence events."
// "Within one hop": each catalog onset frame is matched by exactly one event with
// |event.sampleIndex − onset| ≤ hop, and no event is left unmatched (spec Clarifications).
// Streams use the `.silence` lead-in and a fixed clock; every run is a whole 10 s loop.
// Representative cases (shortened 2026-11-13 under owner rule 7): each rule is checked at the
// default shape (N = 2,048, hop N/2) and at the edges — the smallest size at the tightest hop (N/8),
// the largest size — at both rates, instead of every fixture × size × hop × rate × backend. The full
// cross-product (the 90-line pulse matrix, the tone and silence sweeps) runs on demand in Release:
//   swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench --anl004-sweep
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class OnsetAcceptanceTests: XCTestCase {
    /// One stream setting: sample rate, FFT size, hop.
    private struct Case: CustomStringConvertible {
        let rate: Int
        let size: FFTSize
        let hop: Int
        init(_ rate: Int, _ size: FFTSize, _ hop: Int) { self.rate = rate; self.size = size; self.hop = hop }
        var description: String { "\(rate) N=\(size.rawValue) hop=\(hop)" }
    }

    // MARK: US1 — pulse trains

    /// Each case on the build's first backend (vDSP where compiled in, else portable); `portable`
    /// cases repeat on the portable backend where vDSP exists. Prints one `ANL-004 matrix:` line per
    /// first-backend case.
    private func checkPulses(_ id: String, _ cases: [Case], portable: [Case] = []) throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
        var largestRatio = 0.0
        var runs: [(Case, SpectrumBackend)] = cases.map { ($0, TestSupport.backends.first!) }
        if SpectrumBackend.isAcceleratedAvailable { runs += portable.map { ($0, .portable) } }
        for (c, backend) in runs {
            let loop = try fixture.loop(sampleRate: c.rate, channels: 1)
            let onsets = fixture.onsetFrames(sampleRate: c.rate)
            let run = try OnsetTestSupport.run(loop, size: c.size, hop: c.hop, rate: c.rate, backend: backend)
            let result = OnsetTestSupport.match(run.events, onsets: onsets, tolerance: c.hop)
            let label = "\(backend) \(id) \(c)"
            XCTAssertTrue(result.passed, "\(label): \(result)")
            XCTAssertEqual(run.events.count, onsets.count, label)
            XCTAssertGreaterThan(onsets.count, 10, label)
            largestRatio = max(largestRatio, Double(result.maxError) / Double(c.hop))
            if backend == TestSupport.backends.first {
                print("ANL-004 matrix: \(id) | \(c.rate) | \(c.size.rawValue) | \(c.hop) | \(result.onsets) | \(result.events) | \(result.misses) | \(result.unmatched) | \(result.maxError)")
            }
        }
        print("ANL-004 pulses \(id): \(runs.count) runs, largest |error|/hop \(largestRatio)")
    }

    /// Both rates at the default shape; the smallest size at its tightest hop (N/8) and the largest
    /// size; the default shape repeated on the portable backend.
    func testPulse120GivesOneOnsetPerPulseWithinOneHop() throws {
        try checkPulses("pulse-120", [Case(44_100, .n2048, 1_024), Case(48_000, .n2048, 1_024),
                                      Case(44_100, .n512, 64), Case(48_000, .n8192, 4_096)],
                        portable: [Case(44_100, .n2048, 1_024)])
    }

    /// Varying pulse strength, at the default shape.
    func testPulse120AccentGivesOneOnsetPerPulseWithinOneHop() throws {
        try checkPulses("pulse-120-accent", [Case(44_100, .n2048, 1_024)])
    }

    /// Another tempo (pulses not aligned with 120 BPM): the largest size at N/8 and the smallest at N/4.
    func testPulse132GivesOneOnsetPerPulseWithinOneHop() throws {
        try checkPulses("pulse-132", [Case(44_100, .n8192, 1_024), Case(48_000, .n512, 128)])
    }

    func testQuieterPulsesAndUnitImpulsesWithinOneHop() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "pulse-120"))
        let backend = TestSupport.backends.first!
        var checked = 0
        for c in [Case(44_100, .n2048, 1_024), Case(48_000, .n512, 128)] {
            // 2 ms pulses at a 0.1 peak (−20 dBFS): the catalog's 0.5 pulses × 0.2.
            let quiet = try fixture.loop(sampleRate: c.rate, channels: 1).map { $0 * 0.2 }
            let quietOnsets = fixture.onsetFrames(sampleRate: c.rate)
            // Unit single-sample impulses at 1,234 + k·10,007 (not a whole number of hops).
            var impulses = [Float](repeating: 0, count: 10 * c.rate)
            var impulseOnsets: [Int64] = []
            for k in stride(from: 1_234, to: impulses.count, by: 10_007) { impulses[k] = 1; impulseOnsets.append(Int64(k)) }
            for (name, signal, onsets) in [("-20 dBFS pulses", quiet, quietOnsets), ("unit impulses", impulses, impulseOnsets)] {
                let run = try OnsetTestSupport.run(signal, size: c.size, hop: c.hop, rate: c.rate, backend: backend)
                let result = OnsetTestSupport.match(run.events, onsets: onsets, tolerance: c.hop)
                XCTAssertTrue(result.passed, "\(name) \(c): \(result)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 4)
        print("ANL-004 quieter pulses and unit impulses: \(checked) runs passed")
    }

    // MARK: US2 — silence and near-silence

    func testSilenceAndBelowFloorNoiseNeverProduceOnsets() throws {
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence"))
        let backend = TestSupport.backends.first!
        var frames = 0
        // The smallest size has the fewest bins per band, so noise reads highest there.
        let signals: [(String, Case, [Float])] = [
            ("silence", Case(44_100, .n2048, 1_024), try silence.loop(sampleRate: 44_100, channels: 1)),
            ("noise -80 dBFS", Case(44_100, .n512, 128), OnsetTestSupport.noise(seconds: 10, rate: 44_100, peak: 1e-4)),
            ("noise -70 dBFS", Case(48_000, .n512, 256), OnsetTestSupport.noise(seconds: 10, rate: 48_000, peak: 3e-4, seed: 0xBEEF)),
        ]
        for (name, c, signal) in signals {
            let run = try OnsetTestSupport.run(signal, size: c.size, hop: c.hop, rate: c.rate, backend: backend, recordFlux: true)
            let label = "\(name) \(c)"
            XCTAssertEqual(run.events.count, 0, label)
            XCTAssertTrue(run.fluxes.allSatisfy { $0.bitPattern == 0 }, label)
            XCTAssertGreaterThan(run.frames, 300, label)
            frames += run.frames
        }
        // −40 dBFS noise reaches above the floor in the top bands: the start may count, nothing after.
        let louder = Case(44_100, .n512, 256)
        let run = try OnsetTestSupport.run(OnsetTestSupport.noise(seconds: 10, rate: louder.rate, peak: 1e-2),
                                           size: louder.size, hop: louder.hop, rate: louder.rate, backend: backend)
        XCTAssertLessThanOrEqual(run.events.count, 1, "-40 dBFS noise \(louder)")
        if let event = run.events.first { XCTAssertLessThanOrEqual(abs(event.sampleIndex), Int64(louder.hop)) }
        // A sound that stops is not an onset: one pulse, then 1 s of silence.
        for rate in OnsetTestSupport.rates {
            var single = [Float](repeating: 0, count: rate + 2_000)
            for k in 1_000..<1_088 { single[k] = 0.5 }
            let run = try OnsetTestSupport.run(single, size: .n2048, hop: 1_024, rate: rate, backend: backend)
            XCTAssertEqual(run.events.count, 1)
            XCTAssertLessThanOrEqual(abs((run.events.first?.sampleIndex ?? -10_000) - 1_000), 1_024)
        }
        print("ANL-004 silence and below-floor noise: \(frames) frames, 0 events, every detection value exactly 0")
    }

    // MARK: US3 — steady and gliding tones

    func testSinesAndSweepsGiveAtMostTheStartEvent() throws {
        let backend = TestSupport.backends.first!
        let cases: [(String, Case)] = [
            ("sine-1k", Case(44_100, .n2048, 1_024)),
            ("sweep-log", Case(44_100, .n512, 128)),
            ("sweep-linear", Case(48_000, .n8192, 4_096)),
        ]
        var summary: [String] = []
        for (id, c) in cases {
            let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
            let stereo = try fixture.loop(sampleRate: c.rate, channels: 2)
            let mid = (0..<(stereo.count / 2)).map { (stereo[2 * $0] + stereo[2 * $0 + 1]) * 0.5 }
            let run = try OnsetTestSupport.run(mid, size: c.size, hop: c.hop, rate: c.rate, backend: backend)
            let label = "\(id) \(c)"
            // At most the start of the sound; never anything later (a sweep is not an onset).
            // A tone fades in through the window over size/hop frames, so at small hops and
            // large sizes its start may stay below the threshold (research ANL-004-D3).
            XCTAssertLessThanOrEqual(run.events.count, 1, "\(label): \(run.events.map(\.sampleIndex))")
            if let event = run.events.first { XCTAssertLessThanOrEqual(abs(event.sampleIndex), Int64(c.hop), label) }
            summary.append("\(label): \(run.events.count)")
        }
        print("ANL-004 sines and sweeps: \(cases.count) runs, 0 events after the start; start events: \(summary)")
    }

    /// One case per documented bound: N = 512 (≤ 25 per 10 s), 1,024 (≤ 4), 2,048 and up (exactly 1).
    func testLoudNoiseStaysWithinTheDocumentedBound() throws {
        let backend = TestSupport.backends.first!
        var counts: [String] = []
        for c in [Case(44_100, .n512, 256), Case(48_000, .n1024, 512), Case(44_100, .n8192, 4_096)] {
            let noise = OnsetTestSupport.noise(seconds: 10, rate: c.rate, peak: 0.3)
            let bound = c.size == .n512 ? 25 : c.size == .n1024 ? 4 : 1
            let run = try OnsetTestSupport.run(noise, size: c.size, hop: c.hop, rate: c.rate, backend: backend)
            let label = "-10 dBFS noise \(c)"
            XCTAssertGreaterThanOrEqual(run.events.count, 1, label)            // the start
            XCTAssertLessThanOrEqual(run.events.count, bound, label)
            if c.size.rawValue >= 2_048 { XCTAssertEqual(run.events.count, 1, label) }
            counts.append("\(c): \(run.events.count)")
        }
        print("ANL-004 loud noise events per 10 s: \(counts.joined(separator: ", "))")
    }

    // MARK: US4 — determinism and backends

    /// Two runs on the first backend are bit-identical, and vDSP and portable give the same events:
    /// −10 dBFS noise (48 kHz, 1,024 / 256, events after the start) and the accented pulses (varied
    /// strengths, default shape).
    func testRepeatedRunsAndBackendsGiveIdenticalEvents() throws {
        let c = Case(48_000, .n1024, 256)
        let signal = OnsetTestSupport.noise(seconds: 10, rate: c.rate, peak: 0.3)
        let accent = try OnsetTestSupport.loop("pulse-120-accent", rate: 44_100)
        var largest: Float = 0
        for (name, c, signal) in [("noise -10 dBFS", c, signal), ("pulse-120-accent", Case(44_100, .n2048, 1_024), accent)] {
            let label = "\(name) \(c)"
            var first: OnsetTestSupport.Run?
            for backend in TestSupport.backends {
                let a = try OnsetTestSupport.run(signal, size: c.size, hop: c.hop, rate: c.rate, backend: backend, recordFlux: true)
                XCTAssertFalse(a.events.isEmpty, label)
                if backend == TestSupport.backends.first {
                    let b = try OnsetTestSupport.run(signal, size: c.size, hop: c.hop, rate: c.rate, backend: backend, recordFlux: true)
                    XCTAssertEqual(a.events, b.events, "\(backend) \(label)")
                    XCTAssertEqual(a.events.map(\.strength.bitPattern), b.events.map(\.strength.bitPattern), "\(backend) \(label)")
                    XCTAssertEqual(a.fluxes.map(\.bitPattern), b.fluxes.map(\.bitPattern), "\(backend) \(label)")
                }
                if let reference = first {
                    XCTAssertEqual(a.events.map(\.sequence), reference.events.map(\.sequence), label)
                    XCTAssertEqual(a.events.map(\.sampleIndex), reference.events.map(\.sampleIndex), label)
                    XCTAssertEqual(a.events.map(\.frameIndex), reference.events.map(\.frameIndex), label)
                    for (x, y) in zip(a.events, reference.events) {
                        largest = max(largest, abs(x.strength - y.strength), abs(x.threshold - y.threshold))
                        XCTAssertLessThanOrEqual(abs(x.strength - y.strength), 1e-4, label)
                        XCTAssertLessThanOrEqual(abs(x.threshold - y.threshold), 1e-4, label)
                    }
                } else {
                    first = a
                }
            }
        }
        if SpectrumBackend.isAcceleratedAvailable {
            print("ANL-004 backends: identical events; largest |Δstrength|, |Δthreshold| \(largest)")
        } else {
            print("ANL-004 backend agreement: skipped (vDSP compiled out; portable path only); repeated runs identical")
        }
    }
}
