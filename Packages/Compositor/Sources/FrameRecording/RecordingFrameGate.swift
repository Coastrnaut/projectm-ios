// RecordingFrameGate.swift — REC-003 bounded frame queue and statistics (REC-003-R7; research
// REC-003-D5; Constitution VII: bounded queues with a tested overflow policy). Plain Swift; builds on
// Linux.
//
// The gate counts frames between "pixel buffer taken" (frame loop) and "appended or dropped"
// (writer queue). `tryAcquire` never waits: at capacity it refuses and the caller drops the frame.
import Synchronization

public final class RecordingFrameGate: Sendable {
    private struct State {
        var inFlight = 0
        var maxInFlight = 0
    }

    public let capacity: Int
    private let state = Mutex(State())

    public init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    /// Takes a slot, or returns false at capacity (the frame is dropped). Never waits.
    public func tryAcquire() -> Bool {
        state.withLock { (s: inout State) -> Bool in
            guard s.inFlight < capacity else { return false }
            s.inFlight += 1
            s.maxInFlight = max(s.maxInFlight, s.inFlight)
            return true
        }
    }

    /// Gives a slot back (after the frame was appended or dropped).
    public func release() {
        state.withLock { (s: inout State) -> Void in s.inFlight = max(s.inFlight - 1, 0) }
    }

    public var inFlight: Int { state.withLock { (s: inout State) -> Int in s.inFlight } }
    /// The most frames ever in flight at once.
    public var maxInFlight: Int { state.withLock { (s: inout State) -> Int in s.maxInFlight } }
}

/// What happened to the frames offered to a recording (REC-003-R7, R10).
public struct RecordingStatistics: Sendable, Equatable {
    /// Frames appended to the file.
    public var written = 0
    /// Dropped because the bounded queue was full (or no pixel buffer could be taken).
    public var droppedBusy = 0
    /// Dropped because the encoder was not ready for more data.
    public var droppedNotReady = 0
    /// Dropped because the time was not later than the last written frame's (REC-003-R5).
    public var droppedNotIncreasing = 0
    /// Skipped by the frame-rate cap (not a drop: the screen ran faster than the recording).
    public var skippedRate = 0
    /// REC-004: audio frames (44.1 kHz) appended, and dropped because the encoder was not ready.
    public var audioFramesWritten = 0
    public var audioFramesDropped = 0
    /// REC-006-R4, D3: output slots (on the frame grid, between the first and last appended frame) that got no
    /// frame: a stall, a render loop slower than the target, or any frame dropped above. Not filled by repeats.
    public var droppedSlots = 0

    public init() {}

    /// Every frame left out of the file except rate skips.
    public var dropped: Int { droppedBusy + droppedNotReady + droppedNotIncreasing }
}
