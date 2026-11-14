# Contract: band-limited transient detector, kick on the bus, Kick source (ANL-007)

## C1 — `TransientDetectorConfiguration` (AnalysisFeatures)

```swift
public enum TransientBand: Sendable, Hashable, CaseIterable { case kick }
public struct TransientDetectorConfiguration: Sendable, Hashable {
    public static let kick: TransientDetectorConfiguration      // 44.1 kHz, 40–150 Hz, defaults below
    public init(band: TransientBand = .kick, sampleRate: Double = 44_100,
                lowerFrequency: Double = 40, upperFrequency: Double = 150,
                floorDecibels: Float = -70, dominanceDecibels: Float = -15,
                baselineSeconds: Double = 1.0, minimumRiseDecibels: Float = 9,
                deviationMultiplier: Float = 4, refractorySeconds: Double = 0.1,
                envelopeSeconds: Double = 0.1) throws(TransientDetectorConfigurationError)
    public func baselineFrames(hop: Int) -> Int            // round(s·R/hop), 1…128
    public var refractorySamples: Int64                    // round(s·R)
    public func envelopeDecay(hop: Int) -> Float           // exp(−hop/(τ·R))
}
public struct TransientEvent: Sendable, Hashable { band, sequence, sampleIndex, frameIndex,
    strength /*dB rise*/, threshold /*dB*/, level /*dB*/, sampleRate, timestampNanoseconds; seconds }
```

Errors: `invalidSampleRate`, `invalidFrequencyRange(lower, upper)`, `invalidFloor`,
`invalidDominance`, `invalidBaselineWindow`, `invalidMinimumRise`, `invalidDeviationMultiplier`,
`invalidRefractoryPeriod`, `invalidEnvelopeTime` (ranges in data-model.md).

## C2 — `BandTransientDetector` (AnalysisFeatures)

```swift
public final class BandTransientDetector {
    public init(configuration: TransientDetectorConfiguration = .kick, backend: SpectrumBackend = .automatic)
    public func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> TransientEvent?
    public func process(_ frame: SpectrumFrame, magnitudes: [Float]) -> TransientEvent?
    public func reset()
    public private(set) var envelope: Float          // 0…1
    public private(set) var lastLevel, lastRise /*D*/, lastThreshold, lastShare: Float   // dB
    public private(set) var processedFrames, ignoredFrames: Int
    public private(set) var eventCount: UInt64
    public static func recommendedLeadIn() -> SpectrumLeadIn   // .silence
}
```

Per accepted frame (rate matches, `magnitudes.count == size.binCount`, 1 ≤ hop ≤ size):

1. P_band = Σ w_k·m_k² / 1.5 over the range's bins (ANL-002 weight rule); P_total = Σ_{k=1…N/2} m_k² / 1.5.
   Non-finite sums read 0. L = max(floor, 10·log10(max(P_band, 1e−12))).
2. If the frame is the first after `reset()`/an ignored frame, not contiguous (index ≠ previous
   index + previous hop) or has another size: clear the level history (keep the D window), push L
   into the level history, decay the envelope, no event.
3. Else reference = the highest of the last r = clamp(size/hop, 1, 8) levels (fewer if fewer exist;
   the history is seeded with one floor level at creation and `reset()`), D = L − reference;
   share = 10·log10(ΔP_band / ΔP_total) against the reference frame (0 dB when ΔP_total < ΔP_band,
   −200 when either did not rise); median and MAD of the D window (0 and 0 if empty), threshold =
   max(minimumRise, median + k·MAD); push D into its window (oldest dropped beyond
   `baselineFrames(hop:)`) and L into the level history.
4. envelope ← envelope · decay.
5. If rise ≤ threshold: armed = true, no event. Else (armed' = armed; armed = false) an event iff
   armed', L > floor, share ≥ dominance, and (no previous event or sample − last ≥ refractorySamples).
6. On an event: envelope = 1, sequence += 1.

No allocation, lock, log, I/O or clock in `process`. Not Sendable.

## C3 — Bus (ANL-016)

- `AnalysisPipelineConfiguration(…, kick: .kick)`; `sampleRateMismatch` when its rate differs.
- Per frame the pipeline runs the kick detector after the onset detector and tracker; the frame
  carries `kickEnvelope = detector.envelope`; after the frame and its onset and beat, a kick event
  is published as `AnalysisEvent(kind: .transient(band: .kick, strength:, threshold:, level:),
  eventSample: event.sampleIndex)`.
- A session start resets the detector.

## C4 — MOD-002 / SHD-009 / app

- `AudioFeatureSource.kick`, `id == "audio.kick"`, `init?(id: "audio.kick") == .kick`;
  `value(in:)` = `frame.kick` (nil / non-finite → 0).
- `AudioFeatureFrame(bands:onset:beatConfidence:kick:)` (all but bands defaulted).
- `ExpressionOpcode.kick = 9`, stack effect +1, cost 1; the name `audio.kick` compiles in a formula.
- `LiveBandFrameInfo.kickEnvelope`; `NativeSpectrumHost` passes the last envelope read to its
  bindings every frame.
