# Research: MOD-006 Threshold Trigger

## MOD-006-D1 Schmitt trigger with strict comparisons

- **Decision**: Fire when armed and `value > high`; re-arm when disarmed and `value < low`; `low < high`
  required. Equality does neither. A new trigger starts armed.
- **Rationale**: Hysteresis is the standard cure for chatter around one threshold: noise smaller than
  `high − low` cannot both re-arm and refire. Strict comparisons make the edges exact and testable.
- **Alternatives**: A single threshold with a refractory period only (ANL-004 style): noise longer than
  the interval still storms. A smoothing envelope before the threshold: delays every event and is
  already available through MOD-005 for bindings.

## MOD-006-D2 Minimum interval consumes early crossings

- **Decision**: After a fire, a crossing (hold satisfied) within `minimumInterval` of the last fire
  disarms without firing; it is never delivered later. Default 100 ms.
- **Rationale**: Deferred delivery would produce events detached from the music and needs a queue.
  Consuming errs toward fewer cue steps. 100 ms matches the detectors' refractory order (ANL-004/007).
- **Alternatives**: Deferred fire at interval end; keeping the trigger armed (it would fire mid-pulse
  when the interval expires, which is late and looks random).

## MOD-006-D3 Hold time

- **Decision**: `hold` (default 0) requires `value > high` continuously, measured from the first frame
  above `high`, until `now − start ≥ hold`. Dropping to `≤ high` or a non-finite value restarts it.
- **Rationale**: Filters short spikes when wanted; continuous requirement is easy to reason about.

## MOD-006-D4 Clock and robustness

- **Decision**: Times are the `UInt64` nanoseconds passed in (the frame's display time). The trigger
  keeps the latest time seen; an earlier time is treated as that latest time (no elapsed time). A
  non-finite value is ignored (no fire, no re-arm, hold restarted). No wall clock, no randomness.
- **Rationale**: Same injected-clock rule as MOD-002/MOD-005; deterministic and frame-rate independent.

## MOD-006-D5 Actions and module boundary

- **Decision**: `ThresholdTriggerAction` in ParameterGraph with raw values `cue.next`, `cue.previous`,
  `blackout`, identical to MIDI-006's `MIDINoteAction`; the app maps by raw value and calls a new
  `MIDINoteActionPerformer.fire(_:)` (the `.fire` path of `perform`). No hold action.
- **Rationale**: ParameterGraph has no dependencies (Linux, Constitution VI); identical identifiers
  keep one vocabulary; the same performer means the same announcements and blackout fade.

## MOD-006-D6 Scene storage

- **Decision**: Optional top-level `triggers` array; each entry is an object kept verbatim
  (`SceneTriggerEntry.fields`), read at restore: `source` (MOD-002 ID), `action`, `high`, `low`
  required; `minimumInterval`, `hold` optional (defaults 0.1, 0). Written only when non-nil, so scenes
  without triggers encode byte-identically and QA-004's matrix is unchanged. A non-object entry or a
  non-array field is a decode error (as FX-020's `effects`). At most 8 entries are applied.
- **Rationale**: Verbatim entries give exact round trips and keep newer fields; FX-020 set the pattern.
- **Alternatives**: Typed entries normalised on write (changes text of hand-written scenes); a
  settings key (rejected in Clarifications).

## MOD-006-D7 Issues

- **Decision**: Two new warning codes: `unknownTrigger` (well-formed but unknown `source` or `action`;
  kept, not applied) at `$.triggers[i].source` / `.action`, and `invalidTrigger` (missing or
  wrong-typed fields, invalid settings, beyond 8) at the field's path (or the entry's). Warnings, so one
  trigger never refuses a scene (MOD-013's ADR-0028 amendment rule).
- **Rationale**: SCN-012 reports by code and path; new codes keep triggers distinguishable from
  bindings.

## MOD-006-D8 App wiring

- **Decision**: `NativeSpectrumHost.setTriggers(_:)`, `onTrigger`, evaluation inside `applyModulation`
  (which now runs when bindings or triggers exist). Triggers come from the scene carry
  (`SceneAutosaveCoordinator.triggerBindings`) when the native visual is created, exactly like bindings
  (SCN-002), and the carry writes the stored list back unchanged.
- **Rationale**: One frame, one feature snapshot; smallest edit to shared files (one line in
  AppCoordinator).
