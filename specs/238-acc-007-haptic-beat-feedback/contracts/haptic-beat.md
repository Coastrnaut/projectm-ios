# Contract: ACC-007 Haptic Beat Feedback

## C1 `HapticPulseGate` (PerformanceControl)

`mutating func consider(_ cue: HapticCue, eventNanoseconds: UInt64, now: UInt64, playable: Bool) -> HapticPulseDecision`

1. `.sessionBoundary` → beat count 0, `.filtered`.
2. `.beat(c)` with c < rules' confidence → `.filtered`. A confident beat increments the beat count; it is a downbeat when `(count − 1) % beatsPerBar == 0`.
3. Choice: `beats` accepts confident beats, `downbeats` confident downbeats, `kicks` kicks; anything else → `.filtered`.
4. `!playable` → `.suppressed`.
5. `now > eventNanoseconds + stale` → `.stale`.
6. `eventNanoseconds` earlier than the last pulse + minimum interval, or the 4th-last pulse within 1 s, or the 180th-last within 60 s → `.throttled`.
7. Otherwise records the time and returns `.pulse`.

Changing the choice keeps the beat count; `reset()` clears count, ring and counters.

## C2 `HapticCue.init?(_ event: AnalysisEvent)` (PerformanceControlAnalysis)

beat → `.beat(confidence)`; transient band `.kick` → `.kick`; session started/ended → `.sessionBoundary`; others → nil.

## C3 `HapticBeatCoordinator` (app)

- Settings (C5 keys) with `enabled`, `choice`, `strength`; the observer is installed only while on with haptic hardware (`observesAnalysis`); Off → `tempo.analysisEventObserver = nil` and no call on the player. `isAvailable` (the switch) is the hardware or the DEBUG override.
- `handle(_ event:)`: maps (C2); `playable` = app active ∧ ¬Low Power Mode ∧ hardware haptics ∧ intensity limit > 0.25; gate (C1); on `.pulse` calls `player.play(strength:intensity:)` with intensity = the clamp's intensity limit.
- Counters `pulses`, `throttled` for tests and diagnostics.

## C4 Settings section

Section "Haptics" after Reduce flashing (`.id("haptics")`): `Toggle("Haptic beat pulses")` id `hapticBeatToggle`;
while on, `Picker("Pulse on")` id `hapticBeatEventPicker` and `Picker("Strength")` id `hapticBeatStrengthPicker`.
Disabled without haptics. Footer: "Short taps on the beat while a visual runs. At most 4 per second; they pause
in Low Power Mode and in the background, follow the sensory safety profile and stop under Strict." plus
"This device has no haptics." when unsupported.

## C5 Storage

`settings.haptics.beatPulses`, `settings.haptics.beatEvent`, `settings.haptics.strength`: FILE-005 included,
`ALLOWED_KEYS`, UI-test reset, `LibraryBackupAppTests` app keys.
