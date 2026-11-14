// MIDIRefreshCoalescer.swift — one refresh per burst of system notifications (MIDI-001-R6; research
// MIDI-001-D3).
//
// The first signal in a quiet period schedules one refresh after the coalescing delay; signals before
// that refresh starts are absorbed; the refresh clears the pending flag before it reads, so a signal
// during or after the read schedules the next one. Latency is bounded by the delay plus one read, even
// under a steady stream (a restarting debounce would not be).
import Dispatch
import Synchronization

/// The pure gate (no clock: the scheduler supplies the delay).
public struct MIDIRefreshCoalescer: Sendable, Equatable {
    public private(set) var isPending = false
    /// Signals absorbed while a refresh was pending (diagnostic count, never stored).
    public private(set) var absorbed = 0

    public init() {}

    /// A signal arrived: true when the caller must schedule a refresh.
    public mutating func signal() -> Bool {
        if isPending {
            absorbed += 1
            return false
        }
        isPending = true
        return true
    }

    /// The scheduled refresh starts (before it reads the system).
    public mutating func beginRefresh() { isPending = false }

    /// Discovery stopped: nothing is pending any more.
    public mutating func reset() {
        isPending = false
        absorbed = 0
    }
}

/// Runs refresh work after a delay, one item at a time (serial).
public struct MIDIRefreshScheduler: Sendable {
    public let schedule: @Sendable (_ afterNanoseconds: UInt64, _ work: @escaping @Sendable () -> Void) -> Void

    public init(schedule: @escaping @Sendable (_ afterNanoseconds: UInt64, _ work: @escaping @Sendable () -> Void) -> Void) {
        self.schedule = schedule
    }

    /// One private serial queue (utility QoS): refreshes never overlap and never run on the main thread.
    public static func serialQueue(label: String = "projectm.midi.discovery") -> MIDIRefreshScheduler {
        let queue = DispatchQueue(label: label, qos: .utility)
        return MIDIRefreshScheduler { (afterNanoseconds: UInt64, work: @escaping @Sendable () -> Void) -> Void in
            let delay: DispatchTimeInterval = .nanoseconds(Int(clamping: afterNanoseconds))
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}

/// A scheduler for tests: work waits until `runAll()`; no clock, no threads.
public final class ManualMIDIScheduler: Sendable {
    private let queue = Mutex<[(delay: UInt64, work: @Sendable () -> Void)]>([])

    public init() {}

    public var scheduler: MIDIRefreshScheduler {
        MIDIRefreshScheduler { [self] (afterNanoseconds: UInt64, work: @escaping @Sendable () -> Void) -> Void in
            queue.withLock { (items: inout [(delay: UInt64, work: @Sendable () -> Void)]) -> Void in
                items.append((delay: afterNanoseconds, work: work))
            }
        }
    }

    public var pendingCount: Int { queue.withLock { (items: inout [(delay: UInt64, work: @Sendable () -> Void)]) -> Int in items.count } }

    /// The delays of the pending items, in order.
    public var pendingDelays: [UInt64] {
        queue.withLock { (items: inout [(delay: UInt64, work: @Sendable () -> Void)]) -> [UInt64] in
            items.map { (item: (delay: UInt64, work: @Sendable () -> Void)) -> UInt64 in item.delay }
        }
    }

    /// Runs pending work in order, including work scheduled while running; returns how many ran.
    @discardableResult
    public func runAll() -> Int {
        var ran = 0
        while true {
            let next: (@Sendable () -> Void)? = queue.withLock { (items: inout [(delay: UInt64, work: @Sendable () -> Void)]) -> (@Sendable () -> Void)? in
                items.isEmpty ? nil : items.removeFirst().work
            }
            guard let next else { return ran }
            next()
            ran += 1
        }
    }
}
