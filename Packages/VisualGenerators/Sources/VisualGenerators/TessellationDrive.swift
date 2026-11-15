// TessellationDrive.swift — how the bands move VIS-018's tiles (VIS-018-R7; spec Clarifications Q4).
//
// Per frame: VIS-007's groups of the ANL-002 bands (each sanitized: not finite → 0, clamped to 0…1) → targets: swell =
// low; drift speed 0.02 + 0.04 × mid turns/s (≤ 0.06); light speed 0.25 + 0.25 × high turns/s (≤ 0.5); brightness
// 0.45 + 0.3 × overall (≤ 0.75, ACC-012) → one-pole smoothing on the injected clock's step (swell attack τ 0.08 s,
// release 0.3 s; speeds 0.5 s; brightness 0.25 s; the step clamped to 0…0.25 s, never backwards) → drift and light
// phases advance by speed × step and wrap to [0, 1). The seam inset is 25 % of each tile's inradius at silence and
// 8 % at full swell. Reduce Motion (ACC-001) halves both speeds and the swell depth. The first frame after a reset only
// anchors the clock. The lattice itself never moves (alignment, A6). No wall clock, no random source, no allocation.
// Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One frame's state for the shader and the flash estimate (sanitized).
public struct TessellationFrame: Sendable, Equatable {
    public static let rest = TessellationFrame(inset: TessellationDrive.restInset, drift: 0, light: 0,
                                               brightness: Float(TessellationDrive.baseBrightness))

    /// Seam inset as a fraction of each tile's inradius, 0.08…0.25.
    public var inset: Float
    /// Palette drift, [0, 1).
    public var drift: Float
    /// Travelling-light phase, [0, 1).
    public var light: Float
    /// 0.45…0.75.
    public var brightness: Float

    public init(inset: Float, drift: Float, light: Float, brightness: Float) {
        self.inset = inset
        self.drift = drift
        self.light = light
        self.brightness = brightness
    }

    public func sanitized() -> TessellationFrame {
        func phase(_ v: Float) -> Float {
            guard v.isFinite else { return 0 }
            let f: Float = v - v.rounded(.down)
            return f < 1 && f >= 0 ? f : 0
        }
        let i: Float = inset.isFinite ? min(max(inset, TessellationDrive.fullInset), TessellationDrive.restInset) : TessellationDrive.restInset
        let b: Float = brightness.isFinite ? min(max(brightness, 0), Float(TessellationDrive.maximumBrightness)) : Float(TessellationDrive.baseBrightness)
        return TessellationFrame(inset: i, drift: phase(drift), light: phase(light), brightness: b)
    }
}

public struct TessellationDrive: Sendable, Equatable {
    public static let restInset: Float = 0.25
    public static let fullInset: Float = 0.08
    public static let baseDrift = 0.02
    public static let midDrift = 0.04
    public static let maximumDrift = 0.06
    public static let baseLight = 0.25
    public static let highLight = 0.25
    public static let maximumLight = 0.5
    public static let baseBrightness = 0.45
    public static let bandBrightness = 0.3
    public static let maximumBrightness = 0.75
    public static let swellAttack = 0.08
    public static let swellRelease = 0.3
    public static let speedTimeConstant = 0.5
    public static let brightnessTimeConstant = 0.25
    public static let maxStep = 0.25
    public static let reduceMotionScale = 0.5
    /// The travelling light dims a tile by at most this fraction.
    public static let lightDepth: Float = 0.2

    /// Smoothed low group, 0…1.
    public private(set) var swell: Double = 0
    /// Turns per second (smoothed).
    public private(set) var driftSpeed: Double = TessellationDrive.baseDrift
    public private(set) var lightSpeed: Double = TessellationDrive.baseLight
    /// Phases in [0, 1).
    public private(set) var drift: Double = 0
    public private(set) var light: Double = 0
    public private(set) var brightness: Double = TessellationDrive.baseBrightness
    /// Reduce Motion of the last frame.
    public private(set) var reduceMotion = false
    private var lastNanoseconds: UInt64?

    public init() {}

    public mutating func reset() { self = TessellationDrive() }

    static func clean(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }

    public static func driftTarget(mid: Double, reduceMotion: Bool) -> Double {
        let s: Double = min(baseDrift + midDrift * clean(mid), maximumDrift)
        return reduceMotion ? s * reduceMotionScale : s
    }

    public static func lightTarget(high: Double, reduceMotion: Bool) -> Double {
        let s: Double = min(baseLight + highLight * clean(high), maximumLight)
        return reduceMotion ? s * reduceMotionScale : s
    }

    public static func brightnessTarget(overall: Double) -> Double {
        min(baseBrightness + bandBrightness * clean(overall), maximumBrightness)
    }

    /// Advances to the frame at `nanoseconds`.
    public mutating func advance(groups: MandalaBandGroups, timeNanoseconds nanoseconds: UInt64, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard let last = lastNanoseconds else {
            lastNanoseconds = nanoseconds
            driftSpeed = Self.driftTarget(mid: groups.mid, reduceMotion: reduceMotion)
            lightSpeed = Self.lightTarget(high: groups.high, reduceMotion: reduceMotion)
            return
        }
        guard nanoseconds > last else { return }   // never backwards
        lastNanoseconds = nanoseconds
        let dt: Double = min(Double(nanoseconds - last) / 1e9, Self.maxStep)
        let low: Double = Self.clean(groups.low)
        let swellTau: Double = low > swell ? Self.swellAttack : Self.swellRelease
        swell = Self.clean(swell + (low - swell) * (1 - exp(-dt / swellTau)))
        let speedBlend: Double = 1 - exp(-dt / Self.speedTimeConstant)
        driftSpeed += (Self.driftTarget(mid: groups.mid, reduceMotion: reduceMotion) - driftSpeed) * speedBlend
        driftSpeed = min(max(driftSpeed, 0), Self.maximumDrift)
        lightSpeed += (Self.lightTarget(high: groups.high, reduceMotion: reduceMotion) - lightSpeed) * speedBlend
        lightSpeed = min(max(lightSpeed, 0), Self.maximumLight)
        let lit: Double = Self.brightnessTarget(overall: groups.overall)
        brightness += (lit - brightness) * (1 - exp(-dt / Self.brightnessTimeConstant))
        brightness = min(max(brightness, Self.baseBrightness), Self.maximumBrightness)
        drift = (drift + driftSpeed * dt).truncatingRemainder(dividingBy: 1)
        light = (light + lightSpeed * dt).truncatingRemainder(dividingBy: 1)
    }

    /// The frame's state (sanitized).
    public var frame: TessellationFrame {
        let depth: Double = reduceMotion ? Self.reduceMotionScale : 1
        let span: Double = Double(Self.restInset - Self.fullInset)
        let inset: Double = Double(Self.restInset) - span * depth * swell
        return TessellationFrame(inset: Float(inset), drift: Float(drift), light: Float(light), brightness: Float(brightness)).sanitized()
    }
}
