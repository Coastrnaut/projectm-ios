// OutputFrameGate.swift — OUT-013 frame pacing per output (specs/281-out-013-frame-pacing, contract C1; research
// OUT-013-D2, D4).
//
// * One gate per output (per visual frame loop). A tick asks `tryBegin()` before it requests a drawable or renders:
//   while `maxFramesInFlight` frames are in flight (submitted, the GPU not done) the tick is dropped and counted; it
//   never waits, so the thread that ticks (the main thread) and the analysis queue are never held by a slow output.
// * `complete()` runs where the frame's completion is observed (Metal's completed handler on any thread, or the ANGLE
//   fence poll on the main thread). `abandon()` returns a slot that produced no frame (no drawable, a failed present).
// * `noteDrawableWait` arms a one-tick back-off after a drawable wait longer than `slowWaitFraction` of the refresh
//   interval, so the display can catch up without any queue (OUT-013-R7).
// * Lock-free: every value is an atomic; nothing allocates after init. Counts are local and in memory only.
import Synchronization

/// The rules of one output's pacing (data model `OutputPacingPolicy`).
public struct OutputPacingPolicy: Sendable, Equatable {
    /// Frames in flight at most (clamped to 1…3).
    public let maxFramesInFlight: Int
    /// A drawable wait longer than this fraction of the refresh interval skips the next tick.
    public let slowWaitFraction: Double

    public init(maxFramesInFlight: Int = 2, slowWaitFraction: Double = 0.5) {
        self.maxFramesInFlight = min(max(maxFramesInFlight, 1), 3)
        self.slowWaitFraction = slowWaitFraction
    }

    /// OUT-013-R2: two frames in flight; a wait over half a refresh interval backs off one tick.
    public static let standard = OutputPacingPolicy()
}

/// One output's pacing counts (OUT-013-R5).
public struct OutputPacingCounts: Sendable, Equatable {
    public var begun = 0
    public var completed = 0
    public var droppedInFlight = 0
    public var droppedNoDrawable = 0
    public var droppedBackOff = 0
    public var inFlight = 0
    public var maxInFlight = 0

    public init() {}

    /// All dropped ticks and frames, whatever the cause.
    public var dropped: Int { droppedInFlight + droppedNoDrawable + droppedBackOff }
}

/// Bounds one output's frames in flight without ever blocking (OUT-013-R2, R3).
public final class OutputFrameGate: Sendable {
    public let policy: OutputPacingPolicy
    private let inFlight = Atomic<Int>(0)
    private let maxSeen = Atomic<Int>(0)
    private let backOff = Atomic<Bool>(false)
    private let begun = Atomic<Int>(0)
    private let completed = Atomic<Int>(0)
    private let droppedInFlight = Atomic<Int>(0)
    private let droppedNoDrawable = Atomic<Int>(0)
    private let droppedBackOff = Atomic<Int>(0)

    public init(policy: OutputPacingPolicy = .standard) {
        self.policy = policy
    }

    /// True: render this tick (one slot taken). False: the tick is dropped and counted.
    public func tryBegin() -> Bool {
        if backOff.exchange(false, ordering: .acquiringAndReleasing) {
            droppedBackOff.wrappingAdd(1, ordering: .relaxed)
            return false
        }
        var current = inFlight.load(ordering: .acquiring)
        while true {
            guard current < policy.maxFramesInFlight else {
                droppedInFlight.wrappingAdd(1, ordering: .relaxed)
                return false
            }
            let (exchanged, original) = inFlight.compareExchange(expected: current, desired: current + 1,
                                                                 ordering: .acquiringAndReleasing)
            if exchanged { break }
            current = original
        }
        begun.wrappingAdd(1, ordering: .relaxed)
        raiseMaxSeen(to: current + 1)
        return true
    }

    /// The frame of a successful `tryBegin` completed (any thread).
    public func complete() {
        guard release() else { return }
        completed.wrappingAdd(1, ordering: .relaxed)
    }

    /// A successful `tryBegin` produced no frame (no drawable, nothing presented).
    public func abandon() {
        guard release() else { return }
        droppedNoDrawable.wrappingAdd(1, ordering: .relaxed)
    }

    /// OUT-013-R7: a drawable wait longer than `slowWaitFraction` of `refreshInterval` skips the next tick.
    public func noteDrawableWait(_ seconds: Double, refreshInterval: Double) {
        guard refreshInterval > 0, seconds > policy.slowWaitFraction * refreshInterval else { return }
        backOff.store(true, ordering: .releasing)
    }

    /// Whether the next tick will be skipped by the back-off.
    public var isBackingOff: Bool { backOff.load(ordering: .acquiring) }

    /// A snapshot of the counts.
    public var counts: OutputPacingCounts {
        var counts = OutputPacingCounts()
        counts.begun = begun.load(ordering: .relaxed)
        counts.completed = completed.load(ordering: .relaxed)
        counts.droppedInFlight = droppedInFlight.load(ordering: .relaxed)
        counts.droppedNoDrawable = droppedNoDrawable.load(ordering: .relaxed)
        counts.droppedBackOff = droppedBackOff.load(ordering: .relaxed)
        counts.inFlight = inFlight.load(ordering: .acquiring)
        counts.maxInFlight = maxSeen.load(ordering: .relaxed)
        return counts
    }

    /// Takes one frame out of flight; false when none was in flight (a stray report is ignored).
    private func release() -> Bool {
        var current = inFlight.load(ordering: .acquiring)
        while current > 0 {
            let (exchanged, original) = inFlight.compareExchange(expected: current, desired: current - 1,
                                                                 ordering: .acquiringAndReleasing)
            if exchanged { return true }
            current = original
        }
        return false
    }

    private func raiseMaxSeen(to value: Int) {
        var seen = maxSeen.load(ordering: .relaxed)
        while value > seen {
            let (exchanged, original) = maxSeen.compareExchange(expected: seen, desired: value, ordering: .relaxed)
            if exchanged { return }
            seen = original
        }
    }
}
