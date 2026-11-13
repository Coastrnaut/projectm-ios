// RecordingTimeline.swift — REC-003 timestamp and frame-rate rules (REC-003-R5, R6, R11; research
// REC-003-D4). Plain Swift; builds on Linux.
//
// Each frame's time is the frame loop's presentation time in nanoseconds. The first admitted frame
// is tick 0; later frames are rounded to the nearest 1/600 s from it. Per frame, in order:
//   1. a tick not later than the last written tick → `droppedNotIncreasing` (never written);
//   2. a tick at or beyond the duration limit → `durationReached` (the recording stops);
//   3. a tick earlier than the next slot less a quarter interval → `skippedRate`. Slots advance by
//      one interval from the previous slot (so a 120 Hz loop averages 30 fps, not 40), and restart
//      from the frame's own time when the loop fell behind (no burst after a stall);
//   4. otherwise `candidate(tick)`; it becomes the last written tick only through `markWritten`
//      (the caller writes it only when the bounded queue admits it).
// Not thread-safe: one thread (the frame loop) drives a timeline.

public struct RecordingTimeline: Sendable {
    public enum Admission: Equatable, Sendable {
        case candidate(tick: Int64)
        case skippedRate
        case droppedNotIncreasing
        case durationReached
    }

    public let settings: RecordingSettings
    /// The first admitted frame's time (nil before the first frame).
    public private(set) var originNanoseconds: UInt64?
    /// The last written tick (nil before the first written frame).
    public private(set) var lastWrittenTick: Int64?
    /// The next frame slot (nil before the first written frame).
    public private(set) var nextDueTick: Int64?
    /// Frames written so far.
    public private(set) var writtenCount = 0

    public init(settings: RecordingSettings = .standard) {
        self.settings = settings
    }

    /// The tick of a time relative to the origin (rounded to the nearest; negative before it).
    public func tick(forNanoseconds ns: UInt64) -> Int64 {
        guard let origin = originNanoseconds else { return 0 }
        let delta = ns >= origin ? Double(ns - origin) : -Double(origin - ns)
        return Int64((delta * Double(RecordingSettings.timescale) / 1e9).rounded())
    }

    public mutating func admit(presentationNanoseconds ns: UInt64) -> Admission {
        if originNanoseconds == nil { originNanoseconds = ns }
        let t = tick(forNanoseconds: ns)
        if let last = lastWrittenTick {
            if t <= last { return .droppedNotIncreasing }
            if t >= settings.maxDurationTicks { return .durationReached }
            let interval = settings.frameIntervalTicks
            if t < (nextDueTick ?? last + interval) - interval / 4 { return .skippedRate }
        } else if t < 0 {
            return .droppedNotIncreasing
        }
        return .candidate(tick: t)
    }

    /// The candidate was written. Ticks must increase (a smaller one is ignored).
    public mutating func markWritten(tick: Int64) {
        if let last = lastWrittenTick, tick <= last { return }
        let interval = settings.frameIntervalTicks
        // The next slot: one interval after this one, or one interval after this frame when it came late.
        nextDueTick = max((nextDueTick ?? tick) + interval, tick + interval)
        lastWrittenTick = tick
        writtenCount += 1
    }

    /// Where the session ends: one interval after the last written frame (nil with no frame).
    public var endTick: Int64? { lastWrittenTick.map { (last: Int64) -> Int64 in last + settings.frameIntervalTicks } }

    /// Recorded length in seconds (0 before the first frame).
    public var recordedSeconds: Double { Double(endTick ?? 0) / Double(RecordingSettings.timescale) }
}
