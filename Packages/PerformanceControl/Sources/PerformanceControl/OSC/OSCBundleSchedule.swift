// OSCBundleSchedule.swift — timing for OSC bundles (OSC-006; specs/278-osc-006-osc-bundles, contract B1).
//
// * A bundle's NTP time tag is mapped to the dispatcher's monotonic clock once, at receipt, from one read of the
//   monotonic clock and one of the wall clock (OSC-006-R2, D1): `due = monotonicNow + (tag − wallNow)`. The
//   difference is a signed 32.32 value, so it stays right across the 2036 NTP era. Sender and receiver wall clocks
//   are assumed roughly in sync; a scheduled due time never moves when the wall clock changes later.
// * Pending messages sit in a bounded min-heap ordered by (due, arrival sequence), so equal due times keep arrival
//   order (OSC-006-R5, D9). Pure Swift apart from `Date` for the system wall clock; runs on Linux.
import Foundation

/// The fixed late-message policy and bounds (OSC-006-R6 to R8, D4). Nanoseconds and messages.
public struct OSCBundleTiming: Sendable, Equatable {
    /// Up to this late is on time.
    public var onTimeTolerance: UInt64
    /// Later than this is dropped; between the tolerance and this it is applied at once and counted late.
    public var maximumLateness: UInt64
    /// Further ahead than this is dropped, never clamped.
    public var horizon: UInt64
    /// Pending messages at most.
    public var capacity: Int

    public init(onTimeTolerance: UInt64, maximumLateness: UInt64, horizon: UInt64, capacity: Int) {
        self.onTimeTolerance = onTimeTolerance
        self.maximumLateness = maximumLateness
        self.horizon = horizon
        self.capacity = capacity
    }

    public static let `default` = OSCBundleTiming(onTimeTolerance: 20_000_000, maximumLateness: 1_000_000_000,
                                                  horizon: 10_000_000_000, capacity: 256)
}

/// The wall clock as an NTP time tag (OSC-006-D2). Tests inject a fake.
public struct OSCWallClock: Sendable {
    public let now: @Sendable () -> OSCTimeTag

    public init(now: @escaping @Sendable () -> OSCTimeTag) { self.now = now }

    /// Seconds from 1900-01-01 (NTP) to 1970-01-01 (Unix).
    public static let unixToNTPSeconds: Double = 2_208_988_800

    public static let system = OSCWallClock(now: { () -> OSCTimeTag in
        OSCTimeTag(ntpSeconds: Date().timeIntervalSince1970 + OSCWallClock.unixToNTPSeconds)
    })
}

extension OSCTimeTag {
    /// A tag from NTP seconds (fractional part rounded down to 1/2³² s); the era wraps modulo 2³² s.
    public init(ntpSeconds: Double) {
        let whole = ntpSeconds.rounded(.down)
        let fraction = (ntpSeconds - whole) * 4_294_967_296.0
        let wrapped = UInt64(whole.truncatingRemainder(dividingBy: 4_294_967_296.0))
        self.init(seconds: UInt32(truncatingIfNeeded: wrapped), fraction: UInt32(min(fraction, 4_294_967_295.0)))
    }

    /// `self` moved by `nanoseconds` (tests and senders' arithmetic).
    public func adding(nanoseconds: Int64) -> OSCTimeTag {
        let delta: Int64 = Int64((Double(nanoseconds) * 4_294_967_296.0 / 1_000_000_000.0).rounded())
        return OSCTimeTag(rawValue: rawValue &+ UInt64(bitPattern: delta))
    }

    /// Signed nanoseconds from `other` to `self`, the seconds clamped to ±10⁶ (far outside every bound).
    public func nanoseconds(since other: OSCTimeTag) -> Int64 {
        let fixed = Int64(bitPattern: rawValue &- other.rawValue)
        let seconds: Int64 = fixed >> 32
        let fraction: Int64 = fixed & 0xFFFF_FFFF
        let clamped: Int64 = min(max(seconds, -1_000_000), 1_000_000)
        return clamped * 1_000_000_000 + (fraction * 1_000_000_000) >> 32
    }

    /// OSC 1.0 comparison: the later of two tags by NTP value (an inner tag never precedes its container's).
    /// "Immediately" is earlier than every other tag; otherwise the signed 32.32 difference decides (era-safe).
    static func latest(_ a: OSCTimeTag, _ b: OSCTimeTag) -> OSCTimeTag {
        if a.isImmediately { return b }
        if b.isImmediately { return a }
        return b.nanoseconds(since: a) > 0 ? b : a
    }
}

/// Both clocks read once at receipt (OSC-006-R2).
public struct OSCTimeMapping: Sendable, Equatable {
    public let monotonicNow: UInt64
    public let wallNow: OSCTimeTag

    public init(monotonicNow: UInt64, wallNow: OSCTimeTag) {
        self.monotonicNow = monotonicNow
        self.wallNow = wallNow
    }

    /// Signed nanoseconds from receipt to the tag (negative: late); nil for "immediately".
    public func offset(for tag: OSCTimeTag) -> Int64? {
        tag.isImmediately ? nil : tag.nanoseconds(since: wallNow)
    }

    /// The tag's monotonic due time for a tag at or after receipt; nil for "immediately" or a late tag.
    public func due(for tag: OSCTimeTag) -> UInt64? {
        guard let offset = offset(for: tag), offset >= 0 else { return nil }
        return monotonicNow &+ UInt64(offset)
    }
}

public struct OSCScheduledMessage: Sendable, Equatable {
    public let message: OSCMessage
    /// Monotonic nanoseconds.
    public let due: UInt64
    /// Arrival order across datagrams, depth-first within one.
    public let sequence: UInt64

    public init(message: OSCMessage, due: UInt64, sequence: UInt64) {
        self.message = message
        self.due = due
        self.sequence = sequence
    }

    func precedes(_ other: OSCScheduledMessage) -> Bool {
        due != other.due ? due < other.due : sequence < other.sequence
    }
}

/// Pending messages ordered by (due, sequence): O(log n) insert and removal (OSC-006-R12).
public struct OSCBundleSchedule: Sendable {
    private var heap: [OSCScheduledMessage] = []

    public init() {}

    public var count: Int { heap.count }
    public var isEmpty: Bool { heap.isEmpty }
    public var earliestDue: UInt64? { heap.first?.due }

    public mutating func insert(_ entry: OSCScheduledMessage) {
        heap.append(entry)
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard heap[child].precedes(heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    /// Removes and returns every entry due at `now`, in (due, sequence) order.
    public mutating func takeDue(now: UInt64) -> [OSCScheduledMessage] {
        var result: [OSCScheduledMessage] = []
        while let first = heap.first, first.due <= now { result.append(removeFirst()) }
        return result
    }

    public mutating func removeAll() { heap.removeAll() }

    private mutating func removeFirst() -> OSCScheduledMessage {
        let first = heap[0]
        let last = heap.removeLast()
        guard !heap.isEmpty else { return first }
        heap[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var best = parent
            if left < heap.count, heap[left].precedes(heap[best]) { best = left }
            if right < heap.count, heap[right].precedes(heap[best]) { best = right }
            if best == parent { break }
            heap.swapAt(parent, best)
            parent = best
        }
        return first
    }
}

/// Why a bundle message was not applied or scheduled (OSC-006-R6 to R8).
public enum OSCBundleDrop: Sendable, Hashable {
    /// More than the maximum lateness late.
    case tooLate
    /// Further ahead than the horizon.
    case beyondHorizon
    /// The pending queue had no room for the datagram's future messages.
    case queueFull
}
