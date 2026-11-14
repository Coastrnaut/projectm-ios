// ParticleFountainConfiguration.swift — the particle fountain's parameters, burst size, launch draw and seeded
// generator (VIS-008-R2, R3, R4, R7, R9; data-model.md; research VIS-008-D2, D5, D6).
//
// Lengths are in R, half the output's shorter side; positions are measured from the emitter (bottom centre,
// 0.1 R above the bottom edge), y up. `init` clamps; properties set later are clamped by `clamped()`, which
// every consumer applies. Non-finite values take their defaults. Pure Swift (every platform).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// SplitMix64 (research VIS-008-D5): a pure 64-bit integer generator, identical on every platform.
public struct SplitMix64: Sendable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1): the top 53 bits.
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }
}

public struct ParticleFountainConfiguration: Sendable, Equatable {
    public static let gravityRange: ClosedRange<Double> = 0.5...10
    public static let dragRange: ClosedRange<Double> = 0...5
    public static let lifeRange: ClosedRange<Double> = 0.5...10
    public static let sizeRange: ClosedRange<Double> = 0.005...0.1
    public static let defaultGravity = 3.0
    public static let defaultDrag = 0.8
    public static let defaultLife = 2.5
    public static let defaultParticleSize = 0.025
    /// "VIS-008" in hex-speak.
    public static let defaultSeed: UInt64 = 0x5EED_0008

    /// VIS-008-R5: the pool and the pending-onset queue.
    public static let capacity = 512
    public static let onsetQueueCapacity = 32
    /// VIS-008-R3: the fixed step, and the most steps one advance runs.
    public static let stepsPerSecond = 240
    public static let maximumStepsPerAdvance = 240
    /// VIS-008-R2: burst = minimumBurst + round(burstRange · e), e = clamp((s − θ) / excessScale, 0, 1).
    public static let minimumBurst = 4
    public static let burstRange = 20
    public static let excessScale = 0.25
    /// Launch cone half-angle (radians, 20°) and speed range (R/s).
    public static let coneHalfAngle = 20.0 * Double.pi / 180
    public static let minimumSpeed = 3.0
    public static let maximumSpeed = 4.0
    /// The emitter's height above the bottom edge (R).
    public static let emitterHeight = 0.1
    /// VIS-008-R4: death below this height or beyond this side distance (R).
    public static let floorHeight = -0.15
    public static let sideBound = 3.0
    /// VIS-008-R7: the brightest alpha (ACC-012: below full white) and the fade-in, seconds.
    public static let peakAlpha = 0.8
    public static let attackSeconds = 0.05
    /// Palette colours cycled by spawn sequence.
    public static let paletteColors = 16
    /// Smallest drawn side, pixels.
    public static let minimumSidePixels = 2.0
    /// VIS-008-R9: Reduce Motion's time scale.
    public static let reduceMotionTimeScale = 0.7

    /// G, R/s² (Low 2.0, Medium 3.0, High 4.5 in the app).
    public var gravity: Double
    /// Linear drag k, per second.
    public var drag: Double
    /// Seconds from spawn to death (before Reduce Motion).
    public var life: Double
    /// A particle's side, fraction of R (at least 2 px drawn).
    public var particleSize: Double
    /// Restored at every reset.
    public var seed: UInt64
    /// ACC-001: halves bursts and slows the motion (applies to later bursts).
    public var reduceMotion: Bool
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(gravity: Double = ParticleFountainConfiguration.defaultGravity,
                drag: Double = ParticleFountainConfiguration.defaultDrag,
                life: Double = ParticleFountainConfiguration.defaultLife,
                particleSize: Double = ParticleFountainConfiguration.defaultParticleSize,
                seed: UInt64 = ParticleFountainConfiguration.defaultSeed, reduceMotion: Bool = false,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.gravity = gravity
        self.drag = drag
        self.life = life
        self.particleSize = particleSize
        self.seed = seed
        self.reduceMotion = reduceMotion
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range.
    public func clamped() -> ParticleFountainConfiguration {
        var c = self
        c.gravity = Self.clamp(gravity, Self.gravityRange, Self.defaultGravity)
        c.drag = Self.clamp(drag, Self.dragRange, Self.defaultDrag)
        c.life = Self.clamp(life, Self.lifeRange, Self.defaultLife)
        c.particleSize = Self.clamp(particleSize, Self.sizeRange, Self.defaultParticleSize)
        c.background = background.clamped
        return c
    }

    /// The motion's time scale: 0.7 under Reduce Motion, else 1.
    public var timeScale: Double { reduceMotion ? Self.reduceMotionTimeScale : 1 }
    /// Values a particle spawned now carries (VIS-008-R9: the same arc, `timeScale` times as fast).
    public var effectiveGravity: Double { gravity * timeScale * timeScale }
    public var effectiveDrag: Double { drag * timeScale }
    public var effectiveLife: Double { life / timeScale }

    /// VIS-008-R2: the burst for an onset (4…24; halved, rounded up, under Reduce Motion).
    public static func burstSize(strength: Float, threshold: Float, reduceMotion: Bool) -> Int {
        let excess: Double = Double(strength) - Double(threshold)
        let e: Double = excess.isFinite ? min(max(excess / excessScale, 0), 1) : 0
        let n: Int = minimumBurst + Int((Double(burstRange) * e).rounded())
        return reduceMotion ? (n + 1) / 2 : n
    }

    /// Alpha at `age` for a particle living `life` seconds (VIS-008-R7).
    public static func alpha(age: Double, life: Double) -> Double {
        guard age >= 0, age < life, life > 0 else { return 0 }
        let ramp: Double = min(1, age / attackSeconds)
        return peakAlpha * ramp * (1 - age / life)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
