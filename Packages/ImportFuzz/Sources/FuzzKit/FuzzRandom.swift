// FuzzRandom.swift — the harness's only source of randomness (QA-005-R1; contract H1; research
// QA-005-D2). SplitMix64: small, well known, and the same on every host and Swift version, because
// only `next()` is used, never the standard library's random functions.

public struct FuzzRandom: Sendable {
    public var state: UInt64

    public init(state: UInt64) { self.state = state }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return Self.mix(state)
    }

    /// The SplitMix64 finalizer: a good 64-bit hash of `value`.
    public static func mix(_ value: UInt64) -> UInt64 {
        var z: UInt64 = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound`; `bound` below 1 is treated as 1.
    public mutating func below(_ bound: Int) -> Int {
        let b: UInt64 = UInt64(Swift.max(bound, 1))
        return Int(next() % b)
    }

    /// A value in `range`.
    public mutating func pick(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + below(range.count)
    }

    /// True about once in `n` calls.
    public mutating func chance(oneIn n: Int) -> Bool { below(n) == 0 }

    public mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }

    public mutating func bytes(count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(Swift.max(count, 0))
        for _ in 0..<Swift.max(count, 0) { out.append(byte()) }
        return out
    }

    /// One element of a non-empty array.
    public mutating func element<T>(of items: [T]) -> T { items[below(items.count)] }
}
