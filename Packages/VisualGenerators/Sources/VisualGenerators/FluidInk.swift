// FluidInk.swift — VIS-011 fluid ink: constants, impulses, the fixed-step scheduler, the envelope's ink bound and the
// reference solver (contracts/fluid-ink.md C1 to C3; research VIS-011-D2 to D6). Pure Swift (every platform).
//
// Stable fluids (Stam 1999) on the unit square, y down, cell size h = 1/N, cell centres at (i + 0.5)h. One fixed step of
// 1/60 s runs, in order:
//   1. splats: each impulse adds w · velocity and w · ink with w = exp(−|x − c|² / r²); speed clamped, ink clamped;
//   2. velocity advection: v ← v(x − dt·v(x)) · 0.5^(dt / 1 s), speed clamped;
//   3. divergence: ((vxR − vxL) + (vyB − vyT)) / 2h;
//   4. pressure: 20 Jacobi iterations from p = 0, p ← (pL + pR + pT + pB − h²·div) / 4;
//   5. projection: v ← v − (pR − pL, pB − pT) / 2h, speed clamped;
//   6. ink advection: ink ← ink(x − dt·v(x)) · 0.5^(dt / 2.5 s), clamped to 0…0.8.
// Neighbours and samples clamp to the edge; sampling is bilinear on cell centres. Every stored value is finite (a
// non-finite one becomes 0) and within its cap after every pass. `FluidInkShader` runs the same passes with the same
// formulas on the GPU; `FluidInkSolver` is the CPU reference the tests compare it with.
import Foundation

/// VIS-011's constants (data-model.md).
public enum FluidInk {
    /// Cells per side of the GPU grid (every device; research VIS-011-D2).
    public static let gridSize = 128
    public static let stepsPerSecond: UInt64 = 60
    public static let stepSeconds: Float = 1.0 / 60.0
    /// The spiral-of-death guard: steps one frame may run; a longer gap skips the rest.
    public static let maximumStepsPerFrame = 4
    public static let jacobiIterations = 20
    /// Speed cap, unit squares per second (0.96 cell per step on 128 cells: CFL < 1); halved under Reduce Motion.
    public static let speedCap: Float = 0.45
    public static let velocityHalfLife: Float = 1.0
    public static let inkHalfLife: Float = 2.5
    /// ACC-012: ink per channel never above 0.8.
    public static let inkCap: Float = 0.8
    public static let splatRadius: Float = 0.06
    /// Splat speed and ink at strength 1.
    public static let splatSpeed: Float = 0.45
    public static let splatInk: Float = 0.6
    public static let queueCapacity = 16
    public static let maximumImpulsesPerStep = 2
    public static let maximumStrengthPerStep: Float = 1.5
    /// ACC-001: speed factor and the least spacing between accepted impulses under Reduce Motion.
    public static let reduceMotionScale: Float = 0.5
    public static let reduceMotionSpacingNanoseconds: UInt64 = 500_000_000
    public static let seed: UInt64 = 1301
    /// Health: a value over its cap by more than this fraction resets the field.
    public static let healthTolerance: Float = 0.01

    /// Velocity and ink factors per step.
    public static var velocityFactor: Float { Float(pow(0.5, Double(stepSeconds / velocityHalfLife))) }
    public static var inkFactor: Float { Float(pow(0.5, Double(stepSeconds / inkHalfLife))) }

    /// The speed cap in effect.
    public static func effectiveSpeedCap(reduceMotion: Bool) -> Float { reduceMotion ? speedCap * reduceMotionScale : speedCap }

    /// The start of step `k` after the anchor, nanoseconds (exact integer arithmetic).
    public static func stepOffset(_ k: UInt64) -> UInt64 { k &* 1_000_000_000 / stepsPerSecond }
}

/// An onset turned into an impulse (VIS-011-R2).
public enum FluidImpulse {
    /// The impulse strength 0.4…1 of an ANL-004 onset; nil when strength or threshold is not finite.
    public static func strength(onset strength: Float, threshold: Float) -> Float? {
        guard strength.isFinite, threshold.isFinite else { return nil }
        let excess: Float = (strength - threshold) / 0.5
        return 0.4 + 0.6 * min(max(excess, 0), 1)
    }
}

/// One applied impulse: a Gaussian splat (domain units, y down; ink in linear light).
public struct FluidSplat: Sendable, Equatable {
    public var centerX: Float
    public var centerY: Float
    public var velocityX: Float
    public var velocityY: Float
    public var red: Float
    public var green: Float
    public var blue: Float

    public init(centerX: Float, centerY: Float, velocityX: Float, velocityY: Float, red: Float, green: Float, blue: Float) {
        self.centerX = centerX
        self.centerY = centerY
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let zero = FluidSplat(centerX: 0, centerY: 0, velocityX: 0, velocityY: 0, red: 0, green: 0, blue: 0)

    /// The seeded splat of impulse `index` at `strength` (positions 0.15…0.85, any direction, a palette colour).
    public static func seeded(index: UInt64, strength: Float, reduceMotion: Bool, palette: UnsafePointer<SIMD3<Float>>,
                              paletteCount: Int) -> FluidSplat {
        var rng = SplitMix64(seed: FluidInk.seed &* 0x1000_0000_01B3 ^ index &* 0x9E37_79B9_7F4A_7C15)
        let x: Float = 0.15 + 0.7 * Float(rng.unit())
        let y: Float = 0.15 + 0.7 * Float(rng.unit())
        let angle: Float = 2 * Float.pi * Float(rng.unit())
        let t: Float = Float(rng.unit())
        let speed: Float = strength * FluidInk.splatSpeed * (reduceMotion ? FluidInk.reduceMotionScale : 1)
        let n: Int = max(paletteCount, 1)
        let position: Float = t * Float(n - 1)
        let i: Int = min(Int(position), max(n - 2, 0))
        let f: Float = position - Float(i)
        let a: SIMD3<Float> = palette[i]
        let b: SIMD3<Float> = palette[min(i + 1, n - 1)]
        let color: SIMD3<Float> = (a + (b - a) * f) * (strength * FluidInk.splatInk)
        return FluidSplat(centerX: x, centerY: y, velocityX: speed * cos(angle), velocityY: speed * sin(angle),
                          red: min(max(color.x, 0), 1), green: min(max(color.y, 0), 1), blue: min(max(color.z, 0), 1))
    }
}

/// The fixed-step clock and the impulse queue (VIS-011-R5, R6). Steps start at the anchor (the first frame's time);
/// step k ends at anchor + k·10⁹/60 ns. `advance` plans every step that ends by the frame's time, at most 4; a longer
/// gap skips the rest and re-anchors (counted). An impulse applies at the first step whose start is at or after its
/// time. All storage is made in `init`. Not Sendable: one thread.
public final class FluidStepScheduler {
    public private(set) var anchorNanoseconds: UInt64?
    public private(set) var stepIndex: UInt64 = 0
    /// Steps planned by the last `advance`.
    public private(set) var plannedSteps = 0
    public private(set) var droppedImpulses = 0
    public private(set) var appliedImpulses = 0
    public private(set) var skippedGaps = 0
    /// Steps run since the last reset.
    public private(set) var totalSteps: UInt64 = 0
    public var reduceMotion = false
    /// 16 palette stops (linear rgb) the splats take their colours from.
    public let palette: UnsafeMutablePointer<SIMD3<Float>>
    public static let paletteCount = 16

    private var times: [UInt64]
    private var strengths: [Float]
    private var head = 0
    private var count = 0
    private var impulseIndex: UInt64 = 0
    private var lastAcceptedStart: UInt64?
    /// Planned splats: step s uses `splats[s·2 ..< s·2 + splatCounts[s]]`.
    private var splats: [FluidSplat]
    private var splatCounts: [Int]

    public init() {
        times = [UInt64](repeating: 0, count: FluidInk.queueCapacity)
        strengths = [Float](repeating: 0, count: FluidInk.queueCapacity)
        splats = [FluidSplat](repeating: .zero, count: FluidInk.maximumStepsPerFrame * FluidInk.maximumImpulsesPerStep)
        splatCounts = [Int](repeating: 0, count: FluidInk.maximumStepsPerFrame)
        palette = .allocate(capacity: Self.paletteCount)
        palette.initialize(repeating: SIMD3<Float>(1, 1, 1), count: Self.paletteCount)
    }

    deinit {
        palette.deinitialize(count: Self.paletteCount)
        palette.deallocate()
    }

    public var pendingImpulses: Int { count }

    /// Queues an impulse at `nanoseconds` (the frame clock) for an onset. False when ignored (non-finite) or the queue is
    /// full (counted).
    @discardableResult
    public func enqueue(atNanoseconds nanoseconds: UInt64, strength: Float, threshold: Float) -> Bool {
        guard let s = FluidImpulse.strength(onset: strength, threshold: threshold) else { return false }
        guard count < FluidInk.queueCapacity else {
            droppedImpulses += 1
            return false
        }
        let slot = (head + count) % FluidInk.queueCapacity
        times[slot] = nanoseconds
        strengths[slot] = s
        count += 1
        return true
    }

    /// Starts over: no anchor, empty queue, counters kept.
    public func reset() {
        anchorNanoseconds = nil
        stepIndex = 0
        plannedSteps = 0
        head = 0
        count = 0
        lastAcceptedStart = nil
        totalSteps = 0
    }

    /// Plans every step that ends at or before `nanoseconds` (at most `maximumStepsPerFrame`). Returns the count.
    @discardableResult
    public func advance(toNanoseconds nanoseconds: UInt64) -> Int {
        plannedSteps = 0
        guard let anchor = anchorNanoseconds else {
            anchorNanoseconds = nanoseconds
            stepIndex = 0
            return 0
        }
        guard nanoseconds >= anchor else { return 0 }
        while plannedSteps < FluidInk.maximumStepsPerFrame {
            let end: UInt64 = anchor &+ FluidInk.stepOffset(stepIndex &+ 1)
            guard end <= nanoseconds else { return plannedSteps }
            planStep(plannedSteps, start: anchor &+ FluidInk.stepOffset(stepIndex))
            stepIndex &+= 1
            totalSteps &+= 1
            plannedSteps += 1
        }
        if anchor &+ FluidInk.stepOffset(stepIndex &+ 1) <= nanoseconds {
            anchorNanoseconds = nanoseconds   // a stall: skip the rest of the gap
            stepIndex = 0
            skippedGaps += 1
        }
        return plannedSteps
    }

    /// Splat count of planned step `step`.
    public func splatCount(step: Int) -> Int { splatCounts[step] }
    /// Splat `k` of planned step `step`.
    public func splat(step: Int, _ k: Int) -> FluidSplat { splats[step * FluidInk.maximumImpulsesPerStep + k] }

    private func planStep(_ s: Int, start: UInt64) {
        var n = 0
        var budget: Float = FluidInk.maximumStrengthPerStep
        while count > 0, times[head] <= start {
            let strength: Float = strengths[head]
            head = (head + 1) % FluidInk.queueCapacity
            count -= 1
            if reduceMotion, let last = lastAcceptedStart, start &- last < FluidInk.reduceMotionSpacingNanoseconds {
                droppedImpulses += 1   // ACC-001: fewer impulses
                continue
            }
            guard n < FluidInk.maximumImpulsesPerStep, budget > 0 else {
                droppedImpulses += 1
                continue
            }
            let applied: Float = min(strength, budget)
            budget -= applied
            splats[s * FluidInk.maximumImpulsesPerStep + n] = FluidSplat.seeded(index: impulseIndex, strength: applied,
                                                                               reduceMotion: reduceMotion,
                                                                               palette: palette, paletteCount: Self.paletteCount)
            impulseIndex &+= 1
            appliedImpulses += 1
            lastAcceptedStart = start
            n += 1
        }
        splatCounts[s] = n
    }
}

/// VIS-011-R10: a rigorous upper bound of the ink per channel. A splat raises a cell by at most its peak colour;
/// bilinear advection is a convex combination (it cannot raise the maximum) and the fade lowers it; values are capped.
public struct FluidInkBound: Sendable, Equatable {
    public private(set) var level = SIMD3<Float>(0, 0, 0)

    public init() {}

    public mutating func reset() { level = SIMD3<Float>(0, 0, 0) }

    /// One step with `splats`: M ← min(cap, fade × min(cap, M + Σ peaks)).
    public mutating func step(splatSum: SIMD3<Float>) {
        let cap = SIMD3<Float>(repeating: FluidInk.inkCap)
        let raised: SIMD3<Float> = simd_min_compat(level + splatSum, cap)
        level = simd_min_compat(raised * FluidInk.inkFactor, cap)
    }

    private func simd_min_compat(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(Swift.min(a.x, b.x), Swift.min(a.y, b.y), Swift.min(a.z, b.z))
    }
}

/// The fields' health: largest speed and ink, kinetic energy ½ Σ |v|² h², and whether a non-finite value was seen.
public struct FluidInkHealth: Sendable, Equatable {
    public var maxSpeed: Float
    public var maxInk: Float
    public var kineticEnergy: Float
    public var nonFinite: Bool

    public init(maxSpeed: Float = 0, maxInk: Float = 0, kineticEnergy: Float = 0, nonFinite: Bool = false) {
        self.maxSpeed = maxSpeed
        self.maxInk = maxInk
        self.kineticEnergy = kineticEnergy
        self.nonFinite = nonFinite
    }

    /// A non-finite value, or a value over its cap beyond the tolerance (VIS-011-R7).
    public func needsReset(speedCap: Float) -> Bool {
        let t: Float = 1 + FluidInk.healthTolerance
        return nonFinite || !(maxSpeed <= speedCap * t) || !(maxInk <= FluidInk.inkCap * t)
            || !kineticEnergy.isFinite
    }

    /// ½ × cells × cap² × h²: the energy of every cell at the speed cap (the absolute bound, VIS-011-S1).
    public static func energyBound(speedCap: Float) -> Float { 0.5 * speedCap * speedCap }
}
