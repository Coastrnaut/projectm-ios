# Contract: spectral flux onset detector (ANL-004)

Module `AnalysisFeatures`. Extends ANL-001's contract
(`specs/014-anl-001-windowed-fft/contracts/spectrum-analyzer.md`) and uses ANL-002's
(`specs/016-anl-002-log-frequency-bands/contracts/band-reducer.md`).

## Public API

```swift
// ANL-001 deltas (additive)
public enum SpectrumLeadIn: Sendable, Hashable { case none; case silence }
public struct SpectrumFrame: Sendable, Equatable {
    index: Int64; hop: Int; size: FFTSize; sampleRate: Double; timestampNanoseconds: UInt64
    public init(index: Int64, size: FFTSize, sampleRate: Double, timestampNanoseconds: UInt64, hop: Int? = nil)  // nil → size/2
}
public final class SpectrumStream {
    public init(configuration: SpectrumConfiguration, backend: SpectrumBackend = .automatic,
                clock: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds() },
                leadIn: SpectrumLeadIn = .none)
    public let leadIn: SpectrumLeadIn
    // everything else unchanged
}

// ANL-004
public enum OnsetDetectorConfigurationError: Error, Equatable, Sendable {
    case invalidSampleRate(Double), invalidFloor(Float), invalidThresholdOffset(Float),
         invalidThresholdMultiplier(Float), invalidThresholdWindow(Double),
         invalidMinimumInterOnsetInterval(Double)
}
public struct OnsetDetectorConfiguration: Sendable, Hashable {
    public static let defaultFloorDecibels: Float = -70
    public static let defaultThresholdOffset: Float = 0.06
    public static let defaultThresholdMultiplier: Float = 1.5
    public static let defaultThresholdWindowSeconds: Double = 0.1
    public static let defaultMinimumInterOnsetSeconds: Double = 0.05
    public static let maximumHistoryFrames = 128
    public static let standard: OnsetDetectorConfiguration   // the defaults, 44,100 Hz (non-throwing)
    public init(sampleRate: Double = 44_100, bandCount: BandCount = .b64,
                floorDecibels: Float = defaultFloorDecibels, thresholdOffset: Float = defaultThresholdOffset,
                thresholdMultiplier: Float = defaultThresholdMultiplier,
                thresholdWindowSeconds: Double = defaultThresholdWindowSeconds,
                minimumInterOnsetSeconds: Double = defaultMinimumInterOnsetSeconds) throws(OnsetDetectorConfigurationError)
    public func historyFrames(hop: Int) -> Int          // round(window·rate/hop), 1…128
    public var minimumInterOnsetSamples: Int64           // round(interval·rate)
}
public struct OnsetEvent: Sendable, Hashable {
    sequence: UInt64; sampleIndex: Int64; frameIndex: Int64; strength: Float; threshold: Float
    sampleRate: Double; timestampNanoseconds: UInt64
    public var seconds: Double { get }                   // sampleIndex / sampleRate
}
public final class SpectralFluxOnsetDetector {          // not Sendable: confined to one worker
    public let configuration: OnsetDetectorConfiguration
    public let resolvedBackend: SpectrumBackend
    public init(configuration: OnsetDetectorConfiguration = .standard, backend: SpectrumBackend = .automatic)
    public static func recommendedLeadIn() -> SpectrumLeadIn   // .silence
    public func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> OnsetEvent?
    public func process(_ frame: SpectrumFrame, magnitudes: [Float]) -> OnsetEvent?   // convenience, no allocation
    public func reset()                                  // keeps the sequence counter
    public private(set) var lastFlux: Float              // 0…1, this frame's detection value
    public private(set) var lastThreshold: Float
    public private(set) var processedFrames: Int
    public private(set) var ignoredFrames: Int
    public private(set) var eventCount: UInt64           // = last sequence issued
}
```

`OnsetDetectorConfiguration.standard` holds the defaults without a throwing call; `init()` of the
detector uses it. The detector builds a `BandReducer` for the configuration's sample rate, which
cannot fail because the configuration already enforces ANL-002's minimum rate.

## Guarantees

1. `lastFlux` is finite and in 0…1 for any input; exactly 0 when every band of the frame and of
   the previous frame is at or below the floor (silence, quiet noise) and for every baseline frame.
2. At most one event per `process` call; `sequence` strictly increases by 1 per event over the
   detector's lifetime, across `reset()`.
3. Timing: `event.sampleIndex = frame.index + size − hop`. With `leadIn: .silence`, a click at
   sample s that fires in either of the first two frames containing it satisfies |sampleIndex − s|
   ≤ hop (verified for the AUD-016 pulses at hops N/2, N/4, N/8 and for −20 dBFS pulses and unit
   impulses at N/2 and N/4).
4. Determinism: same frames, configuration and backend → identical events and `lastFlux` values.
   Backends: identical events except `strength`/`threshold`, which agree within 1e-4.
5. `process` does not allocate, lock, log or do I/O; allocation happens in `init` only.
6. Frames at another sample rate or with `magnitudes.count != size.binCount` are ignored and
   counted; a gap, size change or ignored frame makes the next accepted frame a baseline.
7. Nothing from this package is passed to projectM (ANL-004-R16).
8. Without a lead-in and with frames built by the old initializer, ANL-001 and ANL-002 behave
   exactly as before.

## Errors

- `OnsetDetectorConfigurationError` from the configuration initializer only; `process` never
  throws or traps on bad frames (they are counted).
