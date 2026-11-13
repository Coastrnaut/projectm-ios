// PeakCapTracker.swift — the linear spectrum's peak caps (VIS-002-R6; research VIS-002-D3;
// data-model.md).
//
// Per bar: a peak p and the hold time left. Each frame, with frame time dt clamped to 0…0.1 s (the
// FX-019 clamp; never a wall clock) and the bar's displayed value v:
//   v ≥ p → p = v and the hold restarts;
//   else  → the hold is used first (h = min(hold left, dt)), then p falls by fall·(dt − h), but
//           never below v.
// Hold time used up mid-frame flows into the fall, so the motion is exact for any frame rate.
// Storage for 128 bars is allocated in `init`; `update` allocates nothing. Not Sendable: one owner.

public final class PeakCapTracker {
    public static let capacity = SpectrumBarCount.maximum
    public static let maxFrameTime = FlashSafetyLimiter.maxFrameTime

    public var holdSeconds: Double
    public var fallPerSecond: Double
    private let peaks: UnsafeMutablePointer<Double>
    private let holds: UnsafeMutablePointer<Double>

    public init(holdSeconds: Double = LinearSpectrumConfiguration.defaultPeakHoldSeconds,
                fallPerSecond: Double = LinearSpectrumConfiguration.defaultPeakFallPerSecond) {
        self.holdSeconds = holdSeconds
        self.fallPerSecond = fallPerSecond
        peaks = .allocate(capacity: Self.capacity)
        peaks.initialize(repeating: 0, count: Self.capacity)
        holds = .allocate(capacity: Self.capacity)
        holds.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        peaks.deinitialize(count: Self.capacity); peaks.deallocate()
        holds.deinitialize(count: Self.capacity); holds.deallocate()
    }

    /// Bar `k`'s peak, 0…1.
    public func peak(_ k: Int) -> Double { peaks[k] }

    /// Every cap back to 0 (a new bar count or orientation, or a loop restart).
    public func reset() {
        peaks.update(repeating: 0, count: Self.capacity)
        holds.update(repeating: 0, count: Self.capacity)
    }

    /// Advances the first `count` bars (at most 128) by one frame. `values` are the displayed values
    /// (0…1; anything else is sanitized); missing values read 0; bars from `count` on are untouched.
    public func update(values: UnsafeBufferPointer<Float>, count: Int, frameTime: Double) {
        let dt = frameTime > 0 ? min(frameTime, Self.maxFrameTime) : 0
        let hold = holdSeconds.isFinite ? max(holdSeconds, 0) : 0
        let fall = fallPerSecond.isFinite ? max(fallPerSecond, 0) : 0
        for k in 0..<min(max(count, 0), Self.capacity) {
            let v = Double(k < values.count ? sanitizedBandValue(values[k]) : 0)
            if v >= peaks[k] {
                peaks[k] = v
                holds[k] = hold
            } else {
                let held = min(holds[k], dt)
                holds[k] -= held
                peaks[k] = max(v, peaks[k] - fall * (dt - held))
            }
        }
    }
}
