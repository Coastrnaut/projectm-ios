// WarmStartLoader.swift — PERF-009 (contracts/warm-cache.md W3; PERF-009-R5, R7, R11): use a valid cache entry
// or run the expensive step and store its result. The expensive step runs only when the entry is not a hit or
// does not decode; a store failure never fails the load. `built` says whether the expensive step ran, so tests
// prove the warm path by counting, not timing. `LaunchTimeline` measures launch phases on an injected clock.
import Foundation

public struct WarmStartResult<Value> {
    public let value: Value
    public let outcome: WarmCacheOutcome
    /// The expensive step ran (cold).
    public let built: Bool
    /// A new entry was written.
    public let stored: Bool
}

extension WarmStartResult: Sendable where Value: Sendable {}

public enum WarmStartLoader {
    /// `store` nil means no cache: always builds (`unavailable`).
    public static func load<Value>(_ name: String, key: WarmCacheKey, store: WarmCacheStore?,
                                   decode: (Data) throws -> Value, build: () throws -> Value,
                                   encode: (Value) throws -> Data) rethrows -> WarmStartResult<Value> {
        guard let store else {
            return WarmStartResult(value: try build(), outcome: .unavailable, built: true, stored: false)
        }
        var (outcome, payload) = store.read(name, key: key)
        if let payload {
            do {
                return WarmStartResult(value: try decode(payload), outcome: .hit, built: false, stored: false)
            } catch {
                store.remove(name)
                outcome = .damaged(.decode)
            }
        }
        let value = try build()
        var stored = false
        if let data = try? encode(value) {
            stored = (try? store.write(name, key: key, payload: data)) != nil
        }
        return WarmStartResult(value: value, outcome: outcome, built: true, stored: stored)
    }
}

/// Monotonic nanoseconds (injected in tests).
public protocol WarmStartClock: Sendable {
    func nowNanoseconds() -> UInt64
}

/// `DispatchTime`'s uptime clock.
public struct UptimeWarmStartClock: WarmStartClock {
    public init() {}
    public func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

/// Named phases measured from begin to end, in milliseconds. Not thread-safe: one owner.
public struct LaunchTimeline {
    private let clock: any WarmStartClock
    private var started: [String: UInt64] = [:]
    public private(set) var milliseconds: [String: Double] = [:]

    public init(clock: any WarmStartClock = UptimeWarmStartClock()) {
        self.clock = clock
    }

    public mutating func begin(_ phase: String) {
        started[phase] = clock.nowNanoseconds()
    }

    /// The phase's duration, or nil when it was never begun.
    @discardableResult
    public mutating func end(_ phase: String) -> Double? {
        guard let start = started.removeValue(forKey: phase) else { return nil }
        let now = clock.nowNanoseconds()
        let value = Double(now >= start ? now - start : 0) / 1_000_000
        milliseconds[phase] = value
        return value
    }
}
