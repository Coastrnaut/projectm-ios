// StarfieldSimulation.swift — the starfield's stars and fixed-step flight (VIS-016-R2 to R4, R6; contract S1-S4;
// research VIS-016-D2).
//
// A pool of 2000 stars allocated in `init` (Constitution VII). The whole pool is stepped whatever the density, so the
// positions never depend on it; the density only chooses how many of the first stars are drawn. One SplitMix64 stream
// (VIS-008's) seeded with the configuration's seed: `reset()` draws x, y, z for every star in index order; each step
// visits the stars in index order and a star below the near plane moves back by the depth range and draws a new x then
// y. Time is the injected frame clock in monotonic nanoseconds: step k starts at anchor + ⌊k·10⁹/240⌋, so any frame
// timing that reaches the same time has run the same steps (bit-identical positions). The bass target (the low band
// group, set per frame) is smoothed per step. No clock is read; no allocation. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One star: lateral x, y (−2…2) and depth z (near…far).
public struct Star: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public final class StarfieldSimulation {
    public static let capacity = StarfieldConfiguration.capacity
    /// Δt, seconds.
    public static let stepSeconds = 1.0 / Double(StarfieldConfiguration.stepsPerSecond)
    /// The bass one-pole's factor per step.
    static let bassStepFactor: Double = 1 - exp(-stepSeconds / StarfieldConfiguration.bassTimeConstant)

    /// Density, speed and Reduce Motion apply from the next step; a new seed resets the stars.
    public var configuration: StarfieldConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.seed != oldValue.seed { reset() }
        }
    }

    private let stars: UnsafeMutablePointer<Star>
    private var rng: SplitMix64
    /// Step 0's start; nil until the first advance after a reset.
    public private(set) var anchorNanoseconds: UInt64?
    /// Steps run since the anchor.
    public private(set) var stepIndex: UInt64 = 0
    /// Steps run since the last reset.
    public private(set) var stepsRun = 0
    /// The smoothed low group (0…1) and its target.
    public private(set) var bass = 0.0
    public private(set) var bassTarget = 0.0
    /// Stars that passed the near plane since the last reset.
    public private(set) var respawnCount = 0
    /// Long gaps skipped (more than 240 steps in one advance).
    public private(set) var skippedGaps = 0

    public init(configuration: StarfieldConfiguration = StarfieldConfiguration()) {
        self.configuration = configuration.clamped()
        rng = SplitMix64(seed: configuration.seed)
        stars = .allocate(capacity: Self.capacity)
        stars.initialize(repeating: Star(x: 0, y: 0, z: StarfieldConfiguration.far), count: Self.capacity)
        reset()
    }

    deinit {
        stars.deinitialize(count: Self.capacity)
        stars.deallocate()
    }

    // Storage introspection for the allocation tests.
    var storageAddress: UInt { UInt(bitPattern: stars) }

    /// Stars drawn (the density limit applied).
    public var activeCount: Int { configuration.activeCount }

    /// Star `i` of the pool (0..<capacity).
    public func star(_ i: Int) -> Star { stars[i] }

    /// Every star of the pool (tests; allocates).
    public var allStars: [Star] { (0..<Self.capacity).map { (i: Int) -> Star in stars[i] } }

    /// The initial seeded positions: every star draws x, y, z in index order; the bass and the anchor start over.
    public func reset() {
        rng = SplitMix64(seed: configuration.seed)
        let spread: Double = StarfieldConfiguration.lateralSpread
        let near: Double = StarfieldConfiguration.near
        let range: Double = StarfieldConfiguration.far - near
        for i in 0..<Self.capacity {
            let x: Double = (2 * rng.unit() - 1) * spread
            let y: Double = (2 * rng.unit() - 1) * spread
            let z: Double = near + range * (1 - rng.unit())   // (near, far]
            stars[i] = Star(x: x, y: y, z: z)
        }
        anchorNanoseconds = nil
        stepIndex = 0
        stepsRun = 0
        bass = 0
        bassTarget = 0
        respawnCount = 0
        skippedGaps = 0
    }

    /// The low band group (0…1; not finite → 0) the next steps ease towards.
    public func setBass(_ low: Double) {
        bassTarget = low.isFinite ? min(max(low, 0), 1) : 0
    }

    /// The start of step `k` after the anchor, nanoseconds (exact integer arithmetic).
    static func stepOffset(_ k: UInt64) -> UInt64 {
        k &* 1_000_000_000 / UInt64(StarfieldConfiguration.stepsPerSecond)
    }

    /// Runs every step that ends at or before `nanoseconds` (at most 240; the rest of a longer gap is skipped and the
    /// anchor moves to `nanoseconds`). The first call after a reset only sets the anchor. Earlier times do nothing.
    public func advance(toNanoseconds nanoseconds: UInt64) {
        guard let anchor = anchorNanoseconds else {
            anchorNanoseconds = nanoseconds
            stepIndex = 0
            return
        }
        guard nanoseconds >= anchor else { return }
        var steps = 0
        while steps < StarfieldConfiguration.maximumStepsPerAdvance {
            let end: UInt64 = anchor &+ Self.stepOffset(stepIndex &+ 1)
            guard end <= nanoseconds else { return }
            step()
            stepIndex &+= 1
            steps += 1
        }
        if anchor &+ Self.stepOffset(stepIndex &+ 1) <= nanoseconds {
            anchorNanoseconds = nanoseconds   // a stall: skip the rest of the gap
            stepIndex = 0
            skippedGaps += 1
        }
    }

    /// One Δt for the whole pool, in index order.
    private func step() {
        bass += (bassTarget - bass) * Self.bassStepFactor
        let dz: Double = configuration.effectiveSpeed(bass: bass) * Self.stepSeconds
        let near: Double = StarfieldConfiguration.near
        let range: Double = StarfieldConfiguration.far - near
        let spread: Double = StarfieldConfiguration.lateralSpread
        for i in 0..<Self.capacity {
            var s = stars[i]
            s.z -= dz
            if s.z < near {
                s.z += range
                s.x = (2 * rng.unit() - 1) * spread
                s.y = (2 * rng.unit() - 1) * spread
                respawnCount += 1
            }
            stars[i] = s
        }
        stepsRun += 1
    }
}
