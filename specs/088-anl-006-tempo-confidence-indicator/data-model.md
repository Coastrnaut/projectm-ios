# Data Model: ANL-006 Tempo Confidence Indicator

No stored data. All values are in memory, on the main actor in the app.

## TempoConfidenceState (enum, String raw values)

`searching`, `uncertain`, `stable`.

## TempoConfidenceRules (struct, Sendable, Hashable)

| Field | Standard | Rule |
|---|---|---|
| enterConfidence | 0.7 | > exitConfidence |
| exitConfidence | 0.5 | ≥ 0, < enterConfidence |
| enterDwellNanoseconds | 2 000 000 000 | > 0 |
| exitDwellNanoseconds | 1 000 000 000 | > 0 |
| reacquireNanoseconds | 3 000 000 000 | > 0 |
| bpmTolerance | 0.03 | relative, > 0 |
| minimumBPM / maximumBPM | 60 / 200 | SHOW-011's range |

## TempoConfidenceIndicator (struct, Sendable)

| Field | Meaning |
|---|---|
| state | current state (starts `searching`) |
| bpm | the estimate's BPM while uncertain or stable; nil while searching |
| confidence | the last usable estimate's confidence (clamped), 0 while searching |
| lockedBPM | the BPM at entry to stable; nil otherwise |
| stateChanges | number of transitions since creation (diagnostics, flicker tests) |
| private: run start time and BPM, exit-condition start and cause, reacquire start, last time |

Transitions: research ANL-006-D3.

## TempoReadout (enum, Sendable, Hashable)

`manual(bpm)`, `stable(bpm)`, `uncertain(bpm)`, `searching`. Built from a `TempoSnapshot` (manual
wins) and an indicator.
