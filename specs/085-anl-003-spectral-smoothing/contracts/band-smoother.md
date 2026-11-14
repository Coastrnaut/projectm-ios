# Contract C1: BandSmoother (AnalysisFeatures)

```swift
public struct SmoothingTimes: Sendable, Equatable {
    public static let range: ClosedRange<Double>      // 0...2 seconds
    public static let instant: SmoothingTimes
    public var attackSeconds: Double                  // clamped on init
    public var releaseSeconds: Double
    public init(attackSeconds: Double, releaseSeconds: Double)
    public var isInstant: Bool
    /// 1 − exp(ln(0.1)·Δt/τ); 1 when τ == 0; 0 when Δt is not finite or ≤ 0 (τ > 0).
    public static func coefficient(timeConstant: Double, frameInterval: Double) -> Double
}

public final class BandSmoother {
    public static let capacity: Int                   // 128
    public var times: SmoothingTimes
    public init(times: SmoothingTimes = .instant)
    /// Smooths `count` values of `target` (count clamped to 0...capacity) over `frameInterval`
    /// seconds; returns the smoothed vector (valid until the next call). Allocation-free.
    public func update(target: UnsafePointer<Float>, count: Int, frameInterval: Double,
                       generation: UInt64) -> UnsafeBufferPointer<Float>
    /// The next update takes its input directly.
    public func reset()
}
```

Guarantees (ANL-003-R1 to R5, R7):

1. A step from y₀ to x held for frames with total time T leaves (x − y)/(x − y₀) = exp(ln 0.1 · T/τ).
2. With `times.isInstant` the output equals the input bit for bit (non-finite bands excepted: held).
3. Snap on first update, `reset()`, a count change or a generation change.
4. Outputs are finite whenever previous outputs were finite.
5. No allocation, lock, log or I/O in `update`.

# Contract C2: NativeSpectrumHost (app)

- `var smoothing: SmoothingTimes` — set by the coordinator from the settings; next frame.
- Per frame: `raw = readLatest(...)`; `drawn = smoother.update(raw, bandCount, Δt = link.timestamp − previous link.timestamp, session)`;
  modulation reads `raw`, the spectra draw `drawn`; the oscilloscope still draws samples.
- `resume()` / presentation resume / bar-count change reset the smoother.
