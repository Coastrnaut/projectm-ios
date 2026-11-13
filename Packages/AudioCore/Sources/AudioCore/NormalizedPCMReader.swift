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
import Synchronization

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

    /// `analysisTapCapacityFrames` > 0 adds an analysis tap of that many stereo frames; 0 (the
    /// default) or less means no tap.
    public init(analysisTapCapacityFrames: Int = 0) {
        if analysisTapCapacityFrames > 0 {
            let tap = SPSCRingBuffer(capacity: analysisTapCapacityFrames * NormalizedPCMRing.channelCount)
            tapRing = tap
            tapReader = AnalysisTapReader(ring: tap)
        } else {
            tapRing = nil
            tapReader = nil
        }
    }

    /// Producer side (the work queue). `samples` holds `frames` interleaved stereo frames.
    public func write(_ samples: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        ring.write(samples, count: frames * NormalizedPCMRing.channelCount)
        tapRing?.write(samples, count: frames * NormalizedPCMRing.channelCount)
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
    }

    /// Empties the ring and restarts the counters (new session). Safe while the reader runs.
    public func reset() {
        ring.drain()
        overflowBaseline.store(ring.droppedSamples, ordering: .relaxed)
        if let tapRing {
            tapRing.drain()
            tapOverflowBaseline.store(tapRing.droppedSamples, ordering: .relaxed)
        }
        freshnessDropped.store(0, ordering: .relaxed)
        lastBacklog.store(0, ordering: .relaxed)
    }
}

/// The consumer side of a `NormalizedPCMRing`'s analysis tap (ANL-001-R9): reads every buffered
/// stereo frame in order, without the main ring's freshness rule. Real-time safe like the ring.
final class AnalysisTapReader: NormalizedPCMReader, @unchecked Sendable {
    private let ring: SPSCRingBuffer

    init(ring: SPSCRingBuffer) { self.ring = ring }

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard maxFrames > 0 else { return 0 }
        return ring.read(into: dst, maxCount: maxFrames * NormalizedPCMRing.channelCount) / NormalizedPCMRing.channelCount
    }
}
