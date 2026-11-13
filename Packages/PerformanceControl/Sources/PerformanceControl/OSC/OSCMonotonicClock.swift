// OSCMonotonicClock.swift — time and scheduling for the OSC rate limiter, and the refresh gate that
// keeps a flood off the main thread (OSC-009; research OSC-009-D2, D5, D7).
//
// Pure Swift (standard library, Synchronization), so it runs on Linux; no wall clock anywhere.
import Synchronization

/// Monotonic nanoseconds. The default measures `ContinuousClock` from its creation; tests inject a
/// fake that they advance by hand.
public struct OSCMonotonicClock: Sendable {
    public let now: @Sendable () -> UInt64

    public init(now: @escaping @Sendable () -> UInt64) { self.now = now }

    public static func continuous() -> OSCMonotonicClock {
        let origin = ContinuousClock.now
        return OSCMonotonicClock(now: { () -> UInt64 in
            let parts = (ContinuousClock.now - origin).components
            return UInt64(max(parts.seconds, 0)) * 1_000_000_000 + UInt64(max(parts.attoseconds, 0) / 1_000_000_000)
        })
    }
}

/// Runs `work` after about `delay` nanoseconds, never on the main actor (OSC-009-R8).
public struct OSCFlushScheduler: Sendable {
    public let schedule: @Sendable (_ delayNanoseconds: UInt64, _ work: @escaping @Sendable () -> Void) -> Void

    public init(schedule: @escaping @Sendable (_ delayNanoseconds: UInt64, _ work: @escaping @Sendable () -> Void) -> Void) {
        self.schedule = schedule
    }

    /// A detached task that sleeps, then runs `work` (Swift concurrency's global executor).
    public static let sleepingTask = OSCFlushScheduler(schedule: { (delay: UInt64, work: @escaping @Sendable () -> Void) in
        Task.detached {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            work()
        }
    })
}

/// At most one refresh pending, started no sooner than `interval` after the previous one
/// (OSC-009-R11). `request` is called for every change on any thread; only a non-nil answer starts a
/// refresh, which calls `begin` when it runs and then reads the latest state.
public final class OSCRefreshGate: Sendable {
    /// 1/30 s.
    public static let defaultInterval: UInt64 = 33_333_333

    private struct State {
        var pending = false
        var lastRun: UInt64?
    }

    public let interval: UInt64
    private let state = Mutex(State())

    public init(interval: UInt64 = OSCRefreshGate.defaultInterval) { self.interval = interval }

    /// nil while a refresh is pending; otherwise marks one pending and returns the delay before it
    /// may run (0 when the interval has already passed).
    public func request(now: UInt64) -> UInt64? {
        state.withLock { s -> UInt64? in
            guard !s.pending else { return nil }
            s.pending = true
            guard let last = s.lastRun else { return 0 }
            let due = last &+ interval
            return due > now ? due - now : 0
        }
    }

    /// The pending refresh runs now; later changes may request the next one.
    public func begin(now: UInt64) {
        state.withLock { s in
            s.pending = false
            s.lastRun = now
        }
    }

    public var isPending: Bool { state.withLock { $0.pending } }
}
