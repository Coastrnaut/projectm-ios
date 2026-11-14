# Contract: Tempo-synced LFO (MOD-009)

## T1 Sync length

`LFOSync(beatsPerCycle:) throws(LFOError)`: accepts exactly ¼, ½, 1, 2, 4, 8; `allowedBeatsPerCycle`;
`minimumBPM = 40`, `maximumBPM = 240`; `static func usableBPM(_ bpm: Double?) -> Double?` (nil for nil,
non-finite or ≤ 0; else clamped to 40…240); `rateHz(bpm: Double) -> Double` = usable BPM / 60 / beats.

## T2 Oscillator

`LFO(shape:rateHz:phaseOffset:amplitude:center:sync: = nil)`; `validationProblem` also checks `sync`.
`effectiveRateHz(tempoBPM: Double?, maximumRateHz: Double = .infinity) -> Double`.
`value(elapsedNanoseconds:tempoBPM:maximumRateHz:)`: the closed form at the constant effective rate.
`static func phase(from start: Double, elapsedNanoseconds: UInt64, rateHz: Double) -> Double`: MOD-007's exact
phase from a start phase; `phase(elapsedNanoseconds:rateHz:)` equals it with `phaseOffset`.

## T3 Bank

`values(atNanoseconds:tempoBPM: Double? = nil, maximumRateHz:into:)`. Free slots: unchanged (MOD-007 L3).
Synced slots: phase segment (research MOD-009-D2); a time before the segment start reads the segment's start
phase. Deterministic for equal sequences of (time, tempo, cap); allocation-free; `set` resets segments.
`hasSyncedOscillators`.

## T4 Tempo source

`TempoSnapshot.lfoTempoBPM: Double?` (PerformanceControl) = `bpm`: manual > estimate (confidence ≥ 0.5,
60…200 BPM) > nil.

## T5 Scene field

`lfos[i].sync = {"beats": n}`, optional, written by `SceneLFOEntry(_:)` only when `lfo.sync` is set.

| Problem | Code | Path | Oscillator |
|---|---|---|---|
| `sync` not an object | `invalidLFOSync` | `$.lfos[i].sync` | live, unsynced |
| `beats` missing, not a number, not finite or ≤ 0 | `invalidLFOSync` | `$.lfos[i].sync.beats` | live, unsynced |
| `beats` finite positive but not allowed | `unknownLFOSync` | `$.lfos[i].sync.beats` | live, unsynced |

Both are warnings; the entry is kept verbatim. Errors from MOD-007's fields take precedence (the oscillator is
nil and the sync is not examined).

## T6 App

`NativeSpectrumHost.lfoTempoBPM: (@MainActor () -> Double?)?`, read once per frame while a synced oscillator
exists; `AppCoordinator.connectLFOs` sets it to `tempo.snapshot.lfoTempoBPM`. Reduce flashing still caps.
