// SectionEnergyChangeTests.swift — ANL-015: sustained quiet/loud section changes
// (contracts/section-energy-change.md C1-C4). Synthetic PCM through the real SpectrumStream and
// ANL-014 level for the timing-sensitive cases, per-frame synthetic levels on the hop clock for the
// state-machine cases, and one short pipeline run; a few representative cases (owner rule 7). No
// Accelerate import, no C stdio globals, no clock.
import XCTest
import AudioCore
@testable import AnalysisFeatures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

final class SectionEnergyChangeTests: XCTestCase {
    // MARK: Fixtures

    private static let rate: Double = 44_100
    private static let hop: Int64 = 512
    private static let size: Int64 = 2_048

    private static func amplitude(dBFS: Double) -> Float {
        let linear: Double = pow(10, dBFS / 20)
        return Float(linear)
    }

    /// A 1 kHz tone whose level is `segments[i].dBFS` for `segments[i].seconds` (phase continuous;
    /// nil = digital silence).
    private static func tone(_ segments: [(dBFS: Double?, seconds: Double)]) -> [Float] {
        var out: [Float] = []
        for segment in segments {
            let count = Int((segment.seconds * rate).rounded())
            let start: Int = out.count
            guard let level = segment.dBFS else {
                out += [Float](repeating: 0, count: count)
                continue
            }
            let a: Float = amplitude(dBFS: level)
            for n in start..<(start + count) {
                let phase: Double = 2 * Double.pi * 1_000 * Double(n) / rate + 0.3
                out.append(a * Float(sin(phase)))
            }
        }
        return out
    }

    /// Each frame's (window end, ANL-014 level) for mono `samples` fed in `chunk`-sample pieces.
    private static func levels(_ samples: [Float], chunk: Int = 2_048) throws -> [(end: Int64, level: Float)] {
        let configuration = try SpectrumConfiguration(size: .n2048, hop: 512, sampleRate: rate)
        let spectra = SpectrumStream(configuration: configuration, clock: { 0 })
        var loudness = LoudnessEnvelope()
        var out: [(end: Int64, level: Float)] = []
        var offset = 0
        while offset < samples.count {
            let count: Int = min(chunk, samples.count - offset)
            samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                guard let base = buffer.baseAddress else { return }
                _ = spectra.append(mono: base + offset, count: count)
            }
            offset += count
            while let frame = spectra.nextFrame() {
                let reading: LoudnessReading = loudness.process(frame, magnitudes: spectra.magnitudes)
                out.append((end: frame.index + Int64(frame.size.rawValue), level: reading.decibels))
            }
        }
        return out
    }

    /// Per-frame synthetic levels on the hop clock: frame k ends at 2,048 + k·512.
    private static func synthetic(seconds: Double, level: (Double) -> Float) -> [(end: Int64, level: Float)] {
        let frames = Int(seconds * rate / Double(hop))
        return (0..<frames).map { (k: Int) -> (end: Int64, level: Float) in
            let end: Int64 = size + Int64(k) * hop
            return (end: end, level: level(Double(end) / rate))
        }
    }

    private struct Run {
        var changes: [SectionChange] = []
        var envelopes: [Float] = []
        var slow: [Float] = []
        var references: [Float] = []
    }

    private static func run(_ frames: [(end: Int64, level: Float)],
                            configuration: SectionChangeConfiguration = .standard) -> Run {
        var detector = SectionChangeDetector(configuration: configuration)
        var result = Run()
        for frame in frames {
            if let change = detector.process(levelDecibels: frame.level, frameEnd: frame.end) { result.changes.append(change) }
            result.envelopes.append(detector.envelope)
            result.slow.append(detector.levelDecibels)
            result.references.append(detector.referenceDecibels)
        }
        return result
    }

    // MARK: Configuration (T02)

    func testConfigurationDefaultsAndRefusals() throws {
        let standard = SectionChangeConfiguration.standard
        XCTAssertEqual(standard.dwellSamples, 88_200)
        XCTAssertEqual(standard.settleSamples, 88_200)
        XCTAssertEqual(standard.refractorySamples, 176_400)
        XCTAssertEqual(standard.windowFrames, 35)
        XCTAssertEqual(standard.envelopeDecay, Float(exp(-512.0 / 44_100.0)), accuracy: 1e-7)
        XCTAssertEqual(standard.referenceCoefficient, 1 - exp(-512.0 / (8 * 44_100.0)), accuracy: 1e-12)
        XCTAssertThrowsError(try SectionChangeConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try SectionChangeConfiguration(hop: 0))
        XCTAssertThrowsError(try SectionChangeConfiguration(windowFrames: 65))
        XCTAssertThrowsError(try SectionChangeConfiguration(floorDecibels: 0))
        XCTAssertThrowsError(try SectionChangeConfiguration(dwellSeconds: .nan))
        XCTAssertThrowsError(try SectionChangeConfiguration(settleSeconds: -1))
        XCTAssertThrowsError(try SectionChangeConfiguration(enterDecibels: 3, holdDecibels: 3)) { (error: Error) -> Void in
            XCTAssertEqual(error as? SectionChangeConfigurationError, .invalidThresholds(enter: 3, hold: 3))
        }
        XCTAssertThrowsError(try AnalysisPipelineConfiguration(sectionChange: try SectionChangeConfiguration(sampleRate: 48_000))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
        XCTAssertThrowsError(try AnalysisPipelineConfiguration(sectionChange: try SectionChangeConfiguration(hop: 256))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
    }

    // MARK: User story 1: the roadmap acceptance (T04)

    func testQuietToLoudFiresOnceAfterDwell() throws {
        let samples: [Float] = Self.tone([(-40, 4), (-10, 6)])
        let step: Int64 = 176_400
        let dwell: Int64 = SectionChangeConfiguration.standard.dwellSamples
        let result = Self.run(try Self.levels(samples))
        XCTAssertEqual(result.changes.count, 1, "exactly one change: \(result.changes)")
        let change = try XCTUnwrap(result.changes.first)
        print("ANL-015 acceptance: start \(change.startSample - step) samples after the step, confirmed \(change.confirmSample - step - dwell) after step + dwell; level \(change.levelDecibels) dB from \(change.referenceDecibels) dB")
        XCTAssertEqual(change.direction, .rising)
        XCTAssertGreaterThan(change.startSample, step)
        XCTAssertGreaterThanOrEqual(change.confirmSample, step + dwell, "never before the dwell")
        XCTAssertLessThanOrEqual(change.confirmSample, step + dwell + Self.size, "within one analysis window after it")
        XCTAssertEqual(change.levelDecibels, -13, accuracy: 0.5)
        XCTAssertEqual(change.referenceDecibels, -43, accuracy: 0.5)
    }

    // MARK: User story 2: bursts and steady input (T05)

    func testBriefBurstsSteadyInputAndSettlingFireNothing() throws {
        for burst in [1.0, 1.5] {
            let samples: [Float] = Self.tone([(-40, 3), (-10, burst), (-40, 2.5)])
            XCTAssertEqual(Self.run(try Self.levels(samples)).changes, [], "\(burst) s burst")
        }
        // A step inside the 2 s settling period is absorbed (the opening level is not a change).
        let settling: [Float] = Self.tone([(-40, 1), (-10, 4)])
        XCTAssertEqual(Self.run(try Self.levels(settling)).changes, [], "step during settling")
        // Steady tone, silence (−120 dB frames), and steady noise-like jitter (±2 dB around −20).
        XCTAssertEqual(Self.run(Self.synthetic(seconds: 12) { (_: Double) -> Float in -13 }).changes, [])
        XCTAssertEqual(Self.run(Self.synthetic(seconds: 12) { (_: Double) -> Float in -120 }).changes, [])
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        let jitter = Self.synthetic(seconds: 12) { (_: Double) -> Float in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float(seed >> 40) / Float(1 << 24)
            return -20 + 4 * (unit - 0.5)
        }
        XCTAssertEqual(Self.run(jitter).changes, [])
        // A slow drift (−40 → −30 dB over 20 s, 0.5 dB/s) is absorbed by the 8 s reference: nothing.
        let drift = Self.synthetic(seconds: 24) { (t: Double) -> Float in
            Float(-40 + 10 * min(max((t - 2) / 20, 0), 1))
        }
        XCTAssertEqual(Self.run(drift).changes, [], "slow drift")
        // A fade (−50 → −10 dB over 10 s after 2 s at −50): only rising changes, never closer together
        // than dwell + refractory, so at most two.
        let fade = Self.run(Self.synthetic(seconds: 14) { (t: Double) -> Float in
            Float(-50 + 40 * min(max((t - 2) / 10, 0), 1))
        })
        print("ANL-015 fade: \(fade.changes.map { (c: SectionChange) -> String in "\(c.confirmSample) \(c.referenceDecibels)→\(c.levelDecibels)" })")
        XCTAssertLessThanOrEqual(fade.changes.count, 2)
        XCTAssertTrue(fade.changes.allSatisfy { (c: SectionChange) -> Bool in c.direction == .rising })
        let standard = SectionChangeConfiguration.standard
        for (a, b) in zip(fade.changes, fade.changes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.confirmSample - a.confirmSample, standard.refractorySamples + standard.dwellSamples)
        }
    }

    // MARK: User story 3: loud to quiet, refractory, envelope, bad input (T06)

    func testLoudToQuietFiresOnceAfterDwell() throws {
        let step: Int64 = 176_400
        let dwell: Int64 = SectionChangeConfiguration.standard.dwellSamples
        for quiet in [-40.0, nil] as [Double?] {
            let result = Self.run(try Self.levels(Self.tone([(-10, 4), (quiet, 5)])))
            XCTAssertEqual(result.changes.count, 1, "loud → \(String(describing: quiet)): \(result.changes)")
            let change = try XCTUnwrap(result.changes.first)
            XCTAssertEqual(change.direction, .falling)
            XCTAssertGreaterThanOrEqual(change.confirmSample, step + dwell)
            XCTAssertLessThanOrEqual(change.confirmSample, step + dwell + 17_920 + Self.size, "within the slow window and one block")
        }
        // Silence, then a tone after settling: one rising change.
        let rise = Self.run(try Self.levels(Self.tone([(nil, 3), (-30, 4)])))
        XCTAssertEqual(rise.changes.map(\.direction), [.rising])
    }

    func testRefractoryEnvelopeAndNonFiniteLevels() throws {
        let standard = SectionChangeConfiguration.standard
        // Quiet until 3 s, loud 3-6 s, quiet after: the fall happens inside the refractory period.
        let frames = Self.synthetic(seconds: 19) { (t: Double) -> Float in (3..<6).contains(t) ? -13 : -43 }
        let result = Self.run(frames)
        XCTAssertEqual(result.changes.map(\.direction), [.rising, .falling])
        let rising = result.changes[0]
        let falling = result.changes[1]
        XCTAssertGreaterThanOrEqual(falling.startSample, rising.confirmSample + standard.refractorySamples)
        XCTAssertGreaterThanOrEqual(falling.confirmSample, falling.startSample + standard.dwellSamples)
        // Envelope: 1 exactly on each change frame, decaying in between, 0 before the first.
        let firstIndex = try XCTUnwrap(frames.firstIndex { (f: (end: Int64, level: Float)) -> Bool in f.end == rising.confirmSample })
        XCTAssertEqual(result.envelopes[firstIndex], 1)
        XCTAssertTrue(result.envelopes[..<firstIndex].allSatisfy { (e: Float) -> Bool in e == 0 })
        XCTAssertLessThan(result.envelopes[firstIndex + 1], 1)
        XCTAssertEqual(result.envelopes[firstIndex + 86], exp(-86 * 512 / 44_100), accuracy: 1e-3)   // ≈ 1 s later
        XCTAssertTrue(result.envelopes.allSatisfy { (e: Float) -> Bool in e.isFinite && (0...1).contains(e) })
        // ≈ 6.9 s after a change the envelope is exactly 0 (snap below 0.001).
        let quietIndex = try XCTUnwrap(frames.firstIndex { (f: (end: Int64, level: Float)) -> Bool in f.end == falling.confirmSample })
        XCTAssertEqual(result.envelopes[quietIndex], 1)
        XCTAssertGreaterThan(result.envelopes[quietIndex - 1], 0)
        XCTAssertLessThan(result.envelopes[quietIndex - 1], 0.01)
        XCTAssertEqual(result.envelopes[quietIndex + 600], 0)

        // Non-finite levels count as the floor: every reading stays finite.
        let specials: [Float] = [.nan, .infinity, -.infinity, -13]
        var index = 0
        let hostile = Self.synthetic(seconds: 8) { (_: Double) -> Float in
            index += 1
            return specials[index % specials.count]
        }
        let bad = Self.run(hostile)
        XCTAssertTrue(bad.slow.allSatisfy { (v: Float) -> Bool in v.isFinite && v >= -70 })
        XCTAssertTrue(bad.references.allSatisfy(\.isFinite))
        XCTAssertTrue(bad.envelopes.allSatisfy { (e: Float) -> Bool in e.isFinite && (0...1).contains(e) })
    }

    // MARK: Determinism (T07)

    func testChunkingInvarianceAndReset() throws {
        let samples: [Float] = Self.tone([(-40, 2.5), (-10, 2.5)])
        let configuration = try SectionChangeConfiguration(settleSeconds: 1, dwellSeconds: 1)
        let a = try Self.levels(samples, chunk: 333)
        let b = try Self.levels(samples, chunk: 4_096)
        XCTAssertEqual(a.map(\.end), b.map(\.end))
        XCTAssertEqual(a.map(\.level), b.map(\.level))
        let first = Self.run(a, configuration: configuration)
        XCTAssertEqual(first.changes.count, 1)
        XCTAssertEqual(first.changes, Self.run(b, configuration: configuration).changes)
        XCTAssertEqual(first.envelopes, Self.run(a, configuration: configuration).envelopes)

        var detector = SectionChangeDetector(configuration: configuration)
        for frame in a { detector.process(levelDecibels: frame.level, frameEnd: frame.end) }
        detector.reset()
        XCTAssertEqual(detector.envelope, 0)
        XCTAssertEqual(detector.levelDecibels, -70)
        XCTAssertFalse(detector.isPending)
        var replay = Run()
        for frame in a {
            if let change = detector.process(levelDecibels: frame.level, frameEnd: frame.end) { replay.changes.append(change) }
        }
        XCTAssertEqual(replay.changes, first.changes, "a reset detector repeats exactly")
    }

    // MARK: User story 4: the bus (T07)

    func testThePipelinePublishesOneSectionChange() throws {
        let section = try SectionChangeConfiguration(settleSeconds: 0.5, dwellSeconds: 1.0)
        let configuration = try AnalysisPipelineConfiguration(bandCount: .b16, sectionChange: section)
        let mono: [Float] = Self.tone([(-40, 1.2), (-10, 1.6)])
        var stereo = [Float](repeating: 0, count: mono.count * 2)
        for (n, value) in mono.enumerated() { stereo[2 * n] = value; stereo[2 * n + 1] = value }

        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let pipeline = AnalysisPipeline(configuration: configuration, clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 512))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.feed(stereo, into: ring, chunkFrames: 512) {
            pipeline.step()
            recorder.poll()
        }
        let changes: [AnalysisEvent] = recorder.recording.events.filter { (e: AnalysisEvent) -> Bool in
            if case .sectionChange = e.kind { return true } else { return false }
        }
        XCTAssertEqual(changes.count, 1)
        let event = try XCTUnwrap(changes.first)
        guard case let .sectionChange(direction, level, reference) = event.kind else { return XCTFail("kind") }
        XCTAssertEqual(direction, .rising)
        XCTAssertGreaterThan(level, reference + 6)
        let step = Int64((1.2 * Self.rate).rounded())
        XCTAssertGreaterThan(event.eventSample, step)
        XCTAssertGreaterThanOrEqual(event.time.sessionSample, event.eventSample + section.dwellSamples)
        XCTAssertLessThanOrEqual(event.time.sessionSample, step + section.dwellSamples + Self.size)
        let frames = recorder.recording.frames
        let onEvent = try XCTUnwrap(frames.first { (f: AnalysisFrame) -> Bool in f.time.sessionSample == event.time.sessionSample })
        XCTAssertEqual(onEvent.sectionChangeEnvelope, 1)
        XCTAssertEqual(onEvent.sectionLevelDecibels, level)
        XCTAssertLessThan(try XCTUnwrap(frames.last).sectionChangeEnvelope, 1)
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in
            (0...1).contains(f.sectionChangeEnvelope) && f.sectionLevelDecibels.isFinite && f.sectionLevelDecibels >= -70
        })
        XCTAssertTrue(frames.filter { (f: AnalysisFrame) -> Bool in f.time.sessionSample < event.time.sessionSample }
            .allSatisfy { (f: AnalysisFrame) -> Bool in f.sectionChangeEnvelope == 0 })

        pipeline.restartSession()
        recorder.poll()
        BusFixture.feed(Array(stereo[0..<(2 * 4_096)]), into: ring, chunkFrames: 512) {
            pipeline.step()
            recorder.poll()
        }
        let after = try XCTUnwrap(recorder.recording.frames.last)
        XCTAssertEqual(after.sectionChangeEnvelope, 0, "a session start resets the detector")
    }
}
