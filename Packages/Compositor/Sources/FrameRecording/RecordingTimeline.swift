// RecordingTimeline.swift — REC-003 timestamp and frame-rate rules on REC-006's exact frame grid
// (REC-003-R5, R11; REC-006-R2, R3, R11; contracts/frame-rate.md C1 in specs/164-rec-006-record-frame-rate;
// research REC-006-D1, D2). Plain Swift; builds on Linux.
//
// Slot n of the output is at n × I ticks of 1/600 s from the first admitted frame (I = 600 / fps: 25, 20
// or 10). A frame at t ns after the origin belongs to the slot whose half-interval window holds it:
// m = (t × fps + 0.5 s) / 1 s in integer arithmetic. Per frame, in order:
//   1. before the origin, or not later than the last written frame's time → `droppedNotIncreasing`;
//   2. m × I at or beyond the duration limit → `durationReached` (the recording stops);
//   3. m below the next free slot (that slot is written or passed) → `skippedRate` (not a drop);
//   4. the frame is before its slot time and the next frame, predicted one render interval d later
//      (the last offered interval, at most one slot), would be nearer the slot by more than 1 µs and still land
//      well inside its window (t + 1.5 d before the window's end) → `skippedRate` (a nearer frame comes);
//   5. otherwise `candidate(tick: m × I)`; it becomes the last written tick only through `markWritten`
//      (the caller writes it only when the bounded queue admits it).
// Slots that never get a frame are not filled: the writer counts them as dropped (REC-006-D3).
// Constant-time integer work; no allocation. Not thread-safe: one thread (the frame loop) drives it.

public struct RecordingTimeline: Sendable {
    public enum Admission: Equatable, Sendable {
        case candidate(tick: Int64)
        case skippedRate
        case droppedNotIncreasing
        case durationReached
    }

    private static let second: Int64 = 1_000_000_000

    public let settings: RecordingSettings
    /// The first admitted frame's time (nil before the first frame).
    public private(set) var originNanoseconds: UInt64?
    /// The last written tick (nil before the first written frame).
    public private(set) var lastWrittenTick: Int64?
    /// Frames written so far.
    public private(set) var writtenCount = 0

    /// The next slot that may still be written.
    private var nextSlot: Int64 = 0
    /// Time (ns after the origin) of the last written frame.
    private var lastWrittenOffset: Int64?
    /// Time (ns after the origin) of the last offered frame at or after the origin.
    private var lastOfferedOffset: Int64?
    /// The candidate handed out last (its tick and time), so `markWritten` can record the time.
    private var pending: (tick: Int64, offset: Int64)?

    public init(settings: RecordingSettings = .standard) {
        self.settings = settings
    }

    /// Frames per second of the grid.
    private var fps: Int64 { Int64(settings.maxFrameRate) }

    /// The next slot's tick (nil before the first written frame).
    public var nextDueTick: Int64? { lastWrittenTick == nil ? nil : nextSlot * settings.frameIntervalTicks }

    /// The tick of the slot a time falls in, relative to the origin (0 before the first frame).
    public func tick(forNanoseconds ns: UInt64) -> Int64 {
        guard let origin = originNanoseconds, ns >= origin else { return 0 }
        return slot(offset: Int64(ns - origin)) * settings.frameIntervalTicks
    }

    /// The slot whose window [n − ½, n + ½) intervals holds `offset` ns.
    private func slot(offset: Int64) -> Int64 {
        (offset * fps + Self.second / 2) / Self.second
    }

    public mutating func admit(presentationNanoseconds ns: UInt64) -> Admission {
        if originNanoseconds == nil { originNanoseconds = ns }
        guard let origin = originNanoseconds, ns >= origin else { return .droppedNotIncreasing }
        let t = Int64(ns - origin)
        let previous: Int64? = lastOfferedOffset
        if let last = lastWrittenOffset, t <= last { return .droppedNotIncreasing }
        lastOfferedOffset = t
        let m: Int64 = slot(offset: t)
        let tick: Int64 = m * settings.frameIntervalTicks
        if tick >= settings.maxDurationTicks { return .durationReached }
        if m < nextSlot { return .skippedRate }
        if let previous, shouldWaitForNearerFrame(t: t, previous: previous, slot: m) { return .skippedRate }
        pending = (tick, t)
        return .candidate(tick: tick)
    }

    /// Rule 4, in units of ns × fps (slot times are then whole multiples of 1 s).
    private func shouldWaitForNearerFrame(t: Int64, previous: Int64, slot m: Int64) -> Bool {
        let scaledT: Int64 = t * fps
        let slotTime: Int64 = m * Self.second
        guard scaledT < slotTime else { return false }
        let d: Int64 = min(max(t - previous, 0) * fps, Self.second)   // at most one slot
        guard d > 0 else { return false }
        let windowEnd: Int64 = slotTime + Self.second / 2
        let predicted: Int64 = scaledT + d
        guard scaledT + d + d / 2 < windowEnd else { return false }
        // Nearer by more than 1 µs: closer times are a tie (clock rounding), and ties go to the earlier frame.
        let tieTolerance: Int64 = 1_000 * fps
        return abs(predicted - slotTime) + tieTolerance < slotTime - scaledT
    }

    /// The candidate was written. Ticks must increase (a smaller one is ignored).
    public mutating func markWritten(tick: Int64) {
        if let last = lastWrittenTick, tick <= last { return }
        let interval = settings.frameIntervalTicks
        if let pending, pending.tick == tick { lastWrittenOffset = pending.offset }
        pending = nil
        nextSlot = tick / interval + 1
        lastWrittenTick = tick
        writtenCount += 1
    }

    /// Where the session ends: one interval after the last written frame (nil with no frame).
    public var endTick: Int64? { lastWrittenTick.map { (last: Int64) -> Int64 in last + settings.frameIntervalTicks } }

    /// Recorded length in seconds (0 before the first frame).
    public var recordedSeconds: Double { Double(endTick ?? 0) / Double(RecordingSettings.timescale) }
}
