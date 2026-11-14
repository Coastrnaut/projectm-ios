// ParticleOrbitConfiguration.swift — the particle orbit's parameters and its bass-to-radius mapping (VIS-009-R2 to R7,
// R9; data-model.md; research VIS-009-D3).
//
// Lengths are in R, half the output's shorter side; positions are measured from the output's centre, y up. `init`
// clamps; properties set later are clamped by `clamped()`, which every consumer applies. Non-finite values take their
// defaults. Pure Swift (every platform).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct ParticleOrbitConfiguration: Sendable, Equatable {
    public static let countRange: ClosedRange<Int> = 16...256
    public static let radiusRange: ClosedRange<Double> = 0.2...0.8
    public static let depthRange: ClosedRange<Double> = 0...1
    public static let speedRange: ClosedRange<Double> = 0.1...3
    public static let sizeRange: ClosedRange<Double> = 0.005...0.1
    public static let defaultCount = 160
    public static let defaultRadius = 0.5
    public static let defaultDepth = 0.4
    public static let defaultSpeed = 0.8
    public static let defaultParticleSize = 0.022
    /// "VIS-009" in hex-speak.
    public static let defaultSeed: UInt64 = 0x5EED_0009

    /// VIS-009-R6: the slots and the pending-beat queue.
    public static let capacity = 256
    public static let beatQueueCapacity = 16
    /// VIS-008's fixed step and the most steps one advance runs.
    public static let stepsPerSecond = 240
    public static let maximumStepsPerAdvance = 240
    /// VIS-009-R3: the drawn radius never leaves these bounds (R).
    public static let minimumRadius = 0.15
    public static let maximumRadius = 0.85
    /// A slot's radial offset is 1 + spread·(2u − 1).
    public static let offsetSpread = 0.1
    /// A slot's angular speed is angularSpeed · (speedLow + speedSpan·u).
    public static let speedLow = 0.75
    public static let speedSpan = 0.5
    /// Radius response: one-pole time constant (s) and rate limit (R/s); Reduce Motion values second.
    public static let radiusTimeConstant = 0.06
    public static let reducedRadiusTimeConstant = 0.15
    public static let radiusRate = 3.0
    public static let reducedRadiusRate = 1.5
    /// VIS-009-R5: the beat pulse's decay (s) and the centre's growth at a full pulse.
    public static let pulseTimeConstant = 0.2
    public static let pulseAmplitude = 0.5
    public static let reducedPulseAmplitude = 0.2
    /// The centre square's side at rest (R).
    public static let coreSize = 0.12
    /// VIS-009-R7: alphas (ACC-012: below 0.8).
    public static let particleAlpha = 0.75
    public static let coreAlpha = 0.7
    public static let paletteColors = 16
    public static let minimumSidePixels = 2.0
    /// VIS-009-R9: Reduce Motion's angular speed factor.
    public static let reduceMotionSpeedScale = 0.5

    /// Particles drawn (the first `particleCount` slots).
    public var particleCount: Int
    /// The base radius (R) when nothing is bound.
    public var radius: Double
    /// How far a full bass pushes the radius out: target = base × (1 + depth × bass).
    public var bassDepth: Double
    /// Mean angular speed, rad/s (counter-clockwise).
    public var angularSpeed: Double
    /// A particle's side, fraction of R (at least 2 px drawn).
    public var particleSize: Double
    /// Restored at every reset.
    public var seed: UInt64
    /// ACC-001: slower turn, smaller pulse, slower radius response (applied at once).
    public var reduceMotion: Bool
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(particleCount: Int = ParticleOrbitConfiguration.defaultCount,
                radius: Double = ParticleOrbitConfiguration.defaultRadius,
                bassDepth: Double = ParticleOrbitConfiguration.defaultDepth,
                angularSpeed: Double = ParticleOrbitConfiguration.defaultSpeed,
                particleSize: Double = ParticleOrbitConfiguration.defaultParticleSize,
                seed: UInt64 = ParticleOrbitConfiguration.defaultSeed, reduceMotion: Bool = false,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.particleCount = particleCount
        self.radius = radius
        self.bassDepth = bassDepth
        self.angularSpeed = angularSpeed
        self.particleSize = particleSize
        self.seed = seed
        self.reduceMotion = reduceMotion
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range.
    public func clamped() -> ParticleOrbitConfiguration {
        var c = self
        c.particleCount = min(max(particleCount, Self.countRange.lowerBound), Self.countRange.upperBound)
        c.radius = Self.clamp(radius, Self.radiusRange, Self.defaultRadius)
        c.bassDepth = Self.clamp(bassDepth, Self.depthRange, Self.defaultDepth)
        c.angularSpeed = Self.clamp(angularSpeed, Self.speedRange, Self.defaultSpeed)
        c.particleSize = Self.clamp(particleSize, Self.sizeRange, Self.defaultParticleSize)
        c.background = background.clamped
        return c
    }

    /// The radius one-pole time constant and rate limit in effect.
    public var effectiveRadiusTimeConstant: Double { reduceMotion ? Self.reducedRadiusTimeConstant : Self.radiusTimeConstant }
    public var effectiveRadiusRate: Double { reduceMotion ? Self.reducedRadiusRate : Self.radiusRate }
    /// The centre's growth at a full pulse.
    public var effectivePulseAmplitude: Double { reduceMotion ? Self.reducedPulseAmplitude : Self.pulseAmplitude }
    /// Angular speed factor (0.5 under Reduce Motion).
    public var speedScale: Double { reduceMotion ? Self.reduceMotionSpeedScale : 1 }

    /// VIS-009-R3: the target radius for `base` (R) and `bass` (0…1; clamped, non-finite reads 0), within
    /// 0.15…0.85 R. Monotone non-decreasing in `bass` for a non-negative depth.
    public static func targetRadius(base: Double, bass: Double, depth: Double) -> Double {
        let b: Double = bass.isFinite ? min(max(bass, 0), 1) : 0
        let d: Double = depth.isFinite ? min(max(depth, depthRange.lowerBound), depthRange.upperBound) : defaultDepth
        let r0: Double = base.isFinite ? base : defaultRadius
        let target: Double = r0 * (1 + d * b)
        return min(max(target, minimumRadius), maximumRadius)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
