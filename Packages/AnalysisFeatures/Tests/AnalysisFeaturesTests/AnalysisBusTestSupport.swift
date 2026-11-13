// AnalysisBusTestSupport.swift — test-only helpers for ANL-016 (ANL-016-T03): a deterministic step
// clock, AUD-016 fixtures as interleaved stereo at 44.1 kHz, a feeder that writes a real normalized
// ring (with its analysis tap) in chunks and steps the pipeline synchronously, a subscription
// recorder, and a reader stub whose capture session restarts in the middle of a read. No Accelerate
// import, no C stdio globals (runs on Linux and with -DANALYSIS_NO_ACCELERATE).
import Foundation
import Synchronization
import XCTest
import AudioCore
@testable import AnalysisFeatures

/// A monotonic clock that advances by `step` nanoseconds on every reading (first reading = start).
final class StepClock: Sendable {
    private let next: Atomic<UInt64>
    private let step: UInt64
    init(start: UInt64 = 1_000_000_000, step: UInt64 = 100_000_000) {
        next = Atomic(start)
        self.step = step
    }
    func read() -> UInt64 { next.add(step, ordering: .relaxed).oldValue }
    var function: @Sendable () -> UInt64 { { [self] in self.read() } }
}

enum BusFixture {
    static let rate = 44_100
    static let format = try! ToneFormat(sampleRate: rate, channels: 2)

    /// AUD-016 `pulse-120` (2 ms clicks at 0.5) as interleaved stereo.
    static func pulses(seconds: Double) throws -> [Float] {
        let generator = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)),
                                          format: format)
        return generator.interleaved(frames: Int(Double(rate) * seconds))
    }

    /// A stereo sine (the source "switch" signal).
    static func sine(_ frequency: Double = 1_000, seconds: Double) throws -> [Float] {
        let generator = try ToneGenerator(signal: .sine(SineTone(frequency: frequency, amplitude: 0.5)), format: format)
        return generator.interleaved(frames: Int(Double(rate) * seconds))
    }

    /// Writes `samples` into `ring` in `chunkFrames` pieces, calling `afterChunk` after each one.
    static func feed(_ samples: [Float], into ring: NormalizedPCMRing, chunkFrames: Int = 2_048,
                     afterChunk: () -> Void = {}) {
        let frames = samples.count / 2
        var offset = 0
        samples.withUnsafeBufferPointer { buffer in
            while offset < frames {
                let n = min(chunkFrames, frames - offset)
                ring.write(buffer.baseAddress! + 2 * offset, frames: n)
                offset += n
                afterChunk()
            }
        }
    }

    /// Writes `samples` and steps `pipeline` after every chunk.
    static func run(_ samples: [Float], ring: NormalizedPCMRing, pipeline: AnalysisPipeline,
                    recorders: [BusRecorder] = []) {
        feed(samples, into: ring) {
            pipeline.step()
            recorders.forEach { $0.poll() }
        }
    }
}

/// Everything one subscription delivered.
struct BusRecording: Equatable {
    var events: [AnalysisEvent] = []
    var frames: [AnalysisFrame] = []
    var bands: [[Float]] = []

    var onsets: [AnalysisEvent] { events.filter { if case .onset = $0.kind { return true } else { return false } } }
    var beats: [AnalysisEvent] { events.filter { if case .beat = $0.kind { return true } else { return false } } }
    var markers: [AnalysisEvent] {
        events.filter {
            switch $0.kind {
            case .sessionStarted, .sessionEnded: return true
            default: return false
            }
        }
    }

    /// Every delivered item's (id, timestamp), sorted by ID.
    var timeline: [(id: UInt64, time: AnalysisTimestamp)] {
        (events.map { ($0.id, $0.time) } + frames.map { ($0.id, $0.time) }).sorted { $0.0 < $1.0 }
    }
}

final class BusRecorder {
    let subscription: AnalysisSubscription
    private(set) var recording = BusRecording()
    private var scratch = [Float](repeating: 0, count: 128)

    init(_ subscription: AnalysisSubscription) { self.subscription = subscription }

    /// Drains queued events and reads the latest frame, if a new one arrived.
    func poll() {
        while let event = subscription.nextEvent() { recording.events.append(event) }
        let frame = scratch.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 128) }
        if let frame {
            recording.frames.append(frame)
            recording.bands.append(Array(scratch[0..<frame.bandCount]))
        }
    }
}

/// A reader over fixed stereo chunks whose capture session restarts during read number
/// `restartDuringRead` (1-based): the chunk returned by that read straddles the restart.
final class RestartingReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let chunks: [[Float]]
    private let restartDuringRead: Int
    private var reads = 0                       // confined to the pipeline's worker
    private let generation = Atomic<UInt64>(0)

    init(chunks: [[Float]], restartDuringRead: Int) {
        self.chunks = chunks
        self.restartDuringRead = restartDuringRead
    }

    var analysisSessionGeneration: UInt64 { generation.load(ordering: .acquiring) }

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard reads < chunks.count else { return 0 }
        let chunk = chunks[reads]
        reads += 1
        let frames = min(maxFrames, chunk.count / 2)
        chunk.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: frames * 2) }
        if reads == restartDuringRead { generation.add(1, ordering: .releasing) }
        return frames
    }
}

extension XCTestCase {
    /// Asserts IDs strictly increase and timeline/host time never decrease in ID order.
    func assertOrdered(_ recording: BusRecording, file: StaticString = #filePath, line: UInt = #line) {
        let items = recording.timeline
        for (a, b) in zip(items, items.dropFirst()) {
            XCTAssertLessThan(a.id, b.id, "IDs strictly increase", file: file, line: line)
            XCTAssertLessThanOrEqual(a.time.timelineSample, b.time.timelineSample, "timeline never decreases (ids \(a.id), \(b.id))", file: file, line: line)
            XCTAssertLessThanOrEqual(a.time.hostNanoseconds, b.time.hostNanoseconds, "host time never decreases (ids \(a.id), \(b.id))", file: file, line: line)
            XCTAssertLessThanOrEqual(a.time.session, b.time.session, "sessions never go back", file: file, line: line)
        }
        let events = recording.events.map(\.id)
        XCTAssertEqual(events, events.sorted(), "events are delivered in ID order", file: file, line: line)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "no ID repeats", file: file, line: line)
    }
}
