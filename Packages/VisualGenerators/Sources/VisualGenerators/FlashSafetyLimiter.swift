// FlashSafetyLimiter.swift — Reduce flashing for native visuals (FR-072; VIS-001-R10; research
// VIS-001-D7).
//
// While the app's Reduce flashing setting is on:
// 1. each displayed bar value moves toward its band value by at most `maxBarStepPerSecond` × frame
//    time (softens rises and falls alike);
// 2. the frame's mean relative luminance (computed exactly from bar areas and linear colors by
//    `CircularSpectrumLayout.luminanceComponents()`) rises by at most `maxLuminanceRisePerSecond`
//    × frame time; a uniform gain ≤ 1 on the bars' colors enforces it.
// Frame time is clamped to 0…`maxFrameTime`, so a stall never permits a jump. A rise of 0.1 (WCAG's
// flash threshold) therefore takes at least 0.4 s. Falls are only slew-limited; the two-sided
// envelope across every effect is FX-019's. With the setting off, values pass through (sanitized)
// and the gain is 1, but the state keeps tracking, so turning it on continues from the current
// picture without a jump.
//
// Real-time safety: 128 values preallocated; no allocation, lock or I/O per frame. Not Sendable.

public final class FlashSafetyLimiter {
    public static let maxBarStepPerSecond: Float = 4
    public static let maxLuminanceRisePerSecond = 0.25
    public static let maxFrameTime = 0.1

    private let displayed: UnsafeMutablePointer<Float>
    private var hasDisplayed = false
    private var previousLuminance = 0.0
    private var hasPreviousLuminance = false

    public init() {
        displayed = .allocate(capacity: SpectrumBarCount.maximum)
        displayed.initialize(repeating: 0, count: SpectrumBarCount.maximum)
    }

    deinit {
        displayed.deinitialize(count: SpectrumBarCount.maximum)
        displayed.deallocate()
    }

    /// The next frame starts from its own values and brightness (no ramp from a stale state), as
    /// after a suspension.
    public func reset() {
        hasDisplayed = false
        hasPreviousLuminance = false
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

    /// The gain (0…1) for the bars' colors, given the frame's luminance parts at gain 1; records the
    /// luminance actually shown.
    public func gain(barsLuminance: Double, backgroundLuminance: Double, frameTime: Double, enabled: Bool) -> Float {
        let bars = barsLuminance.isFinite ? max(barsLuminance, 0) : 0
        let background = backgroundLuminance.isFinite ? max(backgroundLuminance, 0) : 0
        var gain = 1.0
        if enabled && hasPreviousLuminance {
            let ceiling = previousLuminance + Self.maxLuminanceRisePerSecond * Self.clampedFrameTime(frameTime)
            if bars + background > ceiling, bars > 0 {
                gain = min(1, max(0, (ceiling - background) / bars))
            }
        }
        previousLuminance = bars * gain + background
        hasPreviousLuminance = true
        return Float(gain)
    }

    /// Bisection steps of `gain(frameTime:enabled:luminanceAtGain:)`: precision 2⁻²⁴ ≈ 6e-8.
    public static let bisectionSteps = 24

    /// The gain (0…1) for a frame whose mean luminance at gain g is `luminanceAtGain(g)`,
    /// nondecreasing in g (for example the composited luminance with a glow, FX-001-R10; research
    /// FX-001-D4): the largest g whose luminance stays within the rise bound, found by a fixed
    /// number of bisection steps. Records the luminance actually shown. No allocation.
    public func gain(frameTime: Double, enabled: Bool, luminanceAtGain: (Float) -> Double) -> Float {
        @inline(__always) func sanitized(_ v: Double) -> Double { v.isFinite ? max(v, 0) : 0 }
        var gain: Float = 1
        var shown = sanitized(luminanceAtGain(1))
        if enabled && hasPreviousLuminance {
            let ceiling = previousLuminance + Self.maxLuminanceRisePerSecond * Self.clampedFrameTime(frameTime)
            if shown > ceiling {
                var lo: Float = 0
                var hi: Float = 1
                var loLuminance = sanitized(luminanceAtGain(0))
                if loLuminance <= ceiling {
                    for _ in 0..<Self.bisectionSteps {
                        let mid = (lo + hi) / 2
                        let l = sanitized(luminanceAtGain(mid))
                        if l <= ceiling { lo = mid; loLuminance = l } else { hi = mid }
                    }
                }
                gain = lo
                shown = loLuminance
            }
        }
        previousLuminance = shown
        hasPreviousLuminance = true
        return gain
    }
}
