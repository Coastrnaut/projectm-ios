# Data Model: SHOW-011 Tap Tempo

All times are monotonic nanoseconds (`UInt64`) on the clock the analysis bus uses
(`MonotonicClock`, ANL-016-R5); the model never reads a clock itself.

## TapTempoRules (value, Codable)

| Field | Default | Rule |
|---|---|---|
| `tapsToEstablish` | 4 | ≥ 2 |
| `minimumBPM` / `maximumBPM` | 60 / 200 | 0 < min < max |
| `pauseNanoseconds` | 2,000,000,000 | > the slowest period |
| `maximumTaps` | 8 | ≥ `tapsToEstablish` |
| `minimumEstimateConfidence` | 0.5 | 0…1 |

Derived: `shortestIntervalNanoseconds` = 60e9 / max (300 ms), `longestIntervalNanoseconds` =
60e9 / min (1 s).

## TapOutcome (enum)

`counting(taps: Int, of: Int)` (first tap, a pause restart, or taps 2-3), `established(bpm:)`
(the tap that set a manual tempo where there was none), `refined(bpm:)` (a later tap that changed
an existing manual tempo, including a new sequence's fourth tap), `tooFast` (tap ignored),
`tooSlow` (sequence restarted at this tap; count 1).

## TempoEstimate (value, Codable)

`bpm: Double`, `confidence: Double` (0…1), `beatNanoseconds: UInt64?` (a beat time; nil until the
first beat event).

## TempoOrigin (enum, Codable)

`manual`, `estimated`, `none`.

## TempoSnapshot (value, Codable) — the read API

| Field | Manual | Estimated | None |
|---|---|---|---|
| `origin` | `.manual` | `.estimated` | `.none` |
| `bpm` | tapped | estimate's | nil |
| `confidence` | 1 | estimate's | 0 |
| `periodNanoseconds` | 60e9 / bpm (rounded) | same | nil |
| `anchorNanoseconds` | last tap | latest beat (or nil) | nil |

`nextBeat(atOrAfter:)` → the first `anchor + k·period ≥ t` (k may be negative); nil without anchor.
`beatPhase(at:)` → 0..<1 position within the beat; nil without anchor.

## TempoSource (value)

State: `rules`, accepted tap times of the current sequence (≤ `maximumTaps`), `manual` (bpm,
period, anchor) or nil, `estimate` or nil.

Transitions:

```text
none/estimated --4th accepted tap--> manual
manual --further taps--> manual (refined)
manual --reset--> estimated (confident estimate) | none
any --estimate update--> unchanged origin if manual; estimated/none otherwise
```

Validation: an estimate outside the BPM range or below the confidence floor does not count (origin
none unless manual).

## TempoEstimateTracker (PerformanceControlAnalysis)

State: latest frame tempo and confidence, latest beat host time; cleared by session start/end
events. Output: `TempoEstimate?`.

## TempoCoordinator (app)

Observable: `snapshot`, `tapsInSequence`, `lastOutcome`. Not stored.
