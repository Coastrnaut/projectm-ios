// KickDetectorTests.swift — ANL-007: the band transient detector configured as the kick
// (contracts/transient-detector.md C1-C3). Synthetic PCM on deterministic sample clocks with fixed
// seeds; a few representative cases (owner rule 7). No Accelerate import, no C stdio globals.
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class KickDetectorTests: XCTestCase {
    // MARK: Configuration (T02)

    func testKickDefaults() {
        let kick = TransientDetectorConfiguration.kick
        XCTAssertEqual(kick.band, .kick)
        XCTAssertEqual(kick.sampleRate, 44_100)
        XCTAssertEqual(kick.lowerFrequency, 40)
        XCTAssertEqual(kick.upperFrequency, 150)
        XCTAssertEqual(kick.floorDecibels, -70)
        XCTAssertEqual(kick.dominanceDecibels, -15)
        XCTAssertEqual(kick.baselineSeconds, 1.0)
        XCTAssertEqual(kick.minimumRiseDecibels, 9)
        XCTAssertEqual(kick.deviationMultiplier, 4)
        XCTAssertEqual(kick.refractorySeconds, 0.1)
        XCTAssertEqual(kick.envelopeSeconds, 0.1)
        XCTAssertEqual(kick.baselineFrames(hop: 512), 86)
        XCTAssertEqual(kick.baselineFrames(hop: 64), 128, "clamped to the window capacity")
        XCTAssertEqual(kick.refractorySamples, 4_410)
        let decay: Float = kick.envelopeDecay(hop: 512)
        let expected: Float = Float(exp(-512.0 / 4_410.0))
        XCTAssertEqual(decay, expected, accuracy: 1e-6)
        XCTAssertEqual(try TransientDetectorConfiguration(), kick)
    }

    func testInvalidConfigurationsThrow() {
        XCTAssertThrowsError(try TransientDetectorConfiguration(sampleRate: 4_000))
        XCTAssertThrowsError(try TransientDetectorConfiguration(lowerFrequency: 10))
        XCTAssertThrowsError(try TransientDetectorConfiguration(lowerFrequency: 150, upperFrequency: 150))
        XCTAssertThrowsError(try TransientDetectorConfiguration(upperFrequency: 30_000))
        XCTAssertThrowsError(try TransientDetectorConfiguration(floorDecibels: -10))
        XCTAssertThrowsError(try TransientDetectorConfiguration(dominanceDecibels: 3))
        XCTAssertThrowsError(try TransientDetectorConfiguration(baselineSeconds: 0))
        XCTAssertThrowsError(try TransientDetectorConfiguration(minimumRiseDecibels: 0))
        XCTAssertThrowsError(try TransientDetectorConfiguration(deviationMultiplier: -1))
        XCTAssertThrowsError(try TransientDetectorConfiguration(refractorySeconds: 3))
        XCTAssertThrowsError(try TransientDetectorConfiguration(envelopeSeconds: 0))
        do {
            _ = try TransientDetectorConfiguration(lowerFrequency: 200, upperFrequency: 100)
            XCTFail("expected a range error")
        } catch {
            XCTAssertEqual(error, .invalidFrequencyRange(lower: 200, upper: 100))
        }
    }

    // MARK: US1 — low pulses fire, high and mid pulses do not (T04)

    private func report(_ name: String, _ run: TransientTestSupport.Run, starts: [Int]) {
        let m = TransientTestSupport.match(run.events, starts: starts)
        let peak: Float = run.levels.max() ?? 0
        print("ANL-007 fixture \(name): pulses \(starts.count), events \(run.events.count), hits \(m.hits), misses \(m.misses), extras \(m.extras), peak level \(peak) dB")
    }

    func testLowPulsesFireOncePerPulseAtAnyLevelAndHighOrMidPulsesNever() throws {
        // US1: one event per low pulse, within one hop of its start.
        let loud = TransientFixture.kickTrain(count: 4, dBFS: -6)
        let low = try TransientTestSupport.run(loud.samples)
        report("55 Hz -6 dBFS", low, starts: loud.starts)
        let m = TransientTestSupport.match(low.events, starts: loud.starts)
        XCTAssertEqual(m.hits, 4)
        XCTAssertEqual(m.extras, 0)
        XCTAssertEqual(low.events.map(\.sequence), Array(1...4))
        XCTAssertTrue(low.events.allSatisfy { (e: TransientEvent) -> Bool in e.band == .kick && e.strength > e.threshold })

        // US2 (T05): the same pattern 24 dB quieter gives the same events.
        let quiet = TransientFixture.kickTrain(count: 4, dBFS: -30)
        let q = try TransientTestSupport.run(quiet.samples)
        report("55 Hz -30 dBFS", q, starts: quiet.starts)
        XCTAssertEqual(q.events.map(\.sampleIndex), low.events.map(\.sampleIndex), "same hits at -30 and -6 dBFS")

        // High (5 kHz) and mid (1 kHz) pulses, alternating, at the loud level: never a kick.
        var other = [Float](repeating: 0, count: loud.samples.count)
        let amplitude: Float = TransientFixture.amplitude(dBFS: -6)
        TransientFixture.addBursts(into: &other, frequency: 5_000, amplitude: amplitude, starts: [loud.starts[0], loud.starts[2]])
        TransientFixture.addBursts(into: &other, frequency: 1_000, amplitude: amplitude, starts: [loud.starts[1], loud.starts[3]])
        let run = try TransientTestSupport.run(other)
        report("5 kHz and 1 kHz -6 dBFS", run, starts: loud.starts)
        XCTAssertEqual(run.events.count, 0, "high and mid pulses are not kicks")
        XCTAssertEqual(run.envelopes.max() ?? 0, 0)
    }

    func testKickUnderALoudSustainedHighLayerIsStillDetected() throws {
        var kick = TransientFixture.kickTrain(count: 4, dBFS: -12)
        let pad: Float = TransientFixture.amplitude(dBFS: -6)
        TransientFixture.addTone(into: &kick.samples, frequency: 2_000, amplitude: pad)
        TransientFixture.addTone(into: &kick.samples, frequency: 3_300, amplitude: pad)
        TransientFixture.addNoise(into: &kick.samples, peak: TransientFixture.amplitude(dBFS: -30), seed: 0xC0FFEE)
        let run = try TransientTestSupport.run(kick.samples)
        report("55 Hz -12 dBFS under pad -6 dBFS x2 + noise -30 dBFS", run, starts: kick.starts)
        let m = TransientTestSupport.match(run.events, starts: kick.starts)
        XCTAssertEqual(m.hits, 4)
        XCTAssertEqual(m.extras, 0)
    }

    // MARK: US3 — no false kicks (T06)

    func testSustainedBassFiresAtMostOnceAtItsStart() throws {
        var samples = [Float](repeating: 0, count: 6 * TransientFixture.rate / 5)
        let start = TransientFixture.firstStart
        TransientFixture.addTone(into: &samples, frequency: 60, amplitude: TransientFixture.amplitude(dBFS: -12), start: start)
        let run = try TransientTestSupport.run(samples)
        report("60 Hz sustained -12 dBFS", run, starts: [start])
        XCTAssertLessThanOrEqual(run.events.count, 1)
        for event in run.events { XCTAssertLessThanOrEqual(abs(event.sampleIndex - Int64(start)), 512) }
    }

    func testSilenceDitherAndWhiteNoiseNeverFire() throws {
        let rate = TransientFixture.rate
        let silence = [Float](repeating: 0, count: rate * 3 / 10)
        var dither = silence
        let lsb: Float = 1 / 32_768
        TransientFixture.addNoise(into: &dither, peak: lsb, seed: 7)
        var white = [Float](repeating: 0, count: rate * 6 / 5)
        TransientFixture.addNoise(into: &white, peak: TransientFixture.amplitude(dBFS: -6), seed: 0x5EED)
        for (name, samples) in [("silence", silence), ("dither", dither), ("white -6 dBFS", white)] {
            let run = try TransientTestSupport.run(samples)
            report(name, run, starts: [])
            XCTAssertEqual(run.events.count, 0, name)
            XCTAssertEqual(run.envelopes.max() ?? 0, 0, name)
        }
    }

    func testRefractoryPeriodAndReset() throws {
        let rate = TransientFixture.rate
        var close = [Float](repeating: 0, count: rate * 2 / 5)
        let first = TransientFixture.firstStart
        // 60 ms apart (inside 100 ms): one event; 150 ms apart (hop-aligned, 13 hops): two.
        TransientFixture.addBursts(into: &close, frequency: 55, amplitude: 0.5, starts: [first, first + 5 * 512],
                                   decaySeconds: 0.01, lengthSeconds: 0.05)
        let inside = try TransientTestSupport.run(close)
        XCTAssertEqual(inside.events.count, 1, "the second hit is inside the refractory period")
        var apart = [Float](repeating: 0, count: rate / 2)
        TransientFixture.addBursts(into: &apart, frequency: 55, amplitude: 0.5, starts: [first, first + 13 * 512],
                                   decaySeconds: 0.01, lengthSeconds: 0.05)
        let detector = BandTransientDetector()
        let outside = try TransientTestSupport.run(apart, detector: detector)
        XCTAssertEqual(outside.events.count, 2)
        // Envelope: 1 at the event, then decaying.
        let peak = try XCTUnwrap(outside.envelopes.firstIndex(of: 1))
        XCTAssertLessThan(outside.envelopes[peak + 1], 1)
        XCTAssertGreaterThan(outside.envelopes[peak + 1], 0.8)

        detector.reset()
        XCTAssertEqual(detector.envelope, 0)
        let again = try TransientTestSupport.run(apart, detector: detector)
        XCTAssertEqual(again.events.map(\.sequence), [3, 4], "the sequence continues after reset")

        // Ignored frames: another rate, a wrong magnitude count.
        let magnitudes = [Float](repeating: 1, count: FFTSize.n2048.binCount)
        let wrongRate = SpectrumFrame(index: 0, size: .n2048, sampleRate: 48_000, timestampNanoseconds: 0, hop: 512)
        XCTAssertNil(detector.process(wrongRate, magnitudes: magnitudes))
        let frame = SpectrumFrame(index: 0, size: .n2048, sampleRate: 44_100, timestampNanoseconds: 0, hop: 512)
        XCTAssertNil(detector.process(frame, magnitudes: Array(magnitudes.prefix(100))))
        XCTAssertEqual(detector.ignoredFrames, 2)
    }
}
