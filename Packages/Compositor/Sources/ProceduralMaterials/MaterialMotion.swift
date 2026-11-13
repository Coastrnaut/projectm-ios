// MaterialMotion.swift — a material's animation phase and its smoothed music level (SHD-001-R5,
// R10; research SHD-001-D5; data-model.md "MaterialMotion").
//
// Advanced once per frame from the frame context's duration (no wall clock), so the same frame
// sequence always gives the same phase. Music changes only the speed: the band level (mean of the
// finite bands, clamped 0…1) is followed by a level that rises at most 4 per second and falls at
// most 1 per second, and the phase advances by dt · speed · (1 + reactivity · level); with
// reactivity ≤ 1 music at most doubles the speed. The phase is integrated, so a speed change never
// jumps the picture. Plain Swift; builds on Linux.
import Compositor

public struct MaterialMotion: Sendable, Equatable {
    public static let maxRisePerSecond = 4.0
    public static let maxFallPerSecond = 1.0

    /// Accumulated cycles.
    public private(set) var phase: Double = 0
    /// The smoothed music level, 0…1.
    public private(set) var audioLevel: Double = 0

    public init() {}

    /// One frame: `frameDuration` is clamped to 0…`LayerFrameClock.maxFrameDuration` (NaN reads 0),
    /// `bandLevel` to 0…1 (NaN reads 0), `reactivity` to 0…1; a non-finite speed reads 0.
    public mutating func advance(frameDuration: Double, bandLevel: Double, speed: Double, reactivity: Double) {
        let dt = frameDuration > 0 ? min(frameDuration, LayerFrameClock.maxFrameDuration) : 0
        let target = bandLevel.isFinite ? min(max(bandLevel, 0), 1) : 0
        if target > audioLevel {
            audioLevel = min(target, audioLevel + Self.maxRisePerSecond * dt)
        } else {
            audioLevel = max(target, audioLevel - Self.maxFallPerSecond * dt)
        }
        let r = reactivity.isFinite ? min(max(reactivity, 0), 1) : 0
        let s = speed.isFinite ? speed : 0
        phase += dt * s * (1 + r * audioLevel)
    }

    /// The speed multiplier music gives now (1…2 for reactivity 0…1).
    public func speedMultiplier(reactivity: Double) -> Double {
        1 + min(max(reactivity.isFinite ? reactivity : 0, 0), 1) * audioLevel
    }

    /// The mean of the finite band values, clamped to 0…1; 0 when there are none.
    public static func bandLevel(_ bands: UnsafeBufferPointer<Float>) -> Double {
        var sum = 0.0
        var count = 0
        for v in bands where v.isFinite {
            sum += Double(min(max(v, 0), 1))
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// Phase 0, level 0.
    public mutating func reset() {
        phase = 0
        audioLevel = 0
    }
}
