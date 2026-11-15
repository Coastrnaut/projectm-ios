// SignedDistanceDrive.swift — how the bands move VIS-017's scene (VIS-017-R6; spec Clarifications Q4).
//
// Per frame: VIS-007's groups of the ANL-002 bands (each sanitized: not finite → 0, clamped to 0…1) → targets: swell = low,
// spin = 0.25 + 0.35 × mid rad/s (≤ 0.6), brightness = 0.5 + 0.3 × overall (≤ 0.8, ACC-012) → one-pole smoothing on the
// injected clock's step (swell attack τ 0.08 s, release 0.3 s; spin 0.5 s; brightness 0.25 s; the step clamped to
// 0…0.25 s, never backwards) → the angle advances by spin × step and wraps to [0, 2π). Reduce Motion (ACC-001) halves the
// spin and the swell depth. The first frame after a reset only anchors the clock. No wall clock, no random source, no
// allocation. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct SignedDistanceDrive: Sendable, Equatable {
    public static let baseSpin = 0.25
    public static let midSpin = 0.35
    public static let maximumSpin = 0.6
    public static let swellAttack = 0.08
    public static let swellRelease = 0.3
    public static let spinTimeConstant = 0.5
    public static let brightnessTimeConstant = 0.25
    public static let bandBrightness = 0.3
    public static let maxStep = 0.25
    public static let reduceMotionScale = 0.5

    /// Smoothed low group, 0…1.
    public private(set) var swell: Double = 0
    /// Turning speed, rad/s (smoothed).
    public private(set) var spin: Double = SignedDistanceDrive.baseSpin
    /// Radians in [0, 2π).
    public private(set) var angle: Double = 0
    /// 0.5…0.8.
    public private(set) var brightness: Double = Double(SignedDistanceScene.baseBrightness)
    /// Reduce Motion of the last frame.
    public private(set) var reduceMotion = false
    private var lastNanoseconds: UInt64?

    public init() {}

    public mutating func reset() { self = SignedDistanceDrive() }

    static func clean(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }

    /// The spin target (rad/s) for a mid group `mid`.
    public static func spinTarget(mid: Double, reduceMotion: Bool) -> Double {
        let s: Double = min(baseSpin + midSpin * clean(mid), maximumSpin)
        return reduceMotion ? s * reduceMotionScale : s
    }

    /// The brightness target for an overall level `overall`.
    public static func brightnessTarget(overall: Double) -> Double {
        min(Double(SignedDistanceScene.baseBrightness) + bandBrightness * clean(overall), Double(SignedDistanceScene.maximumBrightness))
    }

    /// Advances to the frame at `nanoseconds`.
    public mutating func advance(groups: MandalaBandGroups, timeNanoseconds nanoseconds: UInt64, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard let last = lastNanoseconds else {
            lastNanoseconds = nanoseconds
            spin = Self.spinTarget(mid: groups.mid, reduceMotion: reduceMotion)
            return
        }
        guard nanoseconds > last else { return }   // never backwards
        lastNanoseconds = nanoseconds
        let dt: Double = min(Double(nanoseconds - last) / 1e9, Self.maxStep)
        let low: Double = Self.clean(groups.low)
        let swellTau: Double = low > swell ? Self.swellAttack : Self.swellRelease
        swell += (low - swell) * (1 - exp(-dt / swellTau))
        swell = Self.clean(swell)
        let spinGoal: Double = Self.spinTarget(mid: groups.mid, reduceMotion: reduceMotion)
        spin += (spinGoal - spin) * (1 - exp(-dt / Self.spinTimeConstant))
        spin = min(max(spin, 0), Self.maximumSpin)
        let lit: Double = Self.brightnessTarget(overall: groups.overall)
        brightness += (lit - brightness) * (1 - exp(-dt / Self.brightnessTimeConstant))
        brightness = min(max(brightness, Double(SignedDistanceScene.baseBrightness)), Double(SignedDistanceScene.maximumBrightness))
        let turn: Double = 2 * Double.pi
        angle = (angle + spin * dt).truncatingRemainder(dividingBy: turn)
    }

    /// The frame's pose (sanitized).
    public var pose: SignedDistancePose {
        let depth: Double = reduceMotion ? Double(SignedDistanceScene.sphereSwell) * Self.reduceMotionScale : Double(SignedDistanceScene.sphereSwell)
        return SignedDistancePose(angle: Float(angle), sphereRadius: Float(Double(SignedDistanceScene.sphereRadius) + depth * swell),
                                  brightness: Float(brightness)).sanitized()
    }
}
