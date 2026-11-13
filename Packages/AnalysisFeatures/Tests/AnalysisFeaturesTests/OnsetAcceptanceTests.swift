// OnsetAcceptanceTests.swift — the roadmap acceptance of ANL-004 against the AUD-016 fixtures
// (ANL-004-T10, T11, T13, T15, T17; ANL-004-R15, R17, S1 to S5):
//   "Impulse train produces onset events within one analysis hop and no false silence events."
// "Within one hop": each catalog onset frame is matched by exactly one event with
// |event.sampleIndex − onset| ≤ hop, and no event is left unmatched (spec Clarifications).
// Streams use the `.silence` lead-in and a fixed clock; every run is a whole 10 s loop.
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class OnsetAcceptanceTests: XCTestCase {
    private let pulseFixtures = ["pulse-120", "pulse-120-accent", "pulse-132"]

    private func hops(_ size: FFTSize, _ divisors: [Int] = OnsetTestSupport.hopDivisors) -> [Int] {
        divisors.map { size.rawValue / $0 }
    }

    // MARK: US1 — pulse trains

    /// One pulse fixture × 2 rates × 5 sizes × hops N/2, N/4, N/8 on the build's first backend (vDSP
    /// where compiled in, else portable): 30 combinations. Where vDSP exists, the portable backend
    /// repeats hops N/2 and N/4 (20 combinations); the portable-only build (-DANALYSIS_NO_ACCELERATE,
    /// the Linux shape) runs all 30 on the portable path. Split per fixture to keep each test short.
    private func checkPulseFixture(_ id: String) throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
        var combinations = 0
        var largestRatio = 0.0
        for rate in OnsetTestSupport.rates {
            let loop = try fixture.loop(sampleRate: rate, channels: 1)
            let onsets = fixture.onsetFrames(sampleRate: rate)
            for backend in TestSupport.backends {
                let primary = backend == TestSupport.backends.first
                for size in FFTSize.allCases {
                    for hop in hops(size, primary ? OnsetTestSupport.hopDivisors : [2, 4]) {
                        let run = try OnsetTestSupport.run(loop, size: size, hop: hop, rate: rate, backend: backend)
                        let result = OnsetTestSupport.match(run.events, onsets: onsets, tolerance: hop)
                        let label = "\(backend) \(id) \(rate) N=\(size.rawValue) hop=\(hop)"
                        XCTAssertTrue(result.passed, "\(label): \(result)")
                        XCTAssertEqual(run.events.count, onsets.count, label)
                        largestRatio = max(largestRatio, Double(result.maxError) / Double(hop))
                        if primary {
                            combinations += 1
                            print("ANL-004 matrix: \(id) | \(rate) | \(size.rawValue) | \(hop) | \(result.onsets) | \(result.events) | \(result.misses) | \(result.unmatched) | \(result.maxError)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(combinations, 30)
        print("ANL-004 pulses \(id): \(combinations) combinations on \(TestSupport.backends.first!), backends \(TestSupport.backends); largest |error|/hop \(largestRatio)")
    }

    func testPulse120GivesOneOnsetPerPulseWithinOneHop() throws { try checkPulseFixture("pulse-120") }
    func testPulse120AccentGivesOneOnsetPerPulseWithinOneHop() throws { try checkPulseFixture("pulse-120-accent") }
    func testPulse132GivesOneOnsetPerPulseWithinOneHop() throws { try checkPulseFixture("pulse-132") }

    func testQuieterPulsesAndUnitImpulsesWithinOneHop() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "pulse-120"))
        let backend = TestSupport.backends.first!
        var checked = 0
        for rate in OnsetTestSupport.rates {
            // 2 ms pulses at a 0.1 peak (−20 dBFS): the catalog's 0.5 pulses × 0.2.
            let quiet = try fixture.loop(sampleRate: rate, channels: 1).map { $0 * 0.2 }
            let quietOnsets = fixture.onsetFrames(sampleRate: rate)
            // Unit single-sample impulses at 1,234 + k·10,007 (not a whole number of hops).
            var impulses = [Float](repeating: 0, count: 10 * rate)
            var impulseOnsets: [Int64] = []
            for k in stride(from: 1_234, to: impulses.count, by: 10_007) { impulses[k] = 1; impulseOnsets.append(Int64(k)) }
            for size in FFTSize.allCases {
                for hop in hops(size, [2, 4]) {
                    for (name, signal, onsets) in [("-20 dBFS pulses", quiet, quietOnsets), ("unit impulses", impulses, impulseOnsets)] {
                        let run = try OnsetTestSupport.run(signal, size: size, hop: hop, rate: rate, backend: backend)
                        let result = OnsetTestSupport.match(run.events, onsets: onsets, tolerance: hop)
                        XCTAssertTrue(result.passed, "\(name) \(rate) N=\(size.rawValue) hop=\(hop): \(result)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 40)
        print("ANL-004 quieter pulses and unit impulses: \(checked) combinations passed")
    }

    // MARK: US2 — silence and near-silence

    func testSilenceAndBelowFloorNoiseNeverProduceOnsets() throws {
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence"))
        let backend = TestSupport.backends.first!
        var frames = 0
        for rate in OnsetTestSupport.rates {
            let signals: [(String, [Float])] = [
                ("silence", try silence.loop(sampleRate: rate, channels: 1)),
                ("noise -80 dBFS", OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 1e-4)),
                ("noise -70 dBFS", OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 3e-4, seed: 0xBEEF)),
            ]
            for (name, signal) in signals {
                for size in FFTSize.allCases {
                    for hop in hops(size, [2, 4]) {
                        let run = try OnsetTestSupport.run(signal, size: size, hop: hop, rate: rate, backend: backend, recordFlux: true)
                        let label = "\(name) \(rate) N=\(size.rawValue) hop=\(hop)"
                        XCTAssertEqual(run.events.count, 0, label)
                        XCTAssertTrue(run.fluxes.allSatisfy { $0.bitPattern == 0 }, label)
                        frames += run.frames
                    }
                }
            }
            // −40 dBFS noise reaches above the floor in the top bands: the start may count, nothing after.
            let louder = OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 1e-2)
            for size in FFTSize.allCases {
                for hop in hops(size, [2, 4]) {
                    let run = try OnsetTestSupport.run(louder, size: size, hop: hop, rate: rate, backend: backend)
                    XCTAssertLessThanOrEqual(run.events.count, 1, "-40 dBFS noise \(rate) N=\(size.rawValue) hop=\(hop)")
                    if let event = run.events.first { XCTAssertLessThanOrEqual(abs(event.sampleIndex), Int64(hop)) }
                }
            }
            // A sound that stops is not an onset: one pulse, then 1 s of silence.
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
        var runs = 0
        var summary: [String: Int] = [:]
        for fixture in ReferenceToneCatalog.fixtures {
            switch fixture.signal {
            case .sine, .sweep: break
            default: continue
            }
            for rate in OnsetTestSupport.rates {
                let stereo = try fixture.loop(sampleRate: rate, channels: 2)
                let mid = (0..<(stereo.count / 2)).map { (stereo[2 * $0] + stereo[2 * $0 + 1]) * 0.5 }
                for size in FFTSize.allCases {
                    for hop in hops(size, [2, 4]) {
                        let run = try OnsetTestSupport.run(mid, size: size, hop: hop, rate: rate, backend: backend)
                        let label = "\(fixture.id) \(rate) N=\(size.rawValue) hop=\(hop)"
                        // At most the start of the sound; never anything later (a sweep is not an onset).
                        // A tone fades in through the window over size/hop frames, so at small hops and
                        // large sizes its start may stay below the threshold (research ANL-004-D3).
                        XCTAssertLessThanOrEqual(run.events.count, 1, "\(label): \(run.events.map(\.sampleIndex))")
                        if let event = run.events.first { XCTAssertLessThanOrEqual(abs(event.sampleIndex), Int64(hop), label) }
                        summary[fixture.id, default: 0] += run.events.count
                        runs += 1
                    }
                }
            }
        }
        XCTAssertEqual(runs, 6 * 2 * 10)
        print("ANL-004 sines and sweeps: \(runs) runs, 0 events after the start; start events per fixture (of 20 runs): \(summary.sorted { $0.key < $1.key })")
    }

    func testLoudNoiseStaysWithinTheDocumentedBound() throws {
        let backend = TestSupport.backends.first!
        var counts: [String] = []
        for rate in OnsetTestSupport.rates {
            let noise = OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 0.3)
            for size in FFTSize.allCases {
                let bound = size == .n512 ? 25 : size == .n1024 ? 4 : 1
                for hop in hops(size, [2, 4]) {
                    let run = try OnsetTestSupport.run(noise, size: size, hop: hop, rate: rate, backend: backend)
                    let label = "-10 dBFS noise \(rate) N=\(size.rawValue) hop=\(hop)"
                    XCTAssertGreaterThanOrEqual(run.events.count, 1, label)            // the start
                    XCTAssertLessThanOrEqual(run.events.count, bound, label)
                    if size.rawValue >= 2_048 { XCTAssertEqual(run.events.count, 1, label) }
                    counts.append("\(rate)/\(size.rawValue)/\(hop): \(run.events.count)")
                }
            }
        }
        print("ANL-004 loud noise events per 10 s (rate/size/hop): \(counts.joined(separator: ", "))")
    }

    // MARK: US4 — determinism and backends

    func testRepeatedRunsAndBackendsGiveIdenticalEvents() throws {
        var inputs: [(String, Int, [Float])] = []
        for rate in OnsetTestSupport.rates {
            for id in pulseFixtures + ["sweep-log"] {
                inputs.append((id, rate, try OnsetTestSupport.loop(id, rate: rate)))
            }
            inputs.append(("noise -10 dBFS", rate, OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 0.3)))
        }
        let shapes: [(FFTSize, Int)] = [(.n2048, 1_024), (.n1024, 256)]
        var compared = 0
        var largest: Float = 0
        for (name, rate, signal) in inputs {
            for (size, hop) in shapes {
                let label = "\(name) \(rate) N=\(size.rawValue) hop=\(hop)"
                var first: OnsetTestSupport.Run?
                for backend in TestSupport.backends {
                    let a = try OnsetTestSupport.run(signal, size: size, hop: hop, rate: rate, backend: backend, recordFlux: true)
                    let b = try OnsetTestSupport.run(signal, size: size, hop: hop, rate: rate, backend: backend, recordFlux: true)
                    XCTAssertEqual(a.events, b.events, "\(backend) \(label)")
                    XCTAssertEqual(a.events.map(\.strength.bitPattern), b.events.map(\.strength.bitPattern), "\(backend) \(label)")
                    XCTAssertEqual(a.fluxes.map(\.bitPattern), b.fluxes.map(\.bitPattern), "\(backend) \(label)")
                    if let reference = first {
                        XCTAssertEqual(a.events.map(\.sequence), reference.events.map(\.sequence), label)
                        XCTAssertEqual(a.events.map(\.sampleIndex), reference.events.map(\.sampleIndex), label)
                        XCTAssertEqual(a.events.map(\.frameIndex), reference.events.map(\.frameIndex), label)
                        for (x, y) in zip(a.events, reference.events) {
                            largest = max(largest, abs(x.strength - y.strength), abs(x.threshold - y.threshold))
                            XCTAssertLessThanOrEqual(abs(x.strength - y.strength), 1e-4, label)
                            XCTAssertLessThanOrEqual(abs(x.threshold - y.threshold), 1e-4, label)
                        }
                        compared += 1
                    } else {
                        first = a
                    }
                }
            }
        }
        if SpectrumBackend.isAcceleratedAvailable {
            XCTAssertEqual(compared, inputs.count * shapes.count)
            print("ANL-004 backends: \(compared) runs with identical events; largest |Δstrength|, |Δthreshold| \(largest)")
        } else {
            print("ANL-004 backend agreement: skipped (vDSP compiled out; portable path only); repeated runs identical")
        }
    }
}
