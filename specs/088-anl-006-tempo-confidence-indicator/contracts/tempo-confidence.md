# Contract C1: tempo confidence indicator (ANL-006)

## Package `PerformanceControl`

```swift
public enum TempoConfidenceState: String, Sendable, Hashable, Codable { case searching, uncertain, stable }

public struct TempoConfidenceRules: Sendable, Hashable {
    public static let standard: TempoConfidenceRules        // 0.7 / 0.5, 2 s / 1 s, 3 s, 3 %, 60…200
    public init(enterConfidence:exitConfidence:enterDwellNanoseconds:exitDwellNanoseconds:
                reacquireNanoseconds:bpmTolerance:minimumBPM:maximumBPM:)   // precondition-checked
}

public struct TempoConfidenceIndicator: Sendable {
    public init(rules: TempoConfidenceRules = .standard)
    public private(set) var state: TempoConfidenceState     // .searching at start
    public private(set) var bpm: Double?                    // nil while searching
    public private(set) var confidence: Double              // 0 while searching
    public private(set) var stateChanges: Int
    public mutating func update(_ estimate: TempoEstimate?, at nanoseconds: UInt64)
    public mutating func reset()                            // back to .searching, counters kept
}

public enum TempoReadout: Sendable, Hashable {
    case manual(bpm: Double), stable(bpm: Double), uncertain(bpm: Double), searching
    public init(snapshot: TempoSnapshot, indicator: TempoConfidenceIndicator)
}
```

Guarantees:

- Deterministic; reads no clock; allocates nothing per update.
- `stable` only after confidence ≥ enter with BPM within tolerance for ≥ enter dwell; left only
  after the exit condition held for ≥ exit dwell (spec ANL-006-R4).
- `confidence` reports the input's (clamped) value; the indicator never raises it.
- `TempoSnapshot` and `TempoSource` are unchanged (ANL-006-R10).

## App (`TempoCoordinator`, `TempoControls`)

| Readout | Number line | Word line | Accessibility value (label "Tempo") |
|---|---|---|---|
| manual(120) | 120 BPM | Manual | 120 BPM, manual |
| stable(120) | 120 BPM | Stable | 120 BPM, stable |
| uncertain(120) | ≈120 BPM | Uncertain | About 120 BPM, uncertain |
| searching | — | Searching | Searching for tempo |

- BPM is rounded to a whole number. The element stays static text (ACC-004), identifier
  `tempoReadout`; the Tap control's value uses the same accessibility value outside a tap sequence.
- Reset announcement: "Manual tempo cleared. " followed by "Detected tempo 120 BPM" (stable),
  "Tempo uncertain, about 120 BPM" (uncertain) or "Searching for tempo" (searching).
- DEBUG: `-uitestTempoEstimate <bpm>:<confidence>[:<polls>:<confidence2>]` replaces each poll's
  estimate (research ANL-006-D7).
