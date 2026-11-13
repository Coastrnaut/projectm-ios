// OSCRateLimiter.swift — token-bucket limits per source, across sources and per target (OSC-009;
// specs/041-osc-009-osc-rate-limiter, contract L1, research OSC-009-D1, D6).
//
// * Integer token buckets: one token is 1e9 units, refilled by `perSecond × elapsed nanoseconds` up to
//   `burst` tokens. Over any window of W seconds a bucket allows at most `burst + perSecond × W` takes.
//   Elapsed time is clamped to a full refill, so a clock jump cannot overflow; a clock that goes
//   backwards refills nothing. Every time is an argument (an injected monotonic clock), so the same
//   input always gives the same decisions.
// * Datagrams pass only when their source's bucket AND the global bucket both have a token; a dropped
//   datagram spends neither.
// * Targets coalesce: over its rate, a target holds only its newest value until its next token.
// * Bounded memory: at most `maximumSources` and `maximumTargets` entries, least recently used
//   evicted (the victim search scans at most the cap). An evicted target's held value is handed back
//   so the caller applies it. Not thread-safe; `OSCDispatcher` owns one under its lock.
// No peer addresses or payloads are stored: sources are opaque numbers from the transport.
import ParameterGraph

/// A steady rate and a burst allowance.
public struct OSCRateLimit: Sendable, Hashable {
    /// Tokens per second, 1…1,000,000.
    public let perSecond: Int
    /// Tokens a full bucket holds, 1…1,000.
    public let burst: Int

    public init(perSecond: Int, burst: Int) {
        self.perSecond = min(max(perSecond, 1), 1_000_000)
        self.burst = min(max(burst, 1), 1_000)
    }
}

/// The limits the receiver applies (OSC-009-R5). Not shown in Settings.
public struct OSCRateLimitConfiguration: Sendable, Hashable {
    public var perSource: OSCRateLimit
    public var global: OSCRateLimit
    public var perTarget: OSCRateLimit
    public var maximumSources: Int
    public var maximumTargets: Int

    public init(perSource: OSCRateLimit = OSCRateLimit(perSecond: 200, burst: 50),
                global: OSCRateLimit = OSCRateLimit(perSecond: 500, burst: 100),
                perTarget: OSCRateLimit = OSCRateLimit(perSecond: 60, burst: 10),
                maximumSources: Int = 16,
                maximumTargets: Int = 64) {
        self.perSource = perSource
        self.global = global
        self.perTarget = perTarget
        self.maximumSources = max(maximumSources, 1)
        self.maximumTargets = max(maximumTargets, 1)
    }

    /// 200 datagrams/s (burst 50) per source, 500/s (burst 100) in all, 60 updates/s (burst 10) per
    /// target, 16 sources, 64 targets (research OSC-009-D6).
    public static let `default` = OSCRateLimitConfiguration()
}

/// One sender of datagrams: a peer connection numbered by the transport, never an address.
public struct OSCSourceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Datagrams whose transport does not say who sent them.
    public static let unattributed = OSCSourceID(rawValue: 0)
    public var description: String { "source \(rawValue)" }
}

public struct OSCTokenBucket: Sendable, Hashable {
    public static let unitsPerToken: UInt64 = 1_000_000_000

    public let limit: OSCRateLimit
    public private(set) var units: UInt64
    public private(set) var lastRefill: UInt64

    /// A full bucket at `now`.
    public init(limit: OSCRateLimit, now: UInt64) {
        self.limit = limit
        units = UInt64(limit.burst) * Self.unitsPerToken
        lastRefill = now
    }

    public var capacity: UInt64 { UInt64(limit.burst) * Self.unitsPerToken }
    public var hasToken: Bool { units >= Self.unitsPerToken }
    /// Whole tokens available.
    public var tokens: Int { Int(units / Self.unitsPerToken) }

    public mutating func refill(now: UInt64) {
        guard now > lastRefill else { return }          // same instant, or a clock that went backwards
        let elapsed = now - lastRefill
        lastRefill = now
        let rate = UInt64(limit.perSecond)
        let missing = capacity - units
        if elapsed >= missing / rate + 1 {
            units = capacity
        } else {
            units = min(capacity, units + elapsed * rate)   // elapsed × rate ≤ missing + rate: no overflow
        }
    }

    /// Takes one token; call only when `hasToken`.
    public mutating func take() {
        units -= Self.unitsPerToken
    }

    /// Nanoseconds from `lastRefill` until one token is available (0 when one is).
    public var nanosecondsUntilToken: UInt64 {
        guard !hasToken else { return 0 }
        let rate = UInt64(limit.perSecond)
        let deficit = Self.unitsPerToken - units
        return (deficit + rate - 1) / rate
    }
}

public enum OSCTargetDecision: Sendable, Hashable {
    /// A token was taken: apply the value now (any older held value is dropped).
    case applyNow
    /// Over the target's rate: the value is held as the target's newest.
    case held
}

public struct OSCRateLimiter: Sendable {
    private struct SourceEntry: Sendable {
        var bucket: OSCTokenBucket
        var lastUse: UInt64
    }

    private struct TargetEntry: Sendable {
        var bucket: OSCTokenBucket
        var held: Double?
        var lastUse: UInt64
    }

    public let configuration: OSCRateLimitConfiguration
    private var sources: [OSCSourceID: SourceEntry] = [:]
    private var targets: [ParameterID: TargetEntry] = [:]
    private var global: OSCTokenBucket?
    private var useCounter: UInt64 = 0

    public init(configuration: OSCRateLimitConfiguration = .default) {
        self.configuration = configuration
    }

    public var sourceCount: Int { sources.count }
    public var targetCount: Int { targets.count }
    public var heldCount: Int { targets.values.reduce(0) { $0 + ($1.held == nil ? 0 : 1) } }
    public func heldValue(for target: ParameterID) -> Double? { targets[target]?.held }
    public func tracks(_ source: OSCSourceID) -> Bool { sources[source] != nil }

    /// Whether a datagram from `source` may be decoded now (OSC-009-R1, R2, R6).
    public mutating func admitDatagram(from source: OSCSourceID, now: UInt64) -> Bool {
        useCounter += 1
        var entry: SourceEntry
        if let existing = sources[source] {
            entry = existing
        } else {
            if sources.count >= configuration.maximumSources, let victim = Self.leastRecent(sources, \.lastUse) {
                sources.removeValue(forKey: victim)
            }
            entry = SourceEntry(bucket: OSCTokenBucket(limit: configuration.perSource, now: now), lastUse: 0)
        }
        var all = global ?? OSCTokenBucket(limit: configuration.global, now: now)
        entry.bucket.refill(now: now)
        all.refill(now: now)
        let admitted = entry.bucket.hasToken && all.hasToken
        if admitted {
            entry.bucket.take()
            all.take()
        }
        entry.lastUse = useCounter
        sources[source] = entry
        global = all
        return admitted
    }

    /// One update for `target` (OSC-009-R7, R8). `evicted` is a held value of another target that was
    /// evicted to make room; the caller applies it.
    public mutating func submit(_ value: Double, to target: ParameterID, now: UInt64)
        -> (decision: OSCTargetDecision, evicted: (ParameterID, Double)?) {
        useCounter += 1
        var evicted: (ParameterID, Double)?
        var entry: TargetEntry
        if let existing = targets[target] {
            entry = existing
        } else {
            if targets.count >= configuration.maximumTargets, let victim = Self.leastRecent(targets, \.lastUse) {
                if let held = targets.removeValue(forKey: victim)?.held { evicted = (victim, held) }
            }
            entry = TargetEntry(bucket: OSCTokenBucket(limit: configuration.perTarget, now: now), held: nil, lastUse: 0)
        }
        entry.bucket.refill(now: now)
        entry.lastUse = useCounter
        let decision: OSCTargetDecision
        if entry.bucket.hasToken {
            entry.bucket.take()
            entry.held = nil
            decision = .applyNow
        } else {
            entry.held = value
            decision = .held
        }
        targets[target] = entry
        return (decision, evicted)
    }

    /// Held values whose target has a token at `now`, in target order; each takes its token.
    public mutating func takeDue(now: UInt64) -> [(ParameterID, Double)] {
        var due: [(ParameterID, Double)] = []
        for id in targets.keys.sorted() {
            guard var entry = targets[id], let held = entry.held else { continue }
            entry.bucket.refill(now: now)
            if entry.bucket.hasToken {
                entry.bucket.take()
                entry.held = nil
                due.append((id, held))
            }
            targets[id] = entry
        }
        return due
    }

    /// Nanoseconds from `now` until the earliest held value can be applied; nil when nothing is held.
    public func nextDue(now: UInt64) -> UInt64? {
        var earliest: UInt64?
        for entry in targets.values where entry.held != nil {
            var bucket = entry.bucket
            bucket.refill(now: now)
            let wait = bucket.nanosecondsUntilToken
            earliest = min(earliest ?? wait, wait)
        }
        return earliest
    }

    /// Empty tables and no held values (each listener start, and stop; OSC-009-R5).
    public mutating func reset() {
        sources.removeAll()
        targets.removeAll()
        global = nil
    }

    private static func leastRecent<Key, Entry>(_ table: [Key: Entry], _ use: KeyPath<Entry, UInt64>) -> Key? {
        var victim: (key: Key, use: UInt64)?
        for (key, entry) in table where victim == nil || entry[keyPath: use] < victim!.use {
            victim = (key, entry[keyPath: use])
        }
        return victim?.key
    }
}
