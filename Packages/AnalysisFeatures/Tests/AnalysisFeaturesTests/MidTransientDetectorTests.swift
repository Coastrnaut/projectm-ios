// MidTransientDetectorTests.swift — ANL-008: the band transient detector configured as the mid
// transient (1–4 kHz), and every event's confidence (contracts/mid-transient.md C1-C3). It is NOT a
// snare classifier: these tests only ever assert the band, never an instrument. Synthetic PCM on
// deterministic sample clocks with fixed seeds; a few representative cases (owner rule 7).
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class MidTransientDetectorTests: XCTestCase {
    /// The acceptance's confidence threshold.
    static let confident: Float = 0.5

    // MARK: Configuration (T02)

    func testMidTransientDefaults() {
        let mid = TransientDetectorConfiguration.midTransient
        XCTAssertEqual(mid.band, .midTransient)
        XCTAssertEqual(mid.sampleRate, 44_100)
        XCTAssertEqual(mid.lowerFrequency, 1_000)
        XCTAssertEqual(mid.upperFrequency, 4_000)
        XCTAssertEqual(mid.floorDecibels, -70)
        XCTAssertEqual(mid.dominanceDecibels, -15)
        XCTAssertEqual(mid.baselineSeconds, 1.0)
        XCTAssertEqual(mid.minimumRiseDecibels, 9)
        XCTAssertEqual(mid.deviationMultiplier, 4)
        XCTAssertEqual(mid.refractorySeconds, 0.07)
        XCTAssertEqual(mid.envelopeSeconds, 0.08)
        XCTAssertEqual(mid.breadthWeight, 1)
        XCTAssertEqual(mid.confidenceMarginDecibels, 12)
        XCTAssertEqual(mid.refractorySamples, 3_087)
        let expected: Float = Float(exp(-512.0 / 3_528.0))
        XCTAssertEqual(mid.envelopeDecay(hop: 512), expected, accuracy: 1e-6)
        XCTAssertEqual(TransientDetectorConfiguration.kick.breadthWeight, 0, "the kick's confidence ignores breadth")
        XCTAssertEqual(TransientDetectorConfiguration.kick.confidenceMarginDecibels, 12)
        XCTAssertThrowsError(try TransientDetectorConfiguration(breadthWeight: 1.5))
        XCTAssertThrowsError(try TransientDetectorConfiguration(breadthWeight: -0.1))
        XCTAssertThrowsError(try TransientDetectorConfiguration(confidenceMarginDecibels: 0))
        XCTAssertThrowsError(try TransientDetectorConfiguration(confidenceMarginDecibels: 41))
    }

    private func report(_ name: String, _ run: TransientTestSupport.Run, starts: [Int]) {
        let m = TransientTestSupport.match(run.events, starts: starts)
        let confidences = run.events.map { (e: TransientEvent) -> String in String(format: "%.2f", e.confidence) }
        print("ANL-008 fixture \(name): bursts \(starts.count), events \(run.events.count), hits \(m.hits), extras \(m.extras), confidences \(confidences)")
    }

    // MARK: US1 — the acceptance (T04)

    /// Roadmap acceptance: a mid-band impulse triggers an event (band only, no instrument identity),
    /// within one hop of the truth, with confidence ≥ 0.5; level-independent.
    func testMidBandBurstsFireOnceEachWithinOneHopWithConfidence() throws {
        let train = MidTransientFixture.burstTrain(count: 4, dBFS: -12)
        let run = try MidTransientFixture.run(train.samples)
        report("mid noise -12 dBFS", run, starts: train.starts)
        let m = TransientTestSupport.match(run.events, starts: train.starts)
        XCTAssertEqual(m.hits, 4)
        XCTAssertEqual(m.extras, 0)
        for event in run.events {
            XCTAssertEqual(event.band, .midTransient)
            XCTAssertGreaterThanOrEqual(event.confidence, Self.confident)
            XCTAssertLessThanOrEqual(event.confidence, 1)
            XCTAssertGreaterThan(event.strength, event.threshold)
        }
        for dBFS in [-30.0, -6.0] {
            let other = MidTransientFixture.burstTrain(count: 4, dBFS: dBFS)
            let r = try MidTransientFixture.run(other.samples)
            report("mid noise \(dBFS) dBFS", r, starts: other.starts)
            XCTAssertEqual(r.events.map(\.sampleIndex), run.events.map(\.sampleIndex), "same positions at \(dBFS) dBFS")
        }
    }

    // MARK: US2 — kicks, tones, silence (T05)

    func testLowKickDoesNotTriggerConfidently() throws {
        var samples = [Float](repeating: 0, count: TransientFixture.firstStart + 4 * TransientFixture.periodSamples + TransientFixture.rate / 10)
        let starts = TransientFixture.starts(count: 4)
        TransientFixture.addBursts(into: &samples, frequency: 60, amplitude: TransientFixture.amplitude(dBFS: -6), starts: starts)
        let run = try MidTransientFixture.run(samples)
        report("60 Hz kick -6 dBFS", run, starts: starts)
        XCTAssertFalse(run.events.contains { (e: TransientEvent) -> Bool in e.confidence >= Self.confident },
                       "a low-only kick is not a confident mid transient")
    }

    func testSteadyToneSilenceAndDitherDoNotFire() throws {
        let rate = TransientFixture.rate
        var tone = [Float](repeating: 0, count: rate)
        let start = TransientFixture.firstStart
        TransientFixture.addTone(into: &tone, frequency: 2_000, amplitude: TransientFixture.amplitude(dBFS: -12), start: start)
        let t = try MidTransientFixture.run(tone)
        report("2 kHz steady -12 dBFS", t, starts: [start])
        XCTAssertLessThanOrEqual(t.events.count, 1, "a steady tone fires at most at its onset")
        for event in t.events {
            XCTAssertLessThanOrEqual(abs(event.sampleIndex - Int64(start)), Int64(TransientFixture.hop))
            XCTAssertLessThan(event.confidence, Self.confident, "a tonal onset is not broadband")
        }
        let silence = [Float](repeating: 0, count: rate * 3 / 10)
        var dither = silence
        TransientFixture.addNoise(into: &dither, peak: 1 / 32_768, seed: 7)
        for (name, samples) in [("silence", silence), ("dither", dither)] {
            let run = try MidTransientFixture.run(samples)
            XCTAssertEqual(run.events.count, 0, name)
            XCTAssertEqual(run.envelopes.max() ?? 0, 0, name)
        }
    }

    func testRefractoryPeriodAndDeterminism() throws {
        let rate = TransientFixture.rate
        let first = TransientFixture.firstStart
        let amplitude: Float = TransientFixture.amplitude(dBFS: -12)
        // 4 hops ≈ 46 ms apart (inside 70 ms): one event; 11 hops ≈ 128 ms apart: two.
        var close = [Float](repeating: 0, count: rate * 2 / 5)
        MidTransientFixture.addNoiseBursts(into: &close, amplitude: amplitude, starts: [first, first + 4 * 512],
                                           decaySeconds: 0.005, lengthSeconds: 0.02)
        XCTAssertEqual(try MidTransientFixture.run(close).events.count, 1, "the second hit is inside the refractory period")
        var apart = [Float](repeating: 0, count: rate / 2)
        MidTransientFixture.addNoiseBursts(into: &apart, amplitude: amplitude, starts: [first, first + 11 * 512],
                                           decaySeconds: 0.005, lengthSeconds: 0.02)
        let a = try MidTransientFixture.run(apart)
        XCTAssertEqual(a.events.count, 2)
        // Envelope: 1 at the event, then decaying with 80 ms.
        let peak = try XCTUnwrap(a.envelopes.firstIndex(of: 1))
        XCTAssertLessThan(a.envelopes[peak + 1], 1)
        XCTAssertGreaterThan(a.envelopes[peak + 1], 0.8)
        // Determinism: a second fresh detector gives identical events.
        let b = try MidTransientFixture.run(apart)
        XCTAssertEqual(a.events, b.events)
        XCTAssertEqual(a.envelopes, b.envelopes)
    }

    // MARK: Bus (T06)

    func testThePipelinePublishesMidTransientEventsWithConfidence() throws {
        let train = MidTransientFixture.burstTrain(count: 3, dBFS: -12)
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        var stereo = [Float](repeating: 0, count: train.samples.count * 2)
        for (n, value) in train.samples.enumerated() { stereo[2 * n] = value; stereo[2 * n + 1] = value }
        BusFixture.feed(stereo, into: ring, chunkFrames: TransientFixture.hop) {
            pipeline.step()
            recorder.poll()
        }
        let r = recorder.recording
        assertOrdered(r)
        let mids = r.events.filter { (e: AnalysisEvent) -> Bool in
            if case .transient(band: .midTransient, _, _, _, _) = e.kind { return true } else { return false }
        }
        print("ANL-008 bus: \(r.frames.count) frames, \(mids.count) mid transient events at \(mids.map(\.eventSample)), starts \(train.starts)")
        XCTAssertEqual(mids.count, 3)
        XCTAssertEqual(r.frames.first?.midTransient, 0)
        for (event, start) in zip(mids, train.starts) {
            XCTAssertLessThanOrEqual(abs(event.eventSample - Int64(start)), Int64(TransientFixture.hop))
            guard case let .transient(_, strength, threshold, _, confidence) = event.kind else { continue }
            XCTAssertGreaterThan(strength, threshold)
            XCTAssertGreaterThanOrEqual(confidence, Self.confident)
            let index = try XCTUnwrap(r.frames.firstIndex { (f: AnalysisFrame) -> Bool in f.time == event.time })
            XCTAssertLessThan(r.frames[index].id, event.id, "the event follows its frame")
            XCTAssertEqual(r.frames[index].midTransientEnvelope, 1)
            XCTAssertEqual(r.frames[index].midTransientConfidence, confidence)
            XCTAssertEqual(r.frames[index].midTransient, confidence)
            XCTAssertLessThan(r.frames[index + 1].midTransient, confidence)
            XCTAssertGreaterThan(r.frames[index + 1].midTransient, 0)
        }
    }
}
