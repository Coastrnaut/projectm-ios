// TempoConfidenceAcceptanceTests.swift — ANL-006-T04: the roadmap acceptance, "Random-noise input
// never claims high-confidence BPM", with synthetic PCM through the real path the app uses:
// `NormalizedPCMRing`'s analysis tap → ANL-016 `AnalysisPipeline` (stepped synchronously) →
// `TempoSubscriptionReader` → `TempoSource` and `TempoConfidenceIndicator`, polled every 250 ms of
// audio (the app's poll) on the sample clock (research ANL-006-D6; ANL-006-S1 to S3). No wall
// clock. A few fixed seeds and lengths, not a sweep (owner rule 7).
import AnalysisFeatures
import AudioCore
import PerformanceControl
import PerformanceControlAnalysis
import Synchronization
import XCTest

final class TempoConfidenceAcceptanceTests: XCTestCase {
    private static let rate = 44_100

    /// One poll's observation.
    private struct Poll {
        var seconds: Double
        var state: TempoConfidenceState
        var bpm: Double?
        var rawConfidence: Double
        var snapshotOrigin: TempoOrigin
    }

    /// Runs interleaved stereo `samples` through the pipeline; one `Poll` per 250 ms of audio.
    private func run(_ samples: [Float]) throws -> [Poll] {
        let rate = Self.rate
        let ticks = Atomic<UInt64>(1_000_000_000)
        let pipeline = AnalysisPipeline(configuration: try AnalysisPipelineConfiguration(bandCount: .b16),
                                        clock: { () -> UInt64 in ticks.add(1_000_000, ordering: .relaxed).oldValue })
        let reader = TempoSubscriptionReader(subscription: try pipeline.subscribe(eventCapacity: 1_024),
                                             sampleRate: Double(rate))
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        var source = TempoSource()
        var indicator = TempoConfidenceIndicator()
        var polls: [Poll] = []
        let pollFrames: Int = rate / 4
        let frames: Int = samples.count / 2
        var offset = 0
        var nextPoll: Int = pollFrames
        samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            while offset < frames {
                let n: Int = min(2_048, frames - offset)
                ring.write(buffer.baseAddress! + 2 * offset, frames: n)
                offset += n
                pipeline.step()
                guard offset >= nextPoll else { continue }
                nextPoll += pollFrames
                let estimate: TempoEstimate? = reader.poll()
                let nanoseconds: UInt64 = UInt64(offset) * 1_000_000_000 / UInt64(rate)
                source.updateEstimate(estimate)
                indicator.update(estimate, at: nanoseconds)
                let seconds: Double = Double(offset) / Double(rate)
                polls.append(Poll(seconds: seconds, state: indicator.state, bpm: indicator.bpm,
                                  rawConfidence: estimate?.confidence ?? 0, snapshotOrigin: source.snapshot.origin))
            }
        }
        pipeline.detach()
        return polls
    }

    // MARK: Inputs

    /// Mono → interleaved stereo.
    private func stereo(_ mono: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: 2 * mono.count)
        for i in 0..<mono.count {
            out[2 * i] = mono[i]
            out[2 * i + 1] = mono[i]
        }
        return out
    }

    /// Fixed-seed uniform white noise in [-1, 1) from a 64-bit LCG.
    private func white(count: Int, seed: UInt64) -> [Float] {
        var state: UInt64 = seed
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit: Double = Double(state >> 11) / Double(UInt64(1) << 53)
            out[i] = Float(2 * unit - 1)
        }
        return out
    }

    /// Scales to the given peak.
    private func normalized(_ signal: [Float], peak: Float) -> [Float] {
        let largest: Float = signal.map { (x: Float) -> Float in abs(x) }.max() ?? 0
        guard largest > 0 else { return signal }
        let gain: Float = peak / largest
        return signal.map { (x: Float) -> Float in x * gain }
    }

    /// Pink noise: the white LCG through Paul Kellet's economy filter (−3 dB per octave).
    private func pink(count: Int, seed: UInt64) -> [Float] {
        let source = white(count: count, seed: seed)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let x: Float = source[i]
            b0 = 0.99765 * b0 + x * 0.0990460
            b1 = 0.96300 * b1 + x * 0.2965164
            b2 = 0.57000 * b2 + x * 1.0526913
            let sum: Float = b0 + b1 + b2
            out[i] = sum + x * 0.1848
        }
        return out
    }

    /// Random noise bursts: 30 ms of white noise at random times (exponential gaps of mean 1/3 s
    /// plus 50 ms, ANL-004's minimum onset interval) on silence: many onsets, no tempo.
    private func bursts(count: Int, seed: UInt64) -> [Float] {
        let noise = white(count: count, seed: seed &+ 100)
        var state: UInt64 = seed
        var out = [Float](repeating: 0, count: count)
        let burst: Int = 30 * Self.rate / 1_000
        var t: Double = 0
        while true {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit: Double = (Double(state >> 11) + 0.5) / Double(UInt64(1) << 53)
            let gap: Double = -log(unit) / 3 + 0.05
            t += gap
            let start: Int = Int(t * Double(Self.rate))
            guard start < count else { return out }
            let end: Int = min(count, start + burst)
            for i in start..<end { out[i] = 0.5 * noise[i] }
        }
    }

    private func pulses(bpm: Double, seconds: Double) throws -> [Float] {
        let generator = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: bpm, widthSeconds: 0.002, amplitude: 0.5)),
                                          format: try ToneFormat(sampleRate: Self.rate, channels: 2))
        let frames: Int = Int(seconds * Double(Self.rate))
        return generator.interleaved(frames: frames)
    }

    // MARK: ANL-006-S1 (roadmap acceptance)

    /// Runs each input; asserts never stable, confidence < enter, never an estimated snapshot.
    private func checkNeverConfident(_ inputs: [(String, [Float])], seconds: Int) throws {
        let enter: Double = TempoConfidenceRules.standard.enterConfidence
        var report: [String] = []
        for (name, samples) in inputs {
            let polls = try run(samples)
            XCTAssertEqual(polls.count, 4 * seconds, name)
            let highest: Double = polls.map { (p: Poll) -> Double in p.rawConfidence }.max() ?? 0
            let states = Set(polls.map { (p: Poll) -> TempoConfidenceState in p.state })
            XCTAssertFalse(states.contains(.stable), "\(name) reached stable")
            XCTAssertLessThan(highest, enter, "\(name) confidence \(highest)")
            XCTAssertFalse(polls.contains { (p: Poll) -> Bool in p.snapshotOrigin == .estimated },
                           "\(name) produced an estimated tempo snapshot")
            let shown: [String] = states.map { (s: TempoConfidenceState) -> String in s.rawValue }.sorted()
            report.append("\(name): max confidence \(highest), states \(shown)")
        }
        print("ANL-006 noise: " + report.joined(separator: "; "))
    }

    /// Stationary white and pink noise (peak 0.5) and silence, 10 s each.
    func testNoiseAndSilenceNeverClaimAConfidentTempo() throws {
        let seconds = 10
        let count: Int = seconds * Self.rate
        var inputs: [(String, [Float])] = []
        for seed in [UInt64(1), 2] {
            inputs.append(("white seed \(seed)", stereo(normalized(white(count: count, seed: seed), peak: 0.5))))
        }
        for seed in [UInt64(4), 5] {
            inputs.append(("pink seed \(seed)", stereo(normalized(pink(count: count, seed: seed), peak: 0.5))))
        }
        inputs.append(("silence", [Float](repeating: 0, count: 2 * count)))
        try checkNeverConfident(inputs, seconds: seconds)
    }

    /// Noise bursts at random times (many onsets, no tempo), 12 s each: the inputs that do give
    /// ANL-005 estimates, so the indicator's thresholds are exercised.
    func testRandomNoiseBurstsNeverClaimAConfidentTempo() throws {
        let seconds = 12
        let count: Int = seconds * Self.rate
        let inputs: [(String, [Float])] = [UInt64(6), 7, 8].map { (seed: UInt64) -> (String, [Float]) in
            ("noise bursts seed \(seed)", stereo(bursts(count: count, seed: seed)))
        }
        try checkNeverConfident(inputs, seconds: seconds)
    }

    // MARK: ANL-006-S2

    private func checkStable(bpm: Double) throws {
        let polls = try run(try pulses(bpm: bpm, seconds: 12))
        let first = polls.firstIndex { (p: Poll) -> Bool in
            p.state == .stable && abs((p.bpm ?? 0) - bpm) <= 1
        }
        let index = try XCTUnwrap(first, "\(bpm) BPM never stable")
        XCTAssertLessThanOrEqual(polls[index].seconds, 10, "\(bpm) BPM stable at \(polls[index].seconds) s")
        let after = polls[index...]
        XCTAssertTrue(after.allSatisfy { (p: Poll) -> Bool in p.state == .stable && abs((p.bpm ?? 0) - bpm) <= 1 },
                      "\(bpm) BPM did not stay stable")
        print("ANL-006 pulses \(bpm) BPM: stable at \(polls[index].seconds) s, confidence there \(polls[index].rawConfidence)")
    }

    func testPulses120BecomeStable() throws { try checkStable(bpm: 120) }

    func testPulses90BecomeStable() throws { try checkStable(bpm: 90) }

    // MARK: ANL-006-S3

    func testATempoChangeLeavesStableAndReturnsAtTheNewTempo() throws {
        let samples = try pulses(bpm: 120, seconds: 12) + pulses(bpm: 90, seconds: 14)
        let polls = try run(samples)
        let change: Double = 12
        let before = polls.filter { (p: Poll) -> Bool in p.seconds <= change }
        XCTAssertEqual(before.last?.state, .stable)
        XCTAssertEqual(before.last?.bpm ?? 0, 120, accuracy: 1)
        let after = polls.filter { (p: Poll) -> Bool in p.seconds > change }
        let left = after.firstIndex { (p: Poll) -> Bool in p.state != .stable }
        let leftIndex = try XCTUnwrap(left, "never left stable after the change")
        let held = after[..<leftIndex]
        XCTAssertTrue(held.allSatisfy { (p: Poll) -> Bool in abs((p.bpm ?? 0) - 120) <= 3.6 },
                      "while still stable the readout never shows the new tempo as stable")
        let back = after[leftIndex...].firstIndex { (p: Poll) -> Bool in
            p.state == .stable && abs((p.bpm ?? 0) - 90) <= 1
        }
        let backIndex = try XCTUnwrap(back, "never stable at 90")
        XCTAssertLessThanOrEqual(after[backIndex].seconds - change, 12)
        let passed: [String] = after[leftIndex..<backIndex].map { (p: Poll) -> String in p.state.rawValue }
        print("ANL-006 change 120 → 90: left stable \(after[leftIndex].seconds - change) s after the change "
              + "(\(after[leftIndex].state.rawValue)), stable at 90 after \(after[backIndex].seconds - change) s; "
              + "states between: \(Set(passed).sorted())")
    }
}
