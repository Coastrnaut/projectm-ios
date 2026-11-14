// NormalizedPCMReader.swift — the normalized ring between the work queue and the renderer
// (task T060; research R-06; contracts/audio-source.md §NormalizedPCMReader).
//
// Format: Float32, interleaved stereo, 44,100 Hz (research R-05). Capacity 0.5 s = 22,050 stereo
// frames, drop-oldest on overflow. The work queue is the only producer (`write`); the render loop
// is the consumer (`read`).
//
// Freshness rule (R-06): if more than 50 ms (2,205 frames) is buffered when `read` is called (once
// per rendered frame), the reader first skips to the newest 50 ms; the skipped frames are counted
// as dropped. This caps the time audio waits here within the SC-006 latency budget.
// Underrun policy (R-06): an empty ring reads 0 frames; no silence is injected.
//
// Real-time safety (Constitution VII): after init nothing allocates, locks or logs. Every write is
// a whole number of stereo frames and the capacity is even, so drop-oldest and the freshness skip
// keep L/R alignment.
//
// Analysis tap (ANL-001-R9; research ANL-001-D7): an optional second SPSC ring, created only when
// `init(analysisTapCapacityFrames:)` gets a positive capacity, receives a copy of every write. It
// has its own consumer (the analysis worker), drop-oldest overflow and counter, and no freshness
// rule, so reading it (or never reading it) leaves the main ring's reads unchanged. Without a tap
// (the default) the ring behaves exactly as before. Nothing read from the tap goes to projectM.
//
// Session generation (ANL-016-R9; research ANL-016-D1): `reset()` (a new capture session: the
// capture manager's start, restart or source switch) empties both rings and only then increases an
// atomic generation with release ordering; `discardBuffered()` (a seek inside a session) does not.
// The tap's consumer (the analysis event bus) reads it with acquire ordering before and after each
// chunk it reads: a change during the read means the chunk may hold audio of either session.
//
// Renderer boundary (AUD-012, contracts/source-handoff.md C1): `write` is the one place every
// normalized sample passes before projectM and the analysis tap. A write that is clean (finite,
// within the ring's bound, ±2 on the capture path) while the handoff envelope is at unity goes straight to the rings, bit-identical and
// without a copy. Otherwise it goes through a preallocated 1,024-frame scratch: `PCMSanitizer`
// replaces bad samples (counted in `sanitizedSampleCount`), then `HandoffEnvelope` applies the
// switch ramp. The envelope and the scratch are producer-side state (the analysis queue).
// `resetForHandoff` (a source switch) empties the tap and advances the generation like `reset`,
// but keeps projectM's ring, whose content then ends at exact 0, and writes 1,024 frames of
// silence: the one exception to R-06's underrun policy ("no silence is injected").
//
// Recording tap (REC-004-D1, D2; specs/134-rec-004-recording-audio contract C2): a third SPSC ring,
// always allocated, written only while armed (a recording with permitted audio runs). `reset()` and
// `resetForHandoff()` disarm it before their first new-session write, so another source's audio can
// never reach a recording; `discardBuffered()` drains it and keeps it armed. Each armed write stores the
// uptime time of the write and then bumps a counter, so the consumer can date the newest sample it drains.
import Synchronization

/// Reports capture-session restarts to an analysis consumer (ANL-016-R9).
public protocol AnalysisSessionReporting: Sendable {
    /// Increases each time the source ring is reset for a new capture session, after its analysis
    /// tap was emptied. Starts at 0.
    var analysisSessionGeneration: UInt64 { get }
}

/// Reads normalized audio (Float32 interleaved stereo at 44.1 kHz). Consumed by the renderer.
public protocol NormalizedPCMReader: Sendable {
    /// Reads up to `maxFrames` interleaved stereo Float32 frames at 44.1 kHz into `dst` (room for
    /// `2 × maxFrames` floats). Non-blocking; returns the number of frames, 0 when empty.
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int
}

public final class NormalizedPCMRing: NormalizedPCMReader, @unchecked Sendable {
    public static let sampleRate: Double = 44_100
    public static let channelCount = 2
    /// 0.5 s at 44.1 kHz.
    public static let capacityFrames = 22_050
    /// 50 ms at 44.1 kHz: the most a read leaves buffered before it starts (freshness rule).
    public static let freshnessFrames = 2_205

    private let ring = SPSCRingBuffer(capacity: NormalizedPCMRing.capacityFrames * NormalizedPCMRing.channelCount)
    private let freshnessDropped = Atomic<Int>(0)
    /// `ring.droppedSamples` at the last `reset()`, so counts restart with each session.
    private let overflowBaseline = Atomic<Int>(0)
    /// Frames buffered at the start of the latest `read`, before the freshness skip (a measure of
    /// how long audio waited here; read by the latency signposts).
    private let lastBacklog = Atomic<Int>(0)

    /// 0.5 s at 44.1 kHz: the analysis tap's capacity when a caller enables it with the default.
    public static let analysisTapDefaultCapacityFrames = 22_050

    private let tapRing: SPSCRingBuffer?
    /// `tapRing.droppedSamples` at the last `reset()`.
    private let tapOverflowBaseline = Atomic<Int>(0)
    private let tapReader: AnalysisTapReader?
    /// REC-004: the recording tap (0.5 s, preallocated) and its reader.
    private let recordingRing = SPSCRingBuffer(capacity: NormalizedPCMRing.capacityFrames * NormalizedPCMRing.channelCount)
    private let recordingState = RecordingTapState()
    private let recordingReader: RecordingTapReader
    /// Increased by `reset()` after the drains (release); read by the tap's consumer (acquire).
    private let sessionGeneration: SessionGeneration

    /// AUD-012: samples the boundary (and the analyzer's input stage) replaced since creation.
    private let sanitized = Atomic<Int>(0)
    /// AUD-012: producer-side scratch and switch envelope (the analysis queue only).
    public static let boundaryChunkFrames = 1_024
    private let boundaryScratch: UnsafeMutablePointer<Float>
    private var envelope = HandoffEnvelope()

    /// AUD-012: the largest magnitude written; `AudioAnalyzer` (the capture path to projectM) uses
    /// `PCMSanitizer.bound` (±2). The default, infinity, replaces only NaN and ±Inf, so harness
    /// rings that carry test patterns (sample indices) keep them.
    public let sampleBound: Float

    /// `analysisTapCapacityFrames` > 0 adds an analysis tap of that many stereo frames; 0 (the
    /// default) or less means no tap. `sampleBound` (AUD-012): see the property.
    public init(analysisTapCapacityFrames: Int = 0, sampleBound: Float = .infinity) {
        self.sampleBound = sampleBound
        let scratchCount = NormalizedPCMRing.boundaryChunkFrames * NormalizedPCMRing.channelCount
        boundaryScratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCount)
        boundaryScratch.initialize(repeating: 0, count: scratchCount)
        let generation = SessionGeneration()
        sessionGeneration = generation
        recordingReader = RecordingTapReader(ring: recordingRing, state: recordingState)
        if analysisTapCapacityFrames > 0 {
            let tap = SPSCRingBuffer(capacity: analysisTapCapacityFrames * NormalizedPCMRing.channelCount)
            tapRing = tap
            tapReader = AnalysisTapReader(ring: tap, generation: generation)
        } else {
            tapRing = nil
            tapReader = nil
        }
    }

    deinit {
        boundaryScratch.deinitialize(count: NormalizedPCMRing.boundaryChunkFrames * NormalizedPCMRing.channelCount)
        boundaryScratch.deallocate()
    }

    /// Producer side (the work queue). `samples` holds `frames` interleaved stereo frames. Every
    /// sample reaching the rings is finite and within ±`sampleBound` (AUD-012 C1).
    public func write(_ samples: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let count = frames * NormalizedPCMRing.channelCount
        if envelope.isUnity && PCMSanitizer.isClean(samples, count: count, bound: sampleBound) {
            writeRings(samples, count: count)
            envelope.noteLast(left: samples[count - 2], right: samples[count - 1])
            return
        }
        var offset = 0
        while offset < frames {
            let n = min(frames - offset, NormalizedPCMRing.boundaryChunkFrames)
            let chunkCount = n * NormalizedPCMRing.channelCount
            boundaryScratch.update(from: samples + offset * NormalizedPCMRing.channelCount, count: chunkCount)
            let replaced = PCMSanitizer.sanitize(boundaryScratch, count: chunkCount, bound: sampleBound)
            if replaced > 0 { _ = sanitized.add(replaced, ordering: .relaxed) }
            envelope.apply(boundaryScratch, frames: n)
            writeRings(boundaryScratch, count: chunkCount)
            offset += n
        }
    }

    @inline(__always)
    private func writeRings(_ samples: UnsafePointer<Float>, count: Int) {
        ring.write(samples, count: count)
        tapRing?.write(samples, count: count)
        if recordingState.armed.load(ordering: .acquiring) {   // REC-004-R8: only while a recording takes audio
            recordingRing.write(samples, count: count)
            recordingState.noteWrite(atNanoseconds: MonotonicClock.nowNanoseconds())
        }
    }

    // MARK: - REC-004 recording tap (control side arms and disarms; one consumer reads)

    /// Empties the recording tap and starts writing to it. Control side.
    public func armRecordingTap() {
        recordingState.armed.store(false, ordering: .releasing)
        recordingRing.drain()
        recordingState.restart(droppedSamples: recordingRing.droppedSamples)
        recordingState.armed.store(true, ordering: .releasing)
    }

    /// Stops writing to the recording tap and empties it.
    public func disarmRecordingTap() {
        recordingState.armed.store(false, ordering: .releasing)
        recordingRing.drain()
    }

    /// The recording tap's reader (one consumer: the recording's audio feed).
    public var recordingTap: any RecordingTapReading { recordingReader }

    // MARK: - AUD-012 handoff (producer side: the analysis queue)

    /// Samples replaced by the boundary or the analyzer's input stage since creation.
    public var sanitizedSampleCount: Int { sanitized.load(ordering: .relaxed) }

    /// Counts replacements made before the ring (the analyzer's input stage).
    public func recordSanitized(_ count: Int) {
        guard count > 0 else { return }
        _ = sanitized.add(count, ordering: .relaxed)
    }

    /// The switch envelope's phase.
    public var handoffPhase: HandoffEnvelope.Phase { envelope.phase }

    /// The switch envelope (tests and diagnostics).
    public var handoffEnvelope: HandoffEnvelope { envelope }

    /// Starts (or continues) the fade to silence; the old source keeps delivering.
    public func beginFadeOut() { envelope.beginFadeOut() }

    /// Completes a fade-out that had no more audio: a ramp from the last written frame to exact 0
    /// over min(remaining, 1,024) frames. Then silent. Returns the frames written.
    @discardableResult
    public func completeFadeOut() -> Int {
        let total = envelope.forcedFrames
        if total > 0 {
            let left = envelope.lastLeft
            let right = envelope.lastRight
            var index = 0
            while index < total {
                let n = min(total - index, NormalizedPCMRing.boundaryChunkFrames)
                HandoffEnvelope.forcedRamp(into: boundaryScratch, from: index, frames: n, total: total, left: left, right: right)
                writeRings(boundaryScratch, count: n * NormalizedPCMRing.channelCount)
                index += n
            }
        }
        if envelope.phase != .unity { envelope.markSilent() }
        return total
    }

    /// Starts the fade-in of the new source (after `resetForHandoff`).
    public func beginFadeIn() { envelope.beginFadeIn() }

    /// A source switch's new session (C1.6): empties the tap and restarts the counters, keeps
    /// projectM's ring, advances the generation after the drain, then writes `silenceFrames` zero
    /// frames to both rings. The envelope is left silent; `beginFadeIn()` ramps from 0.
    public func resetForHandoff(silenceFrames: Int = HandoffEnvelope.silenceFrames) {
        disarmRecordingTap()   // REC-004-R5: the new source never reaches a recording
        overflowBaseline.store(ring.droppedSamples, ordering: .relaxed)
        if let tapRing {
            tapRing.drain()
            tapOverflowBaseline.store(tapRing.droppedSamples, ordering: .relaxed)
        }
        freshnessDropped.store(0, ordering: .relaxed)
        sessionGeneration.advance()   // after the drain (ANL-016-R9, AUD-012-R8)
        envelope.markSilent()
        let chunk = NormalizedPCMRing.boundaryChunkFrames
        boundaryScratch.update(repeating: 0, count: chunk * NormalizedPCMRing.channelCount)
        var written = 0
        while written < silenceFrames {
            let n = min(silenceFrames - written, chunk)
            writeRings(boundaryScratch, count: n * NormalizedPCMRing.channelCount)
            written += n
        }
    }

    /// Reads the analysis tap (no freshness rule); nil when the ring has no tap. One consumer only:
    /// the analysis worker.
    public var analysisTap: (any NormalizedPCMReader)? { tapReader }

    /// Frames buffered in the analysis tap (0 without a tap).
    public var analysisTapAvailableFrames: Int {
        (tapRing?.availableToRead ?? 0) / NormalizedPCMRing.channelCount
    }

    /// Frames the analysis tap dropped (drop-oldest) since the last `reset()` (0 without a tap).
    public var analysisTapDroppedFrames: Int {
        guard let tapRing else { return 0 }
        return (tapRing.droppedSamples - tapOverflowBaseline.load(ordering: .relaxed)) / NormalizedPCMRing.channelCount
    }

    /// Consumer side (the render loop): applies the freshness rule, then reads.
    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard maxFrames > 0 else { return 0 }
        let backlog = availableFrames
        lastBacklog.store(backlog, ordering: .relaxed)
        if backlog > NormalizedPCMRing.freshnessFrames {
            let skipped = ring.discard(keepingNewest: NormalizedPCMRing.freshnessFrames * NormalizedPCMRing.channelCount)
            _ = freshnessDropped.add(skipped / NormalizedPCMRing.channelCount, ordering: .relaxed)
        }
        return readAll(into: dst, maxFrames: maxFrames)
    }

    /// Reads without the freshness rule (tests and diagnostics).
    func readAll(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        ring.read(into: dst, maxCount: maxFrames * NormalizedPCMRing.channelCount) / NormalizedPCMRing.channelCount
    }

    /// Frames currently buffered.
    public var availableFrames: Int { ring.availableToRead / NormalizedPCMRing.channelCount }

    /// Frames buffered when the latest `read` started (before the freshness skip).
    public var lastReadBacklogFrames: Int { lastBacklog.load(ordering: .relaxed) }

    /// Frames lost because the reader fell more than 0.5 s behind (drop-oldest).
    public var overflowDroppedFrames: Int {
        (ring.droppedSamples - overflowBaseline.load(ordering: .relaxed)) / NormalizedPCMRing.channelCount
    }

    /// Frames skipped by the freshness rule.
    public var freshnessDroppedFrames: Int { freshnessDropped.load(ordering: .relaxed) }

    public var droppedFrames: Int { overflowDroppedFrames + freshnessDroppedFrames }

    /// Empties the ring and keeps the counters: the source jumped in its content (AUD-006), which
    /// is not a new session. Safe while the reader runs.
    public func discardBuffered() {
        ring.drain()
        tapRing?.drain()
        recordingRing.drain()   // REC-004: a seek is not a new session; the tap stays armed
    }

    /// Empties the ring and restarts the counters (new session). Safe while the reader runs.
    public func reset() {
        disarmRecordingTap()   // REC-004-R5: a new session ends a recording's audio
        ring.drain()
        overflowBaseline.store(ring.droppedSamples, ordering: .relaxed)
        if let tapRing {
            tapRing.drain()
            tapOverflowBaseline.store(tapRing.droppedSamples, ordering: .relaxed)
        }
        freshnessDropped.store(0, ordering: .relaxed)
        lastBacklog.store(0, ordering: .relaxed)
        envelope.reset()              // AUD-012: a session that is not a handoff starts at unity
        sessionGeneration.advance()   // after the drains (ANL-016-R9)
    }

    /// Capture sessions begun since creation (ANL-016-R9): increased by every `reset()`.
    public var analysisSessionGeneration: UInt64 { sessionGeneration.value }
}

/// The ring's session counter, shared with its tap reader.
final class SessionGeneration: Sendable {
    private let counter = Atomic<UInt64>(0)
    func advance() { counter.add(1, ordering: .releasing) }
    var value: UInt64 { counter.load(ordering: .acquiring) }
}

/// The consumer side of a `NormalizedPCMRing`'s analysis tap (ANL-001-R9): reads every buffered
/// stereo frame in order, without the main ring's freshness rule. Real-time safe like the ring.
final class AnalysisTapReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let ring: SPSCRingBuffer
    private let generation: SessionGeneration

    init(ring: SPSCRingBuffer, generation: SessionGeneration) {
        self.ring = ring
        self.generation = generation
    }

    var analysisSessionGeneration: UInt64 { generation.value }

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard maxFrames > 0 else { return 0 }
        return ring.read(into: dst, maxCount: maxFrames * NormalizedPCMRing.channelCount) / NormalizedPCMRing.channelCount
    }
}
