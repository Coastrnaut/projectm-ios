// NoiseFieldDrive.swift — how the bands move the noise field (VIS-013-R5, R7, R8; research VIS-013-D3).
//
// Per frame: VIS-007's band groups → targets (warp = base + depth × low; brightness = 0.5 + 0.3 × overall, ≤ 0.8) →
// one-pole smoothing on the frame's duration (τ 0.25 s; the frame time clamped to 0…0.1 s) → the drift phase on the
// injected clock (cells, from the first frame after a reset; at most 1 s per frame, never backwards). No wall clock,
// no random source, no allocation. Pure Swift (every platform). Not Sendable: one thread.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct NoiseFieldDrive: Sendable, Equatable {
    /// Domain warp, cells.
    public private(set) var warp: Double = NoiseFieldConfiguration.baseWarp
    /// 0.5…0.8.
    public private(set) var brightness: Double = NoiseFieldConfiguration.baseBrightness
    /// Drift, cells.
    public private(set) var phase: Double = 0
    private var lastNanoseconds: UInt64?

    public init() {}

    /// Back to silence: base warp and brightness, drift 0; the next frame is the new anchor.
    public mutating func reset() {
        self = NoiseFieldDrive()
    }

    /// Warp and brightness targets for `groups`.
    public static func targets(_ groups: MandalaBandGroups, configuration: NoiseFieldConfiguration) -> (warp: Double, brightness: Double) {
        let low: Double = min(max(groups.low.isFinite ? groups.low : 0, 0), 1)
        let overall: Double = min(max(groups.overall.isFinite ? groups.overall : 0, 0), 1)
        let warp: Double = NoiseFieldConfiguration.baseWarp + configuration.effectiveBandWarp * low
        let lit: Double = NoiseFieldConfiguration.baseBrightness + NoiseFieldConfiguration.bandBrightness * overall
        return (warp, min(lit, NoiseFieldConfiguration.maximumBrightness))
    }

    /// Advances to the frame at `nanoseconds` with `groups`, smoothing over `frameDuration` seconds.
    public mutating func advance(groups: MandalaBandGroups, timeNanoseconds nanoseconds: UInt64, frameDuration: Double,
                                 configuration: NoiseFieldConfiguration) {
        let target: (warp: Double, brightness: Double) = Self.targets(groups, configuration: configuration)
        let dt: Double = frameDuration.isFinite ? min(max(frameDuration, 0), NoiseFieldConfiguration.maxFrameTime) : 0
        let k: Double = 1 - exp(-dt / NoiseFieldConfiguration.smoothingTimeConstant)
        warp += (target.warp - warp) * k
        brightness += (target.brightness - brightness) * k
        brightness = min(brightness, NoiseFieldConfiguration.maximumBrightness)
        if let last = lastNanoseconds, nanoseconds > last {
            let seconds: Double = min(Double(nanoseconds - last) / 1e9, NoiseFieldConfiguration.maxDriftStep)
            phase += configuration.effectiveDriftSpeed * seconds
        }
        if lastNanoseconds == nil || nanoseconds > lastNanoseconds! { lastNanoseconds = nanoseconds }
    }
}
