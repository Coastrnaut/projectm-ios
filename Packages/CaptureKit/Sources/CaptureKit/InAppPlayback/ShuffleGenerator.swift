// ShuffleGenerator.swift — the documented, platform-independent generator behind Shuffle (AUD-005;
// specs/023-aud-005-shuffle-with-history/research.md AUD-005-D1, D5, D6). Foundation only.
//
// The standard library's `shuffled(using:)` and `random(in:using:)` do not promise their algorithm
// across Swift versions, so a stored seed could replay differently after an update. Everything here
// is spelled out instead and pinned by golden tests:
// * SplitMix64 (Steele, Lea and Flood 2014; public-domain constants).
// * `bounded(n)` = `next() % n`. The modulo bias is below 2^-50 for queues of up to 2^14 tracks.
// * Fisher-Yates from the last index down, `j = bounded(i + 1)`.
// * A cycle's seed: the first output of SplitMix64 seeded with `seed ^ (cycle &* golden gamma)`.
// * FNV-1a 64 over UTF-8, for positions that must not depend on Swift's randomized `Hasher`.
import Foundation

/// SplitMix64: a 64-bit state advanced by the golden gamma, then mixed.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= Self.gamma
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// An index in `0..<bound` (`bound` > 0).
    public mutating func bounded(_ bound: Int) -> Int {
        precondition(bound > 0)
        return Int(next() % UInt64(bound))
    }
}

public enum ShuffleGenerator {
    /// Fisher-Yates with SplitMix64(`seed`), from the last index down.
    public static func shuffle<Element>(_ elements: [Element], seed: UInt64) -> [Element] {
        var result = elements
        guard result.count > 1 else { return result }
        var generator = SplitMix64(seed: seed)
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(index, generator.bounded(index + 1))
        }
        return result
    }

    /// The seed of cycle `cycle` (0 for the first) of a shuffle seeded with `seed`.
    public static func cycleSeed(_ seed: UInt64, cycle: Int) -> UInt64 {
        var generator = SplitMix64(seed: seed ^ (UInt64(truncatingIfNeeded: cycle) &* SplitMix64.gamma))
        return generator.next()
    }

    /// FNV-1a, 64 bits, over the UTF-8 bytes of `text`.
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
