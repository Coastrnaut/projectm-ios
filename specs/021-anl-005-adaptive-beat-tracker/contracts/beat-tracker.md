# Contract: Adaptive beat tracker (ANL-005)

Module `AnalysisFeatures`. Pull API only; confined to one worker; nothing into projectM
(ANL-005-R16).

```swift
public struct BeatTrackerConfiguration: Sendable, Hashable {
    public static let standard: BeatTrackerConfiguration
    public init(sampleRate: Double = 44_100, minimumBPM: Double = 60, maximumBPM: Double = 200,
                preferredBPM: Double = 120, windowSeconds: Double = 6,
                timingToleranceSeconds: Double = 0.035,
                silenceTimeoutSeconds: Double = 4) throws(BeatTrackerConfigurationError)
}

public final class AdaptiveBeatTracker {
    public static let highConfidence: Double          // 0.5
    public let configuration: BeatTrackerConfiguration
    public let resolvedBackend: SpectrumBackend
    public init(configuration: BeatTrackerConfiguration = .standard, backend: SpectrumBackend = .automatic)

    public func add(_ onset: OnsetEvent)              // ignored + counted: other rate, not after the previous onset
    public func add(onsetAt sampleIndex: Int64)       // same, for taps and tests
    public func advance(to position: Int64) -> BeatEvent?
    public func process(_ frame: SpectrumFrame, onset: OnsetEvent?) -> BeatEvent?   // add, then advance(to: index + size)
    public var estimate: BeatEstimate? { get }        // nil = no tempo
    public var confidence: Double { get }             // estimate?.confidence ?? 0
    public func reset()
    // counters: acceptedOnsets, ignoredOnsets, ignoredPositions, skippedBeats, suppressedBeats, beatCount
}
```

## Rules

1. `add` keeps onsets of the last `windowSeconds` (by the newest onset) and at most 64, then
   re-fits (ANL-005-R3 to R6). No allocation.
2. `advance(to: p)`: a `p` lower than the previous position is ignored and counted. Otherwise: if
   the estimate's last matched onset is `timeout` or more before `p` the estimate and history are
   dropped (no beat); if there is no estimate and the newest onset is `timeout` before `p` the
   history is dropped. Then, if an estimate exists and a previous position `p0` exists, the latest
   grid beat `b` with `p0 − τ ≤ b < p` is reported, unless it is closer than half a period to the last
   reported beat (`suppressedBeats`); other beats in `[p0, p)` count as `skippedBeats`. The τ allowance
   catches a beat that a re-fit on this frame's onset moved from just after `p0` to just before it
   (implementation finding 2026-11-13: `pulse-132` at 48 kHz lost one beat without it).
3. `process(frame, onset)`: `add(onset)` if present, then `advance(to: frame.index + frame.size)`.
4. Determinism: bit-identical outputs for identical inputs and configuration; the accelerated and
   portable backends are bit-identical (ANL-005-R12).

## Example (per spectrum frame on the analysis worker)

```swift
let detector = SpectralFluxOnsetDetector()
let tracker = AdaptiveBeatTracker()
while let frame = stream.nextFrame() {
    let onset = detector.process(frame, magnitudes: stream.magnitudes)
    if let beat = tracker.process(frame, onset: onset),
       beat.confidence >= AdaptiveBeatTracker.highConfidence { /* hand to the consumer */ }
}
```
