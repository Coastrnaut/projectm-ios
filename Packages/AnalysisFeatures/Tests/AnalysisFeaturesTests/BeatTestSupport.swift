// BeatTestSupport.swift — test-only helpers for ANL-005 (ANL-005-T03): feed exact onset lists or
// audio through the pipeline into a beat tracker, measure convergence and match beat events to the
// catalog's onset frames. No Accelerate import, no C stdio globals (runs on Linux and with
// -DANALYSIS_NO_ACCELERATE).
import Foundation
import XCTest
import AudioCore
@testable import AnalysisFeatures

enum BeatTestSupport {
    /// One observation per advance: the position reached and the estimate there.
    struct Step: Equatable {
        var position: Int64
        var estimate: BeatEstimate?
    }

    struct Run: Equatable {
        var steps: [Step] = []
        var beats: [BeatEvent] = []
        var onsets: [Int64] = []
    }

    /// Feeds `onsets` (sorted sample indices) to `tracker`, advancing in `step`-sample increments from
    /// 0 to `end`: each step first adds the onsets before its end, then advances to it.
    static func track(onsets: [Int64], end: Int64, step: Int64 = 512,
                      tracker: AdaptiveBeatTracker = AdaptiveBeatTracker()) -> Run {
        var run = Run(onsets: onsets)
        var next = 0
        var position: Int64 = 0
        while position <= end {
            while next < onsets.count, onsets[next] < position { tracker.add(onsetAt: onsets[next]); next += 1 }
            if let beat = tracker.advance(to: position) { run.beats.append(beat) }
            run.steps.append(Step(position: position, estimate: tracker.estimate))
            position += step
        }
        return run
    }

    /// Mono `samples` → `.silence` lead-in stream (`size`, `hop`, `rate`, clock fixed at 0) → onset
    /// detector → tracker via `process(_:onset:)`.
    static func pipeline(_ samples: [Float], size: FFTSize, hop: Int, rate: Int,
                         backend: SpectrumBackend = .automatic) throws -> Run {
        let spectrum = try SpectrumConfiguration(size: size, hop: hop, sampleRate: Double(rate))
        let stream = SpectrumStream(configuration: spectrum, backend: backend, clock: { 0 }, leadIn: .silence)
        let detector = SpectralFluxOnsetDetector(
            configuration: try OnsetDetectorConfiguration(sampleRate: Double(rate)), backend: backend)
        let tracker = AdaptiveBeatTracker(configuration: try BeatTrackerConfiguration(sampleRate: Double(rate)),
                                          backend: backend)
        var run = Run()
        samples.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                while let frame = stream.nextFrame() {
                    let onset = detector.process(frame, magnitudes: stream.magnitudes)
                    if let onset { run.onsets.append(onset.sampleIndex) }
                    if let beat = tracker.process(frame, onset: onset) { run.beats.append(beat) }
                    run.steps.append(Step(position: frame.index + Int64(size.rawValue), estimate: tracker.estimate))
                }
            }
        }
        return run
    }

    static func isLocked(_ estimate: BeatEstimate?, bpm: Double, tolerance: Double = 1.0,
                         confidence: Double = 0.8) -> Bool {
        guard let estimate else { return false }
        return abs(estimate.bpm - bpm) <= tolerance && estimate.confidence >= confidence
    }

    /// The first step from which every step in `range` (by position) is locked to `bpm`; nil if the
    /// last step in range is not locked.
    static func convergence(_ run: Run, bpm: Double, in range: Range<Int64> = Int64.min..<Int64.max) -> Step? {
        var candidate: Step?
        for step in run.steps where range.contains(step.position) {
            if isLocked(step.estimate, bpm: bpm) {
                if candidate == nil { candidate = step }
            } else {
                candidate = nil
            }
        }
        return candidate
    }

    /// The largest |BPM − true| over the steps in `range`.
    static func largestTempoError(_ run: Run, bpm: Double, in range: Range<Int64>) -> Double {
        run.steps.filter { range.contains($0.position) }.map { abs(($0.estimate?.bpm ?? .infinity) - bpm) }.max() ?? 0
    }

    struct BeatMatch: CustomStringConvertible {
        var expected = 0
        var reported = 0
        var missed = 0
        var extra = 0
        var largestError: Int64 = 0
        var passed: Bool { missed == 0 && extra == 0 }
        var description: String {
            "expected \(expected), reported \(reported), missed \(missed), extra \(extra), largest |error| \(largestError)"
        }
    }

    /// Catalog onsets in `range` each take the first unused beat within ±tolerance; beats in `range`
    /// never taken are extra.
    static func matchBeats(_ beats: [BeatEvent], onsets: [Int64], tolerance: Int64, in range: Range<Int64>) -> BeatMatch {
        let candidates = beats.filter { range.contains($0.sampleIndex) }
        let truths = onsets.filter { range.contains($0) }
        var result = BeatMatch(expected: truths.count, reported: candidates.count)
        var used = [Bool](repeating: false, count: candidates.count)
        for truth in truths {
            if let i = candidates.indices.first(where: { !used[$0] && abs(candidates[$0].sampleIndex - truth) <= tolerance }) {
                used[i] = true
                result.largestError = max(result.largestError, abs(candidates[i].sampleIndex - truth))
            } else {
                result.missed += 1
            }
        }
        result.extra = used.filter { !$0 }.count
        return result
    }

    /// Random onsets: exponential gaps of mean 1/`perSecond` plus 50 ms (ANL-004's minimum interval),
    /// from a fixed-seed 64-bit LCG.
    static func randomOnsets(perSecond: Double, seconds: Double, rate: Int, seed: UInt64) -> [Int64] {
        var state = seed
        var t = 0.0
        var result: [Int64] = []
        while true {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = (Double(state >> 11) + 0.5) / Double(1 << 53)       // (0, 1)
            t += -log(unit) / perSecond + 0.05
            guard t < seconds else { return result }
            result.append(Int64((t * Double(rate)).rounded()))
        }
    }

    /// One mono loop of a catalog fixture and its onset frames.
    static func fixture(_ id: String, rate: Int) throws -> (samples: [Float], onsets: [Int64], bpm: Double) {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
        let onsets = fixture.onsetFrames(sampleRate: rate)
        let bpm: Double = id == "pulse-132" ? 132 : 120
        return (try fixture.loop(sampleRate: rate, channels: 1), onsets, bpm)
    }
}
