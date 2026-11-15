// ReactionDiffusion.swift — VIS-012 reaction diffusion: constants, presets, seed patterns, the stored settings, the seed
// texture, the bass kick detector with the fixed-step scheduler, the light bound and the health record
// (contracts/reaction-diffusion.md C1 to C3; research VIS-012-D2 to D8). Pure Swift (every platform).
//
// Gray–Scott on an N × N torus (wrap-around edges), explicit Euler with dt = 1 and the 9-point Laplacian
// (centre −1, edges 0.2, corners 0.05). One iteration, per cell:
//   e = (left + right) + (top + bottom); d = (top-left + top-right) + (bottom-left + bottom-right); lap = 0.2e + 0.05d − s
//   U' = U + (Du·lapU − UV² + F(1 − U));  V' = V + (Dv·lapV + UV² − (F + k)V)
//   on a step's first iteration with an injection: a = amount·exp(−|x − c|² / r²); V' += a; U' −= a
//   then each value: non-finite → 0, clamped to [0, 1].
// `ReactionDiffusionShader` runs the same formula on the GPU; `GrayScottSolver` (VisualFluidReference) is the CPU
// reference. The initial state is computed here on the CPU (`ReactionDiffusionSeed.fill`) and copied to the GPU, so
// both start bit-identical.
import Foundation

/// VIS-012's constants (data-model.md).
public enum ReactionDiffusion {
    /// Cells per side (every device; research VIS-012-D2).
    public static let gridSize = 128
    public static let stepsPerSecond: UInt64 = 60
    /// The spiral-of-death guard: fixed steps one frame may run; a longer gap skips the rest.
    public static let maximumStepsPerFrame = 4
    /// Speed: iterations per 1/60 s step.
    public static let speedRange: ClosedRange<Int> = 1...16
    public static let defaultSpeed = 8
    /// The hard bound of iterations one frame runs (VIS-012-R7).
    public static let maximumIterationsPerFrame = maximumStepsPerFrame * 16
    public static let seedRange: ClosedRange<Int> = 0...9999
    public static let defaultSeed = 1
    /// The fade-in after every reload (VIS-012-R11).
    public static let fadeInNanoseconds: UInt64 = 1_000_000_000
    public static let injectionRadius: Float = 0.04
    /// V added (and U removed) at an injection's centre at a full bass level.
    public static let injectionAmount: Float = 0.25
    public static let queueCapacity = 4
    /// The bass kick: the low group rises above `kickOn` after being below `kickOff`.
    public static let kickOn = 0.6
    public static let kickOff = 0.4
    public static let kickSpacingNanoseconds: UInt64 = 250_000_000
    public static let reduceMotionKickSpacingNanoseconds: UInt64 = 1_000_000_000
    /// ACC-012: no drawn channel above 0.8.
    public static let displayCap: Float = 0.8
    /// The display maps t = smoothstep(low, high, V).
    public static let displayLow: Float = 0.1
    public static let displayHigh: Float = 0.4
    public static let paletteStops = 8
    /// The seeded region's value.
    public static let seedU: Float = 0.5
    public static let seedV: Float = 0.25

    /// The start of step `k` after the anchor, nanoseconds (exact integer arithmetic).
    public static func stepOffset(_ k: UInt64) -> UInt64 { k &* 1_000_000_000 / stepsPerSecond }

    /// Iterations per step at `speed` (clamped); Reduce Motion runs half, rounded up (ACC-001).
    public static func iterationsPerStep(speed: Int, reduceMotion: Bool) -> Int {
        let s: Int = min(max(speed, speedRange.lowerBound), speedRange.upperBound)
        return reduceMotion ? (s + 1) / 2 : s
    }

    /// The fade-in factor `elapsed` nanoseconds after a reload (0…1, linear over 1 s).
    public static func ramp(elapsedNanoseconds elapsed: UInt64) -> Float {
        elapsed >= fadeInNanoseconds ? 1 : Float(Double(elapsed) / Double(fadeInNanoseconds))
    }
}

/// Feed, kill and diffusion rates, clamped to the explicit scheme's stable ranges (research VIS-012-D3).
public struct GrayScottParameters: Sendable, Equatable {
    public static let feedRange: ClosedRange<Float> = 0.01...0.10
    public static let killRange: ClosedRange<Float> = 0.04...0.07
    public static let duRange: ClosedRange<Float> = 0.2...1.0
    public static let dvRange: ClosedRange<Float> = 0.1...0.5

    public let feed: Float
    public let kill: Float
    public let du: Float
    public let dv: Float

    public init(feed: Float, kill: Float, du: Float = 1.0, dv: Float = 0.5) {
        self.feed = Self.clamp(feed, Self.feedRange)
        self.kill = Self.clamp(kill, Self.killRange)
        self.du = Self.clamp(du, Self.duRange)
        self.dv = Self.clamp(dv, Self.dvRange)
    }

    /// Non-finite → the lower bound.
    static func clamp(_ v: Float, _ r: ClosedRange<Float>) -> Float {
        guard v.isFinite else { return r.lowerBound }
        return min(max(v, r.lowerBound), r.upperBound)
    }
}

/// The named presets (VIS-012-R2).
public enum ReactionDiffusionPreset: String, CaseIterable, Sendable {
    case coral, mitosis, spots, maze

    public static let defaultPreset: ReactionDiffusionPreset = .coral

    public var title: String {
        switch self {
        case .coral: "Coral"
        case .mitosis: "Mitosis"
        case .spots: "Spots"
        case .maze: "Maze"
        }
    }

    public var parameters: GrayScottParameters {
        switch self {
        case .coral: GrayScottParameters(feed: 0.0545, kill: 0.062)
        case .mitosis: GrayScottParameters(feed: 0.0367, kill: 0.0649)
        case .spots: GrayScottParameters(feed: 0.030, kill: 0.062)
        case .maze: GrayScottParameters(feed: 0.029, kill: 0.057)
        }
    }
}

/// The seed patterns (VIS-012-R5).
public enum ReactionDiffusionPattern: String, CaseIterable, Sendable {
    case square, spots, ring, stripes

    public static let defaultPattern: ReactionDiffusionPattern = .square

    public var title: String {
        switch self {
        case .square: "Centre Square"
        case .spots: "Random Spots"
        case .ring: "Ring"
        case .stripes: "Stripes"
        }
    }
}

/// The stored settings (data-model.md): preset, pattern, seed 0…9999, speed 1…16; out of range → default.
public struct ReactionDiffusionSettings: Sendable, Equatable {
    public var preset: ReactionDiffusionPreset
    public var pattern: ReactionDiffusionPattern
    public var seed: Int
    public var speed: Int

    public init(preset: ReactionDiffusionPreset = .defaultPreset, pattern: ReactionDiffusionPattern = .defaultPattern,
                seed: Int = ReactionDiffusion.defaultSeed, speed: Int = ReactionDiffusion.defaultSpeed) {
        self.preset = preset
        self.pattern = pattern
        self.seed = seed
        self.speed = speed
        self = clamped()
    }

    /// Decodes the stored raw values (UserDefaults); unknown or missing values take their defaults.
    public init(storedPreset: String?, pattern storedPattern: String?, seed storedSeed: Int?, speed storedSpeed: Int?) {
        self.init(preset: storedPreset.flatMap(ReactionDiffusionPreset.init(rawValue:)) ?? .defaultPreset,
                  pattern: storedPattern.flatMap(ReactionDiffusionPattern.init(rawValue:)) ?? .defaultPattern,
                  seed: storedSeed ?? ReactionDiffusion.defaultSeed, speed: storedSpeed ?? ReactionDiffusion.defaultSpeed)
    }

    public static let `default` = ReactionDiffusionSettings()

    public func clamped() -> ReactionDiffusionSettings {
        var c = self
        if !ReactionDiffusion.seedRange.contains(seed) { c.seed = ReactionDiffusion.defaultSeed }
        if !ReactionDiffusion.speedRange.contains(speed) { c.speed = ReactionDiffusion.defaultSpeed }
        return c
    }

    /// A change of these re-seeds the grid (VIS-012-R6); Speed does not.
    public func reloads(from other: ReactionDiffusionSettings) -> Bool {
        preset != other.preset || pattern != other.pattern || seed != other.seed
    }
}

/// The initial state of a pattern and seed (research VIS-012-D4).
public enum ReactionDiffusionSeed {
    /// The random source of `seed` (never a fixed stream: a seed mixes into the state).
    static func generator(seed: Int, salt: UInt64) -> SplitMix64 {
        SplitMix64(seed: UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 ^ salt)
    }

    /// Writes (U, V) for every cell, rows top first, into `cells` (n² entries). U = 1, V = 0 outside the pattern;
    /// 0.5, 0.25 inside. Allocates nothing.
    public static func fill(pattern: ReactionDiffusionPattern, seed: Int, gridSize n: Int,
                            into cells: UnsafeMutablePointer<SIMD2<Float>>) {
        let base = SIMD2<Float>(1, 0)
        let lit = SIMD2<Float>(ReactionDiffusion.seedU, ReactionDiffusion.seedV)
        let count: Int = n * n
        for k in 0..<count { cells[k] = base }
        var rng: SplitMix64 = generator(seed: seed, salt: 0x5244_0012)
        let inv: Float = 1 / Float(n)
        switch pattern {
        case .square:
            let cx: Float = 0.5 + Float(rng.unit() * 2 - 1) * 0.08
            let cy: Float = 0.5 + Float(rng.unit() * 2 - 1) * 0.08
            for j in 0..<n {
                let y: Float = (Float(j) + 0.5) * inv
                for i in 0..<n {
                    let x: Float = (Float(i) + 0.5) * inv
                    if abs(x - cx) <= 0.08, abs(y - cy) <= 0.08 { cells[j * n + i] = lit }
                }
            }
        case .spots:
            for _ in 0..<10 {
                let cx: Float = 0.1 + 0.8 * Float(rng.unit())
                let cy: Float = 0.1 + 0.8 * Float(rng.unit())
                let r: Float = 0.02 + 0.03 * Float(rng.unit())
                disc(cells, n: n, cx: cx, cy: cy, inner: 0, outer: r, value: lit)
            }
        case .ring:
            let cx: Float = 0.5 + Float(rng.unit() * 2 - 1) * 0.08
            let cy: Float = 0.5 + Float(rng.unit() * 2 - 1) * 0.08
            disc(cells, n: n, cx: cx, cy: cy, inner: 0.235, outer: 0.265, value: lit)
        case .stripes:
            let period: Int = max(n / 5, 3)
            let phase: Int = Int(rng.next() % UInt64(period))
            for j in 0..<n where (j + phase) % period < 2 {
                for i in 0..<n { cells[j * n + i] = lit }
            }
        }
    }

    /// Cells whose centre lies at distance inner…outer from (cx, cy) take `value`.
    private static func disc(_ cells: UnsafeMutablePointer<SIMD2<Float>>, n: Int, cx: Float, cy: Float, inner: Float,
                             outer: Float, value: SIMD2<Float>) {
        let inv: Float = 1 / Float(n)
        let inner2: Float = inner * inner
        let outer2: Float = outer * outer
        for j in 0..<n {
            let dy: Float = (Float(j) + 0.5) * inv - cy
            for i in 0..<n {
                let dx: Float = (Float(i) + 0.5) * inv - cx
                let d2: Float = dx * dx + dy * dy
                if d2 >= inner2, d2 <= outer2 { cells[j * n + i] = value }
            }
        }
    }
}

/// One injection: centre (domain units, y down) and amount at the centre.
public struct ReactionInjection: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var amount: Float

    public init(x: Float, y: Float, amount: Float) {
        self.x = x
        self.y = y
        self.amount = amount
    }

    /// The seeded injection `index` at bass `strength` (positions 0.1…0.9).
    public static func seeded(seed: Int, index: UInt64, strength: Float) -> ReactionInjection {
        var rng: SplitMix64 = ReactionDiffusionSeed.generator(seed: seed, salt: index &* 0xBF58_476D_1CE4_E5B9 ^ 0x1A1A)
        let x: Float = 0.1 + 0.8 * Float(rng.unit())
        let y: Float = 0.1 + 0.8 * Float(rng.unit())
        let s: Float = strength.isFinite ? min(max(strength, 0), 1) : 0
        return ReactionInjection(x: x, y: y, amount: ReactionDiffusion.injectionAmount * s)
    }
}

/// The fixed-step clock, the bass kick detector and the injection queue (VIS-012-R7, R8). Steps start at the anchor
/// (the first frame after a reset); `advance` plans every step that ends by the frame's time, at most 4, each with
/// `iterationsPerStep` iterations (≤ 64 per frame); a longer gap skips the rest and re-anchors (counted). An injection
/// applies at the first step whose start is at or after its time, at most one per step. Storage is made in `init`.
/// Not Sendable: one thread.
public final class ReactionDiffusionScheduler {
    public private(set) var anchorNanoseconds: UInt64?
    public private(set) var stepIndex: UInt64 = 0
    public private(set) var plannedSteps = 0
    public private(set) var plannedIterations = 0
    public private(set) var skippedGaps = 0
    public private(set) var totalSteps: UInt64 = 0
    public private(set) var totalIterations: UInt64 = 0
    public private(set) var kicks = 0
    public private(set) var appliedInjections = 0
    public private(set) var droppedInjections = 0
    public var reduceMotion = false
    public var speed = ReactionDiffusion.defaultSpeed
    /// The stored seed (injection positions).
    public var seed = ReactionDiffusion.defaultSeed

    private var times: [UInt64]
    private var strengths: [Float]
    private var head = 0
    private var count = 0
    private var injectionIndex: UInt64 = 0
    private var armed = true
    private var lastKick: UInt64?
    private var stepIterations: [Int]
    private var stepInjections: [ReactionInjection?]

    public init() {
        times = [UInt64](repeating: 0, count: ReactionDiffusion.queueCapacity)
        strengths = [Float](repeating: 0, count: ReactionDiffusion.queueCapacity)
        stepIterations = [Int](repeating: 0, count: ReactionDiffusion.maximumStepsPerFrame)
        stepInjections = [ReactionInjection?](repeating: nil, count: ReactionDiffusion.maximumStepsPerFrame)
    }

    public var pendingInjections: Int { count }

    /// Starts over (a reload): no anchor, empty queue, kick detector armed, injection index 0; counters kept.
    public func reset() {
        anchorNanoseconds = nil
        stepIndex = 0
        plannedSteps = 0
        plannedIterations = 0
        totalSteps = 0
        totalIterations = 0
        head = 0
        count = 0
        injectionIndex = 0
        armed = true
        lastKick = nil
    }

    /// Feeds the frame's bass level (VIS-007's low group, 0…1). True when it fired a kick that was queued.
    @discardableResult
    public func observeBass(_ level: Double, atNanoseconds nanoseconds: UInt64) -> Bool {
        let b: Double = level.isFinite ? min(max(level, 0), 1) : 0
        if b < ReactionDiffusion.kickOff { armed = true; return false }
        guard armed, b > ReactionDiffusion.kickOn else { return false }
        armed = false
        let spacing: UInt64 = reduceMotion ? ReactionDiffusion.reduceMotionKickSpacingNanoseconds
            : ReactionDiffusion.kickSpacingNanoseconds
        if let last = lastKick, nanoseconds >= last, nanoseconds - last < spacing {
            droppedInjections += 1
            return false
        }
        lastKick = nanoseconds
        kicks += 1
        return enqueue(atNanoseconds: nanoseconds, strength: Float(b))
    }

    /// Queues an injection; false when the queue is full (counted) or the strength is not finite.
    @discardableResult
    public func enqueue(atNanoseconds nanoseconds: UInt64, strength: Float) -> Bool {
        guard strength.isFinite else { return false }
        guard count < ReactionDiffusion.queueCapacity else {
            droppedInjections += 1
            return false
        }
        let slot: Int = (head + count) % ReactionDiffusion.queueCapacity
        times[slot] = nanoseconds
        strengths[slot] = min(max(strength, 0), 1)
        count += 1
        return true
    }

    /// Plans every step that ends at or before `nanoseconds` (at most 4 and 64 iterations). Returns the step count.
    @discardableResult
    public func advance(toNanoseconds nanoseconds: UInt64) -> Int {
        plannedSteps = 0
        plannedIterations = 0
        guard let anchor = anchorNanoseconds else {
            anchorNanoseconds = nanoseconds
            stepIndex = 0
            return 0
        }
        guard nanoseconds >= anchor else { return 0 }
        let iterations: Int = ReactionDiffusion.iterationsPerStep(speed: speed, reduceMotion: reduceMotion)
        while plannedSteps < ReactionDiffusion.maximumStepsPerFrame,
              plannedIterations + iterations <= ReactionDiffusion.maximumIterationsPerFrame {
            let end: UInt64 = anchor &+ ReactionDiffusion.stepOffset(stepIndex &+ 1)
            guard end <= nanoseconds else { return plannedSteps }
            planStep(plannedSteps, start: anchor &+ ReactionDiffusion.stepOffset(stepIndex), iterations: iterations)
            stepIndex &+= 1
            totalSteps &+= 1
            totalIterations &+= UInt64(iterations)
            plannedIterations += iterations
            plannedSteps += 1
        }
        if anchor &+ ReactionDiffusion.stepOffset(stepIndex &+ 1) <= nanoseconds {
            anchorNanoseconds = nanoseconds   // a stall: skip the rest of the gap
            stepIndex = 0
            skippedGaps += 1
        }
        return plannedSteps
    }

    /// Iterations of planned step `step`.
    public func iterations(step: Int) -> Int { stepIterations[step] }
    /// The injection of planned step `step` (applied on its first iteration), if any.
    public func injection(step: Int) -> ReactionInjection? { stepInjections[step] }

    private func planStep(_ s: Int, start: UInt64, iterations: Int) {
        stepIterations[s] = iterations
        stepInjections[s] = nil
        guard count > 0, times[head] <= start else { return }
        let strength: Float = strengths[head]
        head = (head + 1) % ReactionDiffusion.queueCapacity
        count -= 1
        stepInjections[s] = ReactionInjection.seeded(seed: seed, index: injectionIndex, strength: strength)
        injectionIndex &+= 1
        appliedInjections += 1
    }
}

/// VIS-012-R11: a rigorous upper bound of every drawn channel: min(0.8, brightest palette stop) × the fade-in ramp.
/// The display draws min(0.8, palette(t) · t) × ramp × gain with t ≤ 1, which never exceeds bound × gain.
public enum ReactionDiffusionBound {
    public static func level(stops: UnsafePointer<SIMD3<Float>>, count: Int, ramp: Float) -> SIMD3<Float> {
        var top = SIMD3<Float>(0, 0, 0)
        for k in 0..<count {
            let c: SIMD3<Float> = stops[k]
            top = SIMD3<Float>(max(top.x, c.x), max(top.y, c.y), max(top.z, c.z))
        }
        let cap: Float = ReactionDiffusion.displayCap
        let r: Float = ramp.isFinite ? min(max(ramp, 0), 1) : 0
        return SIMD3<Float>(min(top.x, cap), min(top.y, cap), min(top.z, cap)) * r
    }
}

/// The grid's health (VIS-012-R9): largest U and V, smallest value, and whether a value was non-finite or outside
/// [0, 1].
public struct ReactionDiffusionHealth: Sendable, Equatable {
    public var maxU: Float
    public var maxV: Float
    public var minValue: Float
    public var flagged: Bool

    public init(maxU: Float = 0, maxV: Float = 0, minValue: Float = 1, flagged: Bool = false) {
        self.maxU = maxU
        self.maxV = maxV
        self.minValue = minValue
        self.flagged = flagged
    }

    /// Every value finite and within [0, 1].
    public var isHealthy: Bool {
        !flagged && maxU.isFinite && maxV.isFinite && minValue.isFinite && maxU <= 1 && maxV <= 1 && minValue >= 0
    }
}
