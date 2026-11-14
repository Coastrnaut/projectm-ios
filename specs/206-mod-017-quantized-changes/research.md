# Research: MOD-017 Quantized Parameter Changes

- **MOD-017-D1 Reuse SHOW-011's grid.** Decision: boundaries come from `TempoSnapshot` (period, anchor) with a new
  `nextBoundary(after:beats:)` that is strictly after the request (beats = 1 for Beat, 4 for Bar). Rationale:
  SHOW-011 is the one tempo every consumer reads (manual tap first, else ANL-005 at confidence ≥ 0.5); SHOW-003
  is not integrated, so there is no other boundary logic to reuse. Alternatives: subscribing to ANL-005 beat
  events directly (rejected: bypasses tap tempo and the confidence floor; SHOW-011-R10 forbids it).
- **MOD-017-D2 Deadline fixed at request.** Decision: the boundary time is computed once per request. Rationale:
  bounded wait (≤ one bar), and a re-anchoring estimate cannot postpone a change forever or apply it twice.
  Alternatives: re-evaluating against each new snapshot (rejected: an anchor that moves backwards could re-arm).
- **MOD-017-D3 No tempo → immediate.** Decision: no phase (no tempo, or an estimate without a beat time) applies at
  once, announced. Alternatives: timeout of one second (rejected: unrelated to the music, still surprising).
- **MOD-017-D4 Exactly once by removal.** Decision: `takeDue(at:)` removes and returns every entry whose deadline
  ≤ now; `cueStepped()` removes all entries. An entry exists at most once per key, so it cannot apply twice.
- **MOD-017-D5 Cancel by returning to the current value.** Decision: a request equal to the current value removes
  the queued entry (a toggle tapped twice before the beat does nothing). The quantized target's `get` returns the
  pending value, so the control shows what will happen.
- **MOD-017-D6 App scheduling.** Decision: one main-actor task sleeps until `nextDeadline` (monotonic clock) and
  then calls `tick()`; rescheduled after every queue change; none while empty. Tests disable it and call
  `tick(at:)` with injected times. Alternatives: polling with TempoCoordinator's 250 ms poll (rejected: up to 250
  ms late, a quarter of a beat at 60 BPM).
- **MOD-017-D7 Lock at apply time.** Decision: the apply path is SCN-015's guarded target; a lock at the boundary
  refuses (and announces) and the entry is dropped, never retried.
- **MOD-017-D8 Scope of quantization.** Decision: discrete = boolean, enumeration, integer, or a target with fixed
  `choices`; only `quantizedTarget` callers (inspector, shelf, macros) are quantized.
