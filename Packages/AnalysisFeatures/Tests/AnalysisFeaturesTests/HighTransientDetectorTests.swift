// HighTransientDetectorTests.swift — ANL-009: the band transient detector configured as the high
// transient (6–16 kHz, 40 ms refractory, at most 12 events in any 1 s), contracts/high-transient.md
// C1-C3. It is NOT a hi-hat classifier: these tests only ever assert the band, never an instrument.
// Synthetic PCM on deterministic sample clocks with fixed seeds; a few representative cases (owner
// rule 7).
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class HighTransientDetectorTests: XCTestCase {
    /// The confidence threshold (as ANL-008's acceptance).
    static let confident: Float = 0.5
    /// The roadmap's "bounded event counts": the cap's 12 events in any 1 s.
    static let cap = 12

    // MARK: Configuration (T02)

    func testHighTransientDefaults() {
        let high = TransientDetectorConfiguration.highTransient
        XCTAssertEqual(high.band, .highTransient)
        XCTAssertEqual(high.sampleRate, 44_100)
        XCTAssertEqual(high.lowerFrequency, 6_000)
        XCTAssertEqual(high.upperFrequency, 16_000)
        XCTAssertEqual(high.floorDecibels, -70)
        XCTAssertEqual(high.dominanceDecibels, -6, "stricter than the kick's and the mid transient's −15 dB")
        XCTAssertEqual(high.baselineSeconds, 1.0)
        XCTAssertEqual(high.minimumRiseDecibels, 9)
        XCTAssertEqual(high.deviationMultiplier, 4)
        XCTAssertEqual(high.refractorySeconds, 0.04)
        XCTAssertEqual(high.envelopeSeconds, 0.05)
        XCTAssertEqual(high.breadthWeight, 1)
        XCTAssertEqual(high.confidenceMarginDecibels, 12)
        XCTAssertEqual(high.maximumEventsPerSecond, Self.cap)
        XCTAssertEqual(high.rateWindowSamples, 44_100)
        XCTAssertEqual(high.refractorySamples, 1_764)
        let expected: Float = Float(exp(-512.0 / 2_205.0))
        XCTAssertEqual(high.envelopeDecay(hop: 512), expected, accuracy: 1e-6)
        XCTAssertEqual(TransientDetectorConfiguration.kick.maximumEventsPerSecond, 0, "the kick is not capped")
        XCTAssertEqual(TransientDetectorConfiguration.midTransient.maximumEventsPerSecond, 0, "the mid transient is not capped")
        XCTAssertThrowsError(try TransientDetectorConfiguration(maximumEventsPerSecond: -1))
        XCTAssertThrowsError(try TransientDetectorConfiguration(maximumEventsPerSecond: 65))
        XCTAssertNoThrow(try TransientDetectorConfiguration(maximumEventsPerSecond: 64))
        XCTAssertNoThrow(try TransientDetectorConfiguration(sampleRate: 44_100, lowerFrequency: 6_000, upperFrequency: 22_050))
    }

    private func report(_ name: String, _ run: TransientTestSupport.Run, starts: [Int]) {
        let m = TransientTestSupport.match(run.events, starts: starts)
        let confidences = run.events.prefix(8).map { (e: TransientEvent) -> String in String(format: "%.2f", e.confidence) }
        print("ANL-009 fixture \(name): clicks \(starts.count), events \(run.events.count), hits \(m.hits), extras \(m.extras), max/1 s \(HighTransientFixture.maximumEventsPerSecond(run.events)), confidences \(confidences)")
    }

    // MARK: US1 — high-band clicks fire (T04)

    /// High-pass filtered noise clicks at known times fire once each, within one hop, with
    /// confidence ≥ 0.5, band `.highTransient` only; level-independent positions.
    func testHighBandClicksFireOnceEachWithinOneHop() throws {
        let train = HighTransientFixture.clickTrain(count: 4, dBFS: -12)
        let run = try HighTransientFixture.run(train.samples).run
        report("high clicks -12 dBFS", run, starts: train.starts)
        let m = TransientTestSupport.match(run.events, starts: train.starts)
        XCTAssertEqual(m.hits, 4)
        XCTAssertEqual(m.extras, 0)
        for event in run.events {
            XCTAssertEqual(event.band, .highTransient)
            XCTAssertGreaterThanOrEqual(event.confidence, Self.confident)
            XCTAssertLessThanOrEqual(event.confidence, 1)
            XCTAssertGreaterThan(event.strength, event.threshold)
        }
        for dBFS in [-30.0, -6.0] {
            let other = HighTransientFixture.clickTrain(count: 4, dBFS: dBFS)
            let r = try HighTransientFixture.run(other.samples).run
            report("high clicks \(dBFS) dBFS", r, starts: other.starts)
            XCTAssertEqual(r.events.map(\.sampleIndex), run.events.map(\.sampleIndex), "same positions at \(dBFS) dBFS")
        }
    }

    // MARK: US2 — bounded event counts (T05)

    /// Clicks every `spacing` samples for `seconds`, starting after the usual lead-in silence.
    private func clicks(spacing: Int, seconds: Int) -> (samples: [Float], starts: [Int]) {
        let rate = TransientFixture.rate
        let first = TransientFixture.firstStart
        let count = seconds * rate / spacing
        let starts = (0..<count).map { (i: Int) -> Int in first + i * spacing }
        var samples = [Float](repeating: 0, count: first + seconds * rate + rate / 10)
        HighTransientFixture.addClicks(into: &samples, amplitude: TransientFixture.amplitude(dBFS: -12), starts: starts,
                                       decaySeconds: 0.002, lengthSeconds: 0.01)
        return (samples, starts)
    }

    /// Dense clicks at 50 per second for 3 s, at the bus's geometry (2,048 / 512) and at the finest
    /// (512 / 128): never more than 12 events in any 1 s span, never more than 36 in all.
    func testDenseClicksAreCappedAtTheMaximumRate() throws {
        let dense = clicks(spacing: TransientFixture.rate / 50, seconds: 3)
        for (size, hop) in [(FFTSize.n2048, 512), (FFTSize.n512, 128)] {
            let capped = try HighTransientFixture.run(dense.samples, size: size, hop: hop)
            report("clicks 50/s, 3 s, N=\(size.rawValue) hop \(hop)", capped.run, starts: dense.starts)
            XCTAssertLessThanOrEqual(HighTransientFixture.maximumEventsPerSecond(capped.run.events), Self.cap)
            XCTAssertLessThanOrEqual(capped.run.events.count, 3 * Self.cap)
            XCTAssertGreaterThan(capped.run.events.count, 0, "the first click still fires")
        }
    }

    /// Clicks at 20 per second (outside the 40 ms refractory period) through 512-point spectra at
    /// hop 128, where the detector can follow them: uncapped, more than 12 fire in a second; capped,
    /// exactly 12 in a 1 s span and never more, and the suppressed ones are counted. The cap only
    /// removes events, never adds or moves one.
    func testTheCapLimitsFastClicksThatWouldOtherwiseFire() throws {
        let fast = clicks(spacing: TransientFixture.rate / 20, seconds: 2)
        let free = try HighTransientFixture.run(fast.samples, configuration: try HighTransientFixture.uncapped(), size: .n512, hop: 128)
        let capped = try HighTransientFixture.run(fast.samples, size: .n512, hop: 128)
        report("clicks 20/s uncapped, N=512 hop 128", free.run, starts: fast.starts)
        report("clicks 20/s capped, N=512 hop 128", capped.run, starts: fast.starts)
        XCTAssertGreaterThan(HighTransientFixture.maximumEventsPerSecond(free.run.events), Self.cap, "the input exercises the cap")
        XCTAssertEqual(HighTransientFixture.maximumEventsPerSecond(capped.run.events), Self.cap)
        XCTAssertGreaterThan(capped.detector.rateLimitedEvents, 0)
        XCTAssertEqual(capped.run.events.count + capped.detector.rateLimitedEvents, free.run.events.count)
        let freeSamples = Set(free.run.events.map(\.sampleIndex))
        XCTAssertTrue(capped.run.events.allSatisfy { (e: TransientEvent) -> Bool in freeSamples.contains(e.sampleIndex) })
    }

    /// Continuous high-band noise for 10 s: a bounded event count, at most 12 in any 1 s and at most
    /// 120 in all (the explicit bound); in practice far fewer, since the adaptive threshold follows
    /// the noise.
    func testContinuousHighNoiseGivesABoundedEventCount() throws {
        let samples = HighTransientFixture.continuousNoise(seconds: 10, dBFS: -12)
        for (size, hop) in [(FFTSize.n2048, 512), (FFTSize.n512, 128)] {
            let run = try HighTransientFixture.run(samples, size: size, hop: hop).run
            report("continuous high noise 10 s, N=\(size.rawValue) hop \(hop)", run, starts: [TransientFixture.firstStart])
            XCTAssertLessThanOrEqual(HighTransientFixture.maximumEventsPerSecond(run.events), Self.cap)
            XCTAssertLessThanOrEqual(run.events.count, 10 * Self.cap, "the explicit bound: 120 events in 10 s")
        }
    }

    // MARK: US2 — kicks and mid bursts (T05)

    func testKickAndMidBurstDoNotTriggerConfidently() throws {
        let starts = TransientFixture.starts(count: 4)
        let length = TransientFixture.firstStart + 4 * TransientFixture.periodSamples + TransientFixture.rate / 10
        var kick = [Float](repeating: 0, count: length)
        TransientFixture.addBursts(into: &kick, frequency: 60, amplitude: TransientFixture.amplitude(dBFS: -6), starts: starts)
        var mid = [Float](repeating: 0, count: length)
        MidTransientFixture.addNoiseBursts(into: &mid, amplitude: TransientFixture.amplitude(dBFS: -6), starts: starts)
        for (name, samples) in [("60 Hz kick -6 dBFS", kick), ("2 kHz mid burst -6 dBFS", mid)] {
            let run = try HighTransientFixture.run(samples).run
            report(name, run, starts: starts)
            XCTAssertFalse(run.events.contains { (e: TransientEvent) -> Bool in e.confidence >= Self.confident },
                           "\(name) is not a confident high transient")
        }
        let silence = [Float](repeating: 0, count: TransientFixture.rate * 3 / 10)
        var dither = silence
        TransientFixture.addNoise(into: &dither, peak: 1 / 32_768, seed: 7)
        for (name, samples) in [("silence", silence), ("dither", dither)] {
            let run = try HighTransientFixture.run(samples).run
            XCTAssertEqual(run.events.count, 0, name)
            XCTAssertEqual(run.envelopes.max() ?? 0, 0, name)
        }
    }

    // MARK: Refractory period and determinism (T05)

    func testRefractoryPeriodAndDeterminism() throws {
        let rate = TransientFixture.rate
        let first = TransientFixture.firstStart
        let amplitude: Float = TransientFixture.amplitude(dBFS: -12)
        // 1,536 samples ≈ 35 ms apart (inside 40 ms), through 512-point spectra at hop 128 so the level
        // reference does not hide the second click: one event, and two without the refractory period.
        var close = [Float](repeating: 0, count: rate * 2 / 5)
        HighTransientFixture.addClicks(into: &close, amplitude: amplitude, starts: [first, first + 3 * 512],
                                       decaySeconds: 0.002, lengthSeconds: 0.01)
        XCTAssertEqual(try HighTransientFixture.run(close, size: .n512, hop: 128).run.events.count, 1,
                       "the second click is inside the refractory period")
        let noRefractory = try HighTransientFixture.uncapped(refractorySeconds: 0)
        XCTAssertEqual(try HighTransientFixture.run(close, configuration: noRefractory, size: .n512, hop: 128).run.events.count, 2,
                       "without the refractory period both clicks fire")
        // 8 hops ≈ 93 ms apart, at the bus's geometry: two.
        var apart = [Float](repeating: 0, count: rate / 2)
        HighTransientFixture.addClicks(into: &apart, amplitude: amplitude, starts: [first, first + 8 * 512],
                                       decaySeconds: 0.002, lengthSeconds: 0.01)
        let a = try HighTransientFixture.run(apart).run
        XCTAssertEqual(a.events.count, 2)
        // Envelope: 1 at the event, then decaying with 50 ms.
        let peak = try XCTUnwrap(a.envelopes.firstIndex(of: 1))
        XCTAssertLessThan(a.envelopes[peak + 1], 1)
        XCTAssertGreaterThan(a.envelopes[peak + 1], 0.75)
        // Determinism: a second fresh detector gives identical events.
        let b = try HighTransientFixture.run(apart).run
        XCTAssertEqual(a.events, b.events)
        XCTAssertEqual(a.envelopes, b.envelopes)
    }

    // MARK: Bus (T06)

    func testThePipelinePublishesHighTransientEventsWithConfidence() throws {
        let train = HighTransientFixture.clickTrain(count: 3, dBFS: -12)
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
        let highs = r.events.filter { (e: AnalysisEvent) -> Bool in
            if case .transient(band: .highTransient, _, _, _, _) = e.kind { return true } else { return false }
        }
        print("ANL-009 bus: \(r.frames.count) frames, \(highs.count) high transient events at \(highs.map(\.eventSample)), starts \(train.starts)")
        XCTAssertEqual(highs.count, 3)
        XCTAssertEqual(r.frames.first?.highTransient, 0)
        for (event, start) in zip(highs, train.starts) {
            XCTAssertLessThanOrEqual(abs(event.eventSample - Int64(start)), Int64(TransientFixture.hop))
            guard case let .transient(_, strength, threshold, _, confidence) = event.kind else { continue }
            XCTAssertGreaterThan(strength, threshold)
            XCTAssertGreaterThanOrEqual(confidence, Self.confident)
            let index = try XCTUnwrap(r.frames.firstIndex { (f: AnalysisFrame) -> Bool in f.time == event.time })
            XCTAssertLessThan(r.frames[index].id, event.id, "the event follows its frame")
            XCTAssertEqual(r.frames[index].highTransientEnvelope, 1)
            XCTAssertEqual(r.frames[index].highTransientConfidence, confidence)
            XCTAssertEqual(r.frames[index].highTransient, confidence)
            XCTAssertLessThan(r.frames[index + 1].highTransient, confidence)
            XCTAssertGreaterThan(r.frames[index + 1].highTransient, 0)
        }
    }
}
