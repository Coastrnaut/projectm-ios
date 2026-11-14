// RecordingTap.swift — REC-004 the recording tap's consumer side (specs/134-rec-004-recording-audio,
// contract C2, research REC-004-D1, D2).
//
// The tap is part of `NormalizedPCMRing`: Float32 interleaved stereo at 44.1 kHz, the normalized source
// audio before input trim, noise gate and latency offset (those act on readers of the analysis tap).
// `read` drains what is buffered and dates it: the producer stores the uptime time of each armed write
// and then bumps a counter; when no write happened during the drain, the last frame drained was written
// at the stored time. When one did, the newer time is used (an error of at most one write, which the
// recorder's contiguity window absorbs). Real-time safe: no allocation, no lock, never blocks.
import Synchronization

/// One drained chunk of the recording tap.
public struct RecordingTapChunk: Sendable, Equatable {
    /// Stereo frames read (0 when nothing was buffered).
    public let frames: Int
    /// Uptime-clock time of the chunk's first frame (0 when `frames` is 0).
    public let firstSampleNanoseconds: UInt64

    public init(frames: Int, firstSampleNanoseconds: UInt64) {
        self.frames = frames
        self.firstSampleNanoseconds = firstSampleNanoseconds
    }
}

/// Reads the recording tap. One consumer at a time.
public protocol RecordingTapReading: AnyObject, Sendable {
    /// Drains up to `maxFrames` stereo frames into `dst` (room for `2 × maxFrames` floats) and dates them.
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> RecordingTapChunk
    /// True while the producer writes to the tap (false after a new capture session began).
    var isArmed: Bool { get }
    /// Frames the tap dropped (drop-oldest) since it was armed.
    var droppedFrames: Int { get }
}

/// The producer-side state shared with the reader.
final class RecordingTapState: Sendable {
    let armed = Atomic<Bool>(false)
    let writes = Atomic<UInt64>(0)
    let lastWriteNanoseconds = Atomic<UInt64>(0)
    let droppedBaseline = Atomic<Int>(0)

    func noteWrite(atNanoseconds ns: UInt64) {
        lastWriteNanoseconds.store(ns, ordering: .releasing)
        writes.add(1, ordering: .releasing)
    }

    func restart(droppedSamples: Int) {
        lastWriteNanoseconds.store(0, ordering: .relaxed)
        droppedBaseline.store(droppedSamples, ordering: .relaxed)
    }
}

final class RecordingTapReader: RecordingTapReading, @unchecked Sendable {
    private let ring: SPSCRingBuffer
    private let state: RecordingTapState

    init(ring: SPSCRingBuffer, state: RecordingTapState) {
        self.ring = ring
        self.state = state
    }

    var isArmed: Bool { state.armed.load(ordering: .acquiring) }

    var droppedFrames: Int { (ring.droppedSamples - state.droppedBaseline.load(ordering: .relaxed)) / NormalizedPCMRing.channelCount }

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> RecordingTapChunk {
        guard maxFrames > 0 else { return RecordingTapChunk(frames: 0, firstSampleNanoseconds: 0) }
        let before = state.writes.load(ordering: .acquiring)
        var newest = state.lastWriteNanoseconds.load(ordering: .acquiring)
        let frames = ring.read(into: dst, maxCount: maxFrames * NormalizedPCMRing.channelCount) / NormalizedPCMRing.channelCount
        guard frames > 0 else { return RecordingTapChunk(frames: 0, firstSampleNanoseconds: 0) }
        if state.writes.load(ordering: .acquiring) != before {
            newest = state.lastWriteNanoseconds.load(ordering: .acquiring)
        }
        let span = UInt64((Double(frames - 1) * 1e9 / NormalizedPCMRing.sampleRate).rounded())
        return RecordingTapChunk(frames: frames, firstSampleNanoseconds: newest > span ? newest - span : 0)
    }
}
