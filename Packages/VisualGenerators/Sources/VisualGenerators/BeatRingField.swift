// BeatRingField.swift — the beat rings' state (VIS-006-R3 to R6; contracts/beat-rings.md C1).
//
// Up to 16 rings, each a birth time (monotonic nanoseconds on the frame clock) and a sequence number (the
// count of rings accepted before it). An emission is accepted unless it comes earlier than the newest birth
// or less than the rate cap's interval after it; when 16 rings are live the oldest slot is replaced. What is
// drawn at time t is a pure function of the accepted births, the life and t (VIS-006-R6): no clock is read.
// Storage is preallocated (Constitution VII). Not Sendable: one owner.

/// One live ring at a sample time.
public struct BeatRing: Sendable, Equatable {
    /// 0 for the first ring accepted since the last reset, then +1.
    public var sequence: Int
    public var birthNanoseconds: UInt64
    /// Seconds since birth.
    public var age: Double
    /// Fraction of half the shorter side.
    public var radius: Double
    /// 0…peak.
    public var alpha: Double
}

public final class BeatRingField {
    public static let capacity = BeatRingConfiguration.maximumRings

    private let births: UnsafeMutablePointer<UInt64>
    private let sequences: UnsafeMutablePointer<Int>
    /// Slots in use (≤ capacity); slot (oldest + i) % capacity is the i-th oldest.
    private var used = 0
    private var oldest = 0
    /// Rings accepted since the last reset (the next ring's sequence).
    public private(set) var accepted = 0
    /// The newest accepted birth, nil after a reset.
    public private(set) var newestBirth: UInt64?

    public init() {
        births = .allocate(capacity: Self.capacity)
        births.initialize(repeating: 0, count: Self.capacity)
        sequences = .allocate(capacity: Self.capacity)
        sequences.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        births.deinitialize(count: Self.capacity); births.deallocate()
        sequences.deinitialize(count: Self.capacity); sequences.deallocate()
    }

    /// Forgets every ring (the host's loop restart).
    public func reset() {
        used = 0
        oldest = 0
        accepted = 0
        newestBirth = nil
    }

    /// Rings stored (live or not yet pruned).
    public var storedCount: Int { used }

    /// A ring born at `nanoseconds`, unless it is earlier than the newest birth or less than
    /// `minimumInterval` seconds after it. Returns whether it was accepted.
    @discardableResult
    public func emit(atNanoseconds nanoseconds: UInt64, minimumInterval: Double) -> Bool {
        if let newest = newestBirth {
            guard nanoseconds >= newest else { return false }
            let gap: Double = Double(nanoseconds - newest) / 1e9
            guard gap >= max(minimumInterval, 0) - 1e-12 else { return false }
        }
        let slot: Int
        if used == Self.capacity {
            slot = oldest   // full: the oldest ring is replaced
            oldest = (oldest + 1) % Self.capacity
        } else {
            slot = (oldest + used) % Self.capacity
            used += 1
        }
        births[slot] = nanoseconds
        sequences[slot] = accepted
        accepted += 1
        newestBirth = nanoseconds
        return true
    }

    /// Drops rings whose age at `nanoseconds` is `life` seconds or more.
    public func prune(atNanoseconds nanoseconds: UInt64, life: Double) {
        while used > 0 {
            let birth = births[oldest]
            guard nanoseconds >= birth, Double(nanoseconds - birth) / 1e9 >= life else { return }
            oldest = (oldest + 1) % Self.capacity
            used -= 1
        }
    }

    /// Prunes, then calls `body` with each live ring oldest first; returns the live count. Rings born after
    /// `nanoseconds` are not drawn yet. No allocation.
    @discardableResult
    public func forEachRing(atNanoseconds nanoseconds: UInt64, life: Double, _ body: (BeatRing) -> Void) -> Int {
        prune(atNanoseconds: nanoseconds, life: life)
        var count = 0
        for i in 0..<used {
            let slot = (oldest + i) % Self.capacity
            let birth = births[slot]
            guard nanoseconds >= birth else { continue }
            let age: Double = Double(nanoseconds - birth) / 1e9
            guard age < life else { continue }
            body(BeatRing(sequence: sequences[slot], birthNanoseconds: birth, age: age,
                          radius: BeatRingConfiguration.radius(age: age, life: life),
                          alpha: BeatRingConfiguration.alpha(age: age, life: life)))
            count += 1
        }
        return count
    }

    /// The live rings at `nanoseconds`, oldest first (tests and diagnostics; allocates).
    public func rings(atNanoseconds nanoseconds: UInt64, life: Double) -> [BeatRing] {
        var out: [BeatRing] = []
        forEachRing(atNanoseconds: nanoseconds, life: life) { (ring: BeatRing) -> Void in out.append(ring) }
        return out
    }
}
