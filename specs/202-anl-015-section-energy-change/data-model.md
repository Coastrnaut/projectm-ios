# Data Model: ANL-015 Section Energy Change

## SectionChangeConfiguration (value)

| Field | Default | Rule |
|---|---|---|
| sampleRate | 44,100 | finite, > 0 |
| hop | 512 | 1…65,536 (must equal the spectrum hop in the pipeline) |
| windowFrames | 35 | 1…`SectionChangeDetector.maximumWindowFrames` (64) |
| floorDecibels | −70 | finite, < 0 |
| settleSeconds | 2.0 | finite, ≥ 0 |
| referenceSeconds | 8.0 | finite, > 0 (one-pole τ) |
| enterDecibels | 6 | finite, > holdDecibels |
| holdDecibels | 3 | finite, ≥ 0 |
| dwellSeconds | 2.0 | finite, > 0 |
| refractorySeconds | 4.0 | finite, ≥ 0 |
| envelopeSeconds | 1.0 | finite, > 0 (decay τ) |

Derived: `settleSamples`, `dwellSamples`, `refractorySamples` (rounded), per-frame `referenceCoefficient` = 1 − exp(−hop/(τ·rate)), per-frame `envelopeDecay` = exp(−hop/(τ·rate)).

## SectionChangeDirection (enum)

`rising` (quiet → loud), `falling` (loud → quiet).

## SectionChange (value)

direction; `levelDecibels` (slow level at confirmation); `referenceDecibels` (the reference it left); `startSample` (window end of the frame that started it); `confirmSample` (window end of the confirming frame).

## SectionChangeDetector (value, state)

history ring (35 powers), count, slow level, reference, phase (`settling`, `idle`, `pending(direction, start)`, `refractory(until)`), envelope. `process(levelDecibels:frameEnd:) -> SectionChange?`; `reset()`.

## AnalysisFrame additions

`sectionChangeEnvelope: Float` (0…1), `sectionLevelDecibels: Float` (≥ floor).

## AnalysisEventKind addition

`.sectionChange(direction: SectionChangeDirection, levelDecibels: Float, referenceDecibels: Float)`.
