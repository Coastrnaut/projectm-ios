# Data Model: ANL-005 Adaptive Beat Tracker

All types live in `Packages/AnalysisFeatures` and are value types except the tracker. Times are
sample indices on the stream's sample clock (`Int64`), or fractional sample positions (`Double`)
for fitted grid values.

## BeatTrackerConfiguration (struct, Sendable, Hashable)

| Field | Default | Valid |
|---|---|---|
| `sampleRate` (Double, Hz) | 44,100 | finite, ≥ 8,000 |
| `minimumBPM` (Double) | 60 | ≥ 30 |
| `maximumBPM` (Double) | 200 | ≤ 300, ≥ 1.5 × minimum |
| `preferredBPM` (Double) | 120 | minimum…maximum |
| `windowSeconds` (Double) | 6 | 2…16 |
| `timingToleranceSeconds` (Double) | 0.035 | 0.005…0.1 |
| `silenceTimeoutSeconds` (Double) | 4 | 1…16 and > 1.5 × 60 / minimum |

Fixed constants (static): `maximumOnsets` 64, `gridStepBPM` 0.25, `maximumLagSeconds` 4,
`harmonics` 4, `recencyHalfLifeSeconds` 2, `hysteresis` 0.9, `minimumMatchedBeats` 4.
Errors: `BeatTrackerConfigurationError` — one case per field, carrying the rejected value
(`invalidSampleRate`, `invalidTempoRange(min, max)`, `invalidPreferredTempo`, `invalidWindow`,
`invalidTimingTolerance`, `invalidSilenceTimeout`). `.standard` = the defaults.

## BeatEstimate (struct, Sendable, Hashable)

`bpm`, `periodSamples`, `anchorSample` (the fitted beat nearest the last matched onset),
`nextBeatSample` (first grid time ≥ position, rounded), `confidence` and its factors `precision`,
`coverage`, `support`, `freshness` (each 0…1), `matchedBeats`, `onsetsInWindow`, `sampleRate`,
`position` (the position it describes). Invariants: 60 ≤ bpm ≤ 200 (configured range);
confidence = product of the factors; matchedBeats ≥ 4.

## BeatEvent (struct, Sendable, Hashable)

`sequence` (UInt64, 1, 2, 3… per tracker lifetime), `sampleIndex` (rounded predicted beat),
`bpm`, `periodSamples`, `confidence`, `sampleRate`; `seconds` = sampleIndex / sampleRate.

## AdaptiveBeatTracker (final class, not Sendable)

State: onset ring (capacity 64, sample indices), per-onset recency scratch, score histogram and
preference table (bins = (max − min)/0.25 + 1), current fit (period, anchor, last matched onset,
factors), position (optional), last reported beat (optional), counters (`acceptedOnsets`,
`ignoredOnsets`, `ignoredPositions`, `skippedBeats`, `suppressedBeats`, `beatCount`).

State transitions:

```text
no tempo ──(add: fit with ≥ 4 matched beats)──▶ tracking
tracking ──(add: new fit)──▶ tracking (estimate replaced; fewer than 4 matched keeps the old one)
tracking ──(advance: position − last matched ≥ timeout)──▶ no tempo (history cleared)
no tempo ──(advance: position − newest onset ≥ timeout)──▶ no tempo (history cleared)
any ──(reset)──▶ no tempo (history and position cleared; sequence and counters kept)
```
