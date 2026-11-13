// GraphMotion.swift — a graph's phase and its music follower (SHD-002-R9, R11; data-model.md
// "GraphMotion").
//
// Advanced once per frame from the frame context's duration (no wall clock), so the same frame
// sequence always gives the same phase. The music level follows the band level (mean of the finite
// bands, clamped 0…1; 0 with none) and moves toward it by at most `musicRate` per second in either
// direction (at most 1, lower when the compiler's bound says so). The phase advances by
// dt · speed, with the speed already clamped by the compiled graph. Plain Swift; builds on Linux.
import Compositor

public struct GraphMotion: Sendable, Equatable {
    /// Accumulated phase in cycles.
    public private(set) var phase: Double = 0
    /// The followed music level, 0…1.
    public private(set) var musicLevel: Double = 0

    public init() {}

    /// One frame: `frameDuration` clamped to 0…`LayerFrameClock.maxFrameDuration` (NaN reads 0),
    /// `bandLevel` to 0…1 (NaN reads 0), `musicRate` to 0…1; a non-finite speed reads 0.
    public mutating func advance(frameDuration: Double, bandLevel: Double, speed: Double, musicRate: Double) {
        let dt = frameDuration > 0 ? min(frameDuration, LayerFrameClock.maxFrameDuration) : 0
        let target = bandLevel.isFinite ? min(max(bandLevel, 0), 1) : 0
        let rate = musicRate.isFinite ? min(max(musicRate, 0), 1) : 0
        let step = rate * dt
        musicLevel = target > musicLevel ? min(target, musicLevel + step) : max(target, musicLevel - step)
        phase += dt * (speed.isFinite ? speed : 0)
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
        musicLevel = 0
    }
}
