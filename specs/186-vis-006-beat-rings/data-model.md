# Data Model: VIS-006 Beat Pulse Rings

- **BeatRingConfiguration** (value): `life` seconds (0.5…5, default 1.5; non-finite → default), `lineThickness` (fraction of the shorter side, 0.001…0.05, default 0.015), `palette`, `background` (premultiplied linear). Constants: `startRadius` 0.05, `endRadius` 0.95, `peakAlpha` 0.8, `attack` 0.05 s, `maximumRings` 16, `segmentsPerRing` 64, `minimumInterval` 1/6 s, `reducedInterval` 1/3 s. `minimumInterval(for: FlashEnvelopeConfiguration)` → 1/3 s when `riseRatePerSecond != nil`, else 1/6 s.
- **BeatRingField** (reference, preallocated 16 slots): per slot `birthNanoseconds`, `sequence`; `newestBirth`, `accepted` (count of accepted rings). `emit(atNanoseconds:minimumInterval:) -> Bool`; `forEachRing(atNanoseconds:life:_:) -> Int` and `rings(atNanoseconds:life:)` (live rings oldest first; expired ones pruned); `reset()`.
- **BeatRing** (value): `sequence`, `birthNanoseconds`, `age` s, `radius` (fraction of half the shorter side), `alpha`.
- **BeatRingTrigger** (value): `lastConfidentBeatNanoseconds?`; `shouldEmit(_ event: AnalysisEvent) -> Bool`.
- **Setting**: `settings.beatRings.life` = `short` | `medium` | `long` (1.0 / 1.5 / 2.5 s); anything else → medium.
