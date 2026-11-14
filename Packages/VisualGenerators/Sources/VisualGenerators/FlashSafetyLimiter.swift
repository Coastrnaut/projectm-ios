// FlashSafetyLimiter.swift — Reduce flashing and the strobe safety envelope for native visuals
// (FR-072; VIS-001-R10; FX-001-R10; FX-019-R9, R11; research VIS-001-D7, FX-019-D6; ADR-0011).
//
// 1. With Reduce flashing on, each displayed bar value moves toward its band value by at most
//    `maxBarStepPerSecond` × frame time (VIS-001's slew; softens rises and falls alike). Off, values
//    pass through (sanitized), but the state keeps tracking, so turning it on starts from the
//    current picture.
// 2. Every frame, on or off, the uniform gain ≤ 1 on the bars' colors comes from FlashSafety's
//    `FlashEnvelope` (FX-019): `.reduceFlashing` (at most 4 transitions per 1 s window in each of the
//    17 areas and both signals, rises of at most 0.25 per second) or the always-on cap (6, no rate).
//    `gain(for:transfer:…)` gives it the layout's area levels after downstream stages (the glow,
//    FX-001-R10), solved by bisection; the whole-frame-only overloads keep VIS-001's and FX-001's
//    entry points. Frame time is clamped to 0…`maxFrameTime`.
// `reset()` (the host's loop restart) restarts only the bar slew; the envelope's history is kept so a
// pause cannot restart a strobe's budget (FX-019-R11). `resetEnvelope()` forgets it too.
//
// Real-time safety: 128 values and the envelope's state preallocated; no allocation, lock or I/O
// per frame. Not Sendable.
import FlashSafety

public final class FlashSafetyLimiter {
    public static let maxBarStepPerSecond: Float = 4
    /// The envelope's rise rate with Reduce flashing on (FlashEnvelopeConfiguration.reduceFlashing).
    public static let maxLuminanceRisePerSecond = FlashEnvelopeConfiguration.reduceFlashing.riseRatePerSecond ?? 0
    public static let maxFrameTime = FlashEnvelopeConfiguration.reduceFlashing.maxFrameTime

    /// FX-019: the strobe safety envelope applied to every frame.
    public let envelope = FlashEnvelope()
    /// Whole-frame-only inputs of `gain(barsLuminance:…)` (the tiles stay 0).
    private let scaled = UnsafeMutableBufferPointer<FlashLevels>.allocate(capacity: FlashZones.count)
    private let offset = UnsafeMutableBufferPointer<FlashLevels>.allocate(capacity: FlashZones.count)
    private let displayed: UnsafeMutablePointer<Float>
    private var hasDisplayed = false

    public init() {
        displayed = .allocate(capacity: SpectrumBarCount.maximum)
        displayed.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        scaled.initialize(repeating: .zero)
        offset.initialize(repeating: .zero)
    }

    deinit {
        displayed.deinitialize(count: SpectrumBarCount.maximum)
        displayed.deallocate()
        scaled.deallocate()
        offset.deallocate()
    }

    /// The next frame's bars start from their own values (no slew from a stale state), as after a
    /// suspension. The envelope's history is kept (FX-019-R11).
    public func reset() {
        hasDisplayed = false
    }

    /// Also forgets the envelope's history (a new visual).
    public func resetEnvelope() {
        hasDisplayed = false
        envelope.reset()
    }

    @inline(__always)
    private static func clampedFrameTime(_ t: Double) -> Double {
        t > 0 ? min(t, maxFrameTime) : 0
    }

    /// The values to draw this frame (at most 128; valid until the next call).
    public func limitValues(_ targets: UnsafeBufferPointer<Float>, frameTime: Double, enabled: Bool) -> UnsafeBufferPointer<Float> {
        let n = min(targets.count, SpectrumBarCount.maximum)
        if enabled && hasDisplayed {
            let step = Self.maxBarStepPerSecond * Float(Self.clampedFrameTime(frameTime))
            for k in 0..<n {
                let target = sanitizedBandValue(targets[k])
                let current = displayed[k]
                displayed[k] = current + min(max(target - current, -step), step)
            }
        } else {
            for k in 0..<n { displayed[k] = sanitizedBandValue(targets[k]) }
        }
        // Bars beyond the input read 0 from now on, so a later longer input slews from 0.
        if n < SpectrumBarCount.maximum {
            for k in n..<SpectrumBarCount.maximum { displayed[k] = 0 }
        }
        hasDisplayed = true
        return UnsafeBufferPointer(start: displayed, count: n)
    }

    /// The gain (0…1) for the bars' colors, given the whole frame's luminance parts at gain 1
    /// (VIS-001's entry point; the 16 tiles read 0, so only the whole-frame area is limited).
    public func gain(barsLuminance: Double, backgroundLuminance: Double, frameTime: Double, enabled: Bool) -> Float {
        let bars = barsLuminance.isFinite ? max(barsLuminance, 0) : 0
        let background = backgroundLuminance.isFinite ? max(backgroundLuminance, 0) : 0
        scaled[FlashZones.wholeFrame] = FlashLevels(luminance: bars, redness: 0)
        offset[FlashZones.wholeFrame] = FlashLevels(luminance: background, redness: 0)
        return envelope.gain(scaled: UnsafeBufferPointer(scaled), offset: UnsafeBufferPointer(offset),
                             frameTime: frameTime, configuration: .forReduceFlashing(enabled))
    }

    /// Bisection steps of the envelope (precision 2⁻²⁴ ≈ 6e-8).
    public static let bisectionSteps = FlashEnvelope.bisectionSteps

    /// The gain (0…1) for a frame whose whole-frame mean luminance at gain g is `luminanceAtGain(g)`,
    /// nondecreasing in g (FX-001's entry point; research FX-001-D4). No allocation.
    public func gain(frameTime: Double, enabled: Bool, luminanceAtGain: (Float) -> Double) -> Float {
        envelope.gain(frameTime: frameTime, configuration: .forReduceFlashing(enabled)) { g, out in
            out[FlashZones.wholeFrame] = FlashLevels(luminance: luminanceAtGain(g), redness: 0)
        }
    }

    /// The gain for a spectrum laid out in `layout` (circular, VIS-001; linear, VIS-002) whose frame
    /// then passes through downstream stages described by `transfer` (FX-001-R10): all 17 areas,
    /// both signals (FX-019-R4). The closure is non-escaping: no allocation.
    public func gain<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(for layout: Source, transfer: Transfer,
                                                       frameTime: Double, enabled: Bool) -> Float {
        gain(for: layout, transfer: transfer, frameTime: frameTime, configuration: .forReduceFlashing(enabled))
    }

    /// ACC-012: the same with an explicit envelope (the sensory safety profile's limits;
    /// `VisualFrameContext.flashConfiguration`). With `.forReduceFlashing(enabled)` it is the overload above.
    public func gain<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(for layout: Source, transfer: Transfer,
                                                       frameTime: Double, configuration: FlashEnvelopeConfiguration) -> Float {
        envelope.gain(frameTime: frameTime, configuration: configuration) { g, out in
            layout.meanLevels(gain: g, transfer: transfer, into: out)
        }
    }
}
