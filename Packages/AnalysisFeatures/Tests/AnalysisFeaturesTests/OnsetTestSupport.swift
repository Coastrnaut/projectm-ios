// OnsetTestSupport.swift — test-only helpers for ANL-004 (ANL-004-T04): run mono audio through a
// lead-in stream and an onset detector, and match events to known onsets within one hop.
// No Accelerate import (runs on Linux and with -DANALYSIS_NO_ACCELERATE).
import XCTest
import AudioCore
@testable import AnalysisFeatures

enum OnsetTestSupport {
    struct Run {
        var events: [OnsetEvent] = []
        /// Every frame's detection value (only when requested).
        var fluxes: [Float] = []
        var frames = 0
    }

    /// Mono `samples` through a stream (`size`, `hop`, `rate`, `leadIn`) and a detector; the clock is
    /// fixed at 0. Allocation in the test loop is fine; the detector itself does not allocate.
    static func run(_ samples: [Float], size: FFTSize, hop: Int, rate: Int,
                    backend: SpectrumBackend = .automatic,
                    configuration: OnsetDetectorConfiguration? = nil,
                    leadIn: SpectrumLeadIn = .silence, recordFlux: Bool = false) throws -> Run {
        let spectrum = try SpectrumConfiguration(size: size, hop: hop, sampleRate: Double(rate))
        let stream = SpectrumStream(configuration: spectrum, backend: backend, clock: { 0 }, leadIn: leadIn)
        let detector = SpectralFluxOnsetDetector(
            configuration: try configuration ?? OnsetDetectorConfiguration(sampleRate: Double(rate)), backend: backend)
        var result = Run()
        samples.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                while let frame = stream.nextFrame() {
                    result.frames += 1
                    if let event = detector.process(frame, magnitudes: stream.magnitudes) { result.events.append(event) }
                    if recordFlux { result.fluxes.append(detector.lastFlux) }
                }
            }
        }
        return result
    }

    struct Match: CustomStringConvertible {
        var onsets = 0
        var events = 0
        var misses = 0
        var unmatched = 0
        var maxError: Int64 = 0
        var passed: Bool { misses == 0 && unmatched == 0 }
        var description: String {
            "onsets \(onsets), events \(events), misses \(misses), false \(unmatched), max |error| \(maxError)"
        }
    }

    /// Walks onsets in order; each takes the first unused event within ±tolerance (events are in
    /// increasing sample order). Events never taken are false events.
    static func match(_ events: [OnsetEvent], onsets: [Int64], tolerance: Int) -> Match {
        var result = Match(onsets: onsets.count, events: events.count)
        var used = [Bool](repeating: false, count: events.count)
        var start = 0
        for onset in onsets {
            var found: Int?
            var i = start
            while i < events.count, events[i].sampleIndex <= onset + Int64(tolerance) {
                if !used[i], abs(events[i].sampleIndex - onset) <= Int64(tolerance) { found = i; break }
                i += 1
            }
            if let found {
                used[found] = true
                result.maxError = max(result.maxError, abs(events[found].sampleIndex - onset))
                start = found + 1
            } else {
                result.misses += 1
            }
        }
        result.unmatched = used.filter { !$0 }.count
        return result
    }

    /// One mono loop of a catalog fixture (the left channel; every fixture used here has equal channels).
    static func loop(_ id: String, rate: Int) throws -> [Float] {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: id))
        return try fixture.loop(sampleRate: rate, channels: 1)
    }

    /// Fixed-seed uniform noise in [-peak, peak) (ANL-001's LCG).
    static func noise(seconds: Double, rate: Int, peak: Float, seed: UInt64 = 0x5EED) -> [Float] {
        TestSupport.noise(count: Int(seconds * Double(rate)), seed: seed, amplitude: peak)
    }

    static let hopDivisors = [2, 4, 8]
    static let rates = [44_100, 48_000]
}

