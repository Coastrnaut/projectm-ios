# Data Model: MOD-009 Tempo-Synced LFO

## LFOSync (ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| beatsPerCycle | Double | one of 0.25, 0.5, 1, 2, 4, 8 |

Constants: `allowedBeatsPerCycle`, `minimumBPM = 40`, `maximumBPM = 240`.
`rateHz(bpm:) = clamp(bpm, 40, 240) / 60 / beatsPerCycle`.

## LFO (MOD-007, extended)

Adds `sync: LFOSync?` (default nil). Effective rate at a tempo: `sync` and a usable BPM → `sync.rateHz(bpm:)`,
else `rateHz`; then `min(·, maximumRateHz)`.

## Phase segment (LFOBank, private)

| Field | Meaning |
|---|---|
| start | frame time (ns) where the segment begins |
| phase | phase (cycles, 0…<1) at `start` |
| rateHz | effective rate during the segment |

Created at the first frame after `set` (phase = phaseOffset); replaced, continuous, when the effective rate
changes. One per slot; only synced slots use it.

## Scene entry (SceneFormat)

`lfos[i].sync`: optional object, `beats` (number) required inside it; other keys kept verbatim.
Issues: `invalidLFOSync`, `unknownLFOSync` (warnings).

## TempoSnapshot.lfoTempoBPM (PerformanceControl)

`bpm` of the snapshot: manual, else confident estimate (≥ 0.5, 60…200), else nil.
