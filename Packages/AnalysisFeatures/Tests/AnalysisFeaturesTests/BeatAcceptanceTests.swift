// BeatAcceptanceTests.swift — the roadmap acceptance of ANL-005 through the full pipeline
// (AUD-016 fixture → spectrum stream with `.silence` lead-in → ANL-004 onset detector → beat tracker),
// ANL-005-T08 to T11, T13, T14; ANL-005-R17, S1 to S5:
//   "Synthetic 120 BPM pulses converge within a specified BPM tolerance."
// Converged at t: from t to the end of the range every frame has an estimate within ±1.0 BPM of the
// true tempo with confidence ≥ 0.8. Representative cases only (owner rule 7, 2026-11-13).
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class BeatAcceptanceTests: XCTestCase {
    // MARK: US1 + US2 — pulse trains converge and beats land within one hop

    private func checkPulse(_ id: String, rate: Int, size: FFTSize, hop: Int) throws {
        let fixture = try BeatTestSupport.fixture(id, rate: rate)
        let run = try BeatTestSupport.pipeline(fixture.samples, size: size, hop: hop, rate: rate)
        let label = "\(id) \(rate) N=\(size.rawValue) hop=\(hop)"
        let end = Int64(fixture.samples.count) + Int64(size.rawValue)
        let converged = try XCTUnwrap(BeatTestSupport.convergence(run, bpm: fixture.bpm), "\(label): never converged")
        let seconds = Double(converged.position) / Double(rate)
        XCTAssertLessThanOrEqual(seconds, 4.0, label)                                        // S1
        let after = converged.position..<end
        let tempoError = BeatTestSupport.largestTempoError(run, bpm: fixture.bpm, in: after)
        let match = BeatTestSupport.matchBeats(run.beats, onsets: fixture.onsets, tolerance: Int64(hop), in: after)
        XCTAssertTrue(match.passed, "\(label): \(match)")                                     // S2
        XCTAssertGreaterThan(match.expected, 8, label)
        for step in run.steps { if let e = step.estimate { XCTAssertGreaterThanOrEqual(e.nextBeatSample, step.position) } }
        let final = try XCTUnwrap(run.steps.last?.estimate)
        print("ANL-005 pulse: \(label) | converged \(String(format: "%.3f", seconds)) s | final \(String(format: "%.3f", final.bpm)) BPM, confidence \(final.confidence) | largest |tempo error| after \(String(format: "%.3f", tempoError)) BPM | beats \(match)")
    }

    func testPulse120Hop512() throws { try checkPulse("pulse-120", rate: 44_100, size: .n2048, hop: 512) }
    func testPulse120Hop1024() throws { try checkPulse("pulse-120", rate: 44_100, size: .n4096, hop: 1_024) }
    func testPulse120AccentHop512() throws { try checkPulse("pulse-120-accent", rate: 44_100, size: .n2048, hop: 512) }
    func testPulse132At48kHop512() throws { try checkPulse("pulse-132", rate: 48_000, size: .n2048, hop: 512) }
    func testPulse132Hop1024() throws { try checkPulse("pulse-132", rate: 44_100, size: .n4096, hop: 1_024) }

    // MARK: US3 — tempo change and gap

    func testTempoChangeRelocksWithinSixSeconds() throws {
        let rate = 44_100, hop = 512
        let a = try BeatTestSupport.fixture("pulse-120", rate: rate)
        let b = try BeatTestSupport.fixture("pulse-132", rate: rate)
        let change = Int64(a.samples.count)
        let run = try BeatTestSupport.pipeline(a.samples + b.samples, size: .n2048, hop: hop, rate: rate)
        let first = try XCTUnwrap(BeatTestSupport.convergence(run, bpm: 120, in: 0..<change), "120 never converged")
        XCTAssertLessThanOrEqual(Double(first.position) / Double(rate), 4.0)
        let second = try XCTUnwrap(BeatTestSupport.convergence(run, bpm: 132, in: change..<Int64.max), "132 never converged")
        let relock = Double(second.position - change) / Double(rate)
        XCTAssertLessThanOrEqual(relock, 6.0)                                                    // S3
        print("ANL-005 change: 120 converged at \(Double(first.position) / Double(rate)) s; 120→132 at 10 s re-converged \(String(format: "%.3f", relock)) s after the change")
    }

    func testSilenceDropsTheTempoAndANewTempoLocksAfterAGap() throws {
        let rate = 44_100, hop = 512
        let a = try BeatTestSupport.fixture("pulse-120", rate: rate)
        let b = try BeatTestSupport.fixture("pulse-132", rate: rate)
        let gapStart = Int64(a.samples.count)
        let restart = gapStart + Int64(6 * rate)
        let samples = a.samples + [Float](repeating: 0, count: 6 * rate) + b.samples
        let run = try BeatTestSupport.pipeline(samples, size: .n2048, hop: hop, rate: rate)
        let lastPulse = try XCTUnwrap(a.onsets.last)
        let lastEvent = try XCTUnwrap(run.onsets.last { $0 < gapStart + Int64(rate) })   // the 132 loop's first event may precede `restart` by up to a hop
        // During the silence the confidence never rises, and the estimate is gone 4 s after the last
        // onset event (which is within one hop of the last pulse), with no beat events after that.
        var previous = Double.infinity
        var goneAt: Int64?
        for step in run.steps where step.position > lastEvent + Int64(hop) && step.position < restart {
            let confidence = step.estimate?.confidence ?? 0
            XCTAssertLessThanOrEqual(confidence, previous, "\(step.position)")
            previous = confidence
            if step.estimate == nil, goneAt == nil { goneAt = step.position }
            if goneAt != nil { XCTAssertNil(step.estimate, "\(step.position)") }
        }
        let gone = try XCTUnwrap(goneAt)
        let goneAfter = Double(gone - lastPulse) / Double(rate)
        XCTAssertLessThanOrEqual(gone - lastEvent, Int64(4 * rate) + Int64(hop))
        XCTAssertTrue(run.beats.allSatisfy { $0.sampleIndex < gone || $0.sampleIndex >= restart })
        let relock = try XCTUnwrap(BeatTestSupport.convergence(run, bpm: 132, in: restart..<Int64.max), "132 never converged")
        let relockSeconds = Double(relock.position - restart) / Double(rate)
        XCTAssertLessThanOrEqual(relockSeconds, 4.0)                                             // S3
        print("ANL-005 gap: last pulse \(lastPulse), last onset event \(lastEvent); no tempo \(String(format: "%.3f", goneAfter)) s after the last pulse; 132 converged \(String(format: "%.3f", relockSeconds)) s after the restart")
    }

    // MARK: US4 — silence and noise through the pipeline

    func testSilenceAndLoudNoiseNeverClaimATempo() throws {
        let rate = 44_100
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence")).loop(sampleRate: rate, channels: 1)
        let quiet = try BeatTestSupport.pipeline(silence, size: .n512, hop: 256, rate: rate)
        XCTAssertTrue(quiet.steps.allSatisfy { $0.estimate == nil })
        XCTAssertTrue(quiet.beats.isEmpty)
        let noise = OnsetTestSupport.noise(seconds: 10, rate: rate, peak: 0.3)
        let loud = try BeatTestSupport.pipeline(noise, size: .n512, hop: 256, rate: rate)
        let highest = loud.steps.map { $0.estimate?.confidence ?? 0 }.max() ?? 0
        XCTAssertLessThan(highest, AdaptiveBeatTracker.highConfidence)                       // S4
        print("ANL-005 noise: silence \(quiet.steps.count) frames, 0 estimates; -10 dBFS noise \(loud.onsets.count) onsets, max confidence \(highest)")
    }

    // MARK: US5 — repeated runs and backends

    func testRepeatedRunsAndBackendsAreBitIdentical() throws {
        let rate = 48_000
        let fixture = try BeatTestSupport.fixture("pulse-132", rate: rate)
        let a = try BeatTestSupport.pipeline(fixture.samples, size: .n2048, hop: 512, rate: rate)
        let b = try BeatTestSupport.pipeline(fixture.samples, size: .n2048, hop: 512, rate: rate)
        XCTAssertEqual(a, b)
        XCTAssertEqual(bits(a), bits(b))
        // The same onsets through each backend's tracker.
        var reference: [UInt64]?
        for backend in [SpectrumBackend.portable, .accelerated] {
            let tracker = AdaptiveBeatTracker(configuration: try BeatTrackerConfiguration(sampleRate: Double(rate)), backend: backend)
            let run = BeatTestSupport.track(onsets: a.onsets, end: Int64(fixture.samples.count), tracker: tracker)
            XCTAssertFalse(run.beats.isEmpty)
            if let reference { XCTAssertEqual(bits(run), reference, "\(backend)") } else { reference = bits(run) }
        }
        print("ANL-005 determinism: \(a.steps.count) estimates and \(a.beats.count) beats identical on repeat; portable and \(SpectrumBackend.isAcceleratedAvailable ? "vDSP" : "portable (vDSP compiled out)") trackers bit-identical")
    }

    /// Every double of every estimate and beat event as a bit pattern, plus the integers.
    private func bits(_ run: BeatTestSupport.Run) -> [UInt64] {
        var out: [UInt64] = []
        for step in run.steps {
            out.append(UInt64(bitPattern: step.position))
            guard let e = step.estimate else { out.append(0); continue }
            out += [e.bpm, e.periodSamples, e.anchorSample, e.confidence, e.precision, e.coverage, e.support, e.freshness]
                .map(\.bitPattern)
            out += [UInt64(bitPattern: e.nextBeatSample), UInt64(e.matchedBeats), UInt64(e.onsetsInWindow)]
        }
        for beat in run.beats {
            out += [beat.sequence, UInt64(bitPattern: beat.sampleIndex), beat.bpm.bitPattern, beat.periodSamples.bitPattern,
                    beat.confidence.bitPattern]
        }
        return out
    }
}
