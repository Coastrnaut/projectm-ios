// LissajousAutoGain.swift — the Lissajous scope's automatic gain with hold (VIS-004-R6; research VIS-004-D4).
//
// The level is the coordinate that reaches the plot's edge. It follows a rise of the window's peak at once,
// holds for `holdSeconds` after the last rise, then falls with a `releaseHalfLife` half-life, never below the
// current peak or `floor` (at most 40 dB of gain). Time advances only by the frame durations passed in,
// clamped to 0…`maxFrameDuration` (no wall clock), so a sequence of inputs always gives the same levels.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct LissajousAutoGain: Sendable, Equatable {
    public static let floor = 0.01
    public static let holdSeconds = 0.5
    public static let releaseHalfLife = 0.5
    public static let maxFrameDuration = 0.1

    /// The full-scale reference (≥ `floor`).
    public private(set) var level: Double = LissajousAutoGain.floor
    /// Seconds since the last rise.
    public private(set) var sinceRise: Double = 0

    public init() {}

    public mutating func reset() {
        level = Self.floor
        sinceRise = 0
    }

    /// A frame duration made valid: NaN or negative → 0, at most `maxFrameDuration`.
    public static func clampedDuration(_ seconds: Double) -> Double {
        seconds.isFinite && seconds > 0 ? min(seconds, maxFrameDuration) : 0
    }

    /// Advances by one frame whose window peaked at `peak` and returns the new level.
    @discardableResult
    public mutating func update(peak: Double, frameDuration: Double) -> Double {
        let dt: Double = Self.clampedDuration(frameDuration)
        let p: Double = peak.isFinite ? max(peak, 0) : 0
        if p >= level {
            level = max(p, Self.floor)
            sinceRise = 0
            return level
        }
        let before: Double = sinceRise
        sinceRise += dt
        if sinceRise > Self.holdSeconds {
            // Only the part of this frame past the hold decays.
            let decaying: Double = sinceRise - max(before, Self.holdSeconds)
            level *= pow(0.5, decaying / Self.releaseHalfLife)
        }
        level = max(level, p, Self.floor)
        return level
    }
}
