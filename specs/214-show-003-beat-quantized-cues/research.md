# Research: SHOW-003 Beat-Quantized Cue Advance

- **SHOW-003-D1 — Model**: a single-slot `QuantizedCueStep` in PerformanceControl. *Rationale*: a cue step is one
  pending action, not a value per key; `QuantizedChangeQueue`'s cancel rule needs a "current value" that a step does
  not have, and its Cue mode makes no sense here. *Reused*: `QuantizeMode` (Off/Beat/Bar; Cue is treated as Off),
  `QuantizeImmediateReason.noTempo`, `TempoSnapshot.nextBoundary(after:beats:)`, the 4-beat bar from the anchor.
  *Alternatives*: `QuantizedChangeQueue<Slot, Request>` with a sentinel value (rejected: contrived cancel semantics).
- **SHOW-003-D2 — Where the gate sits**: inside `ShowCoordinator.next/previous/go(to:)`, so every caller (controls,
  keys, pad, MIDI notes and scene actions, scene switcher, editor Go) is quantized the same way without touching them.
  The boundary runs `stepNow`, the former `perform`. *Alternative*: quantize each caller (rejected: seven call sites,
  easy to miss one).
- **SHOW-003-D3 — Return value**: `ShowStepOutcome.queued` (new case; `moved` stays false). No exhaustive switch over
  the enum exists outside tests (audit grep). A request that would do nothing now (Next at the last cue, an unknown
  cue) is not queued: the gate checks with a copy of the list first and returns that outcome.
- **SHOW-003-D4 — Repeat and replace**: same request = cancel; different = replace, the deadline recomputed at the new
  request time (Clarifications). Timed requests (`timed: true`) only fill an empty slot.
- **SHOW-003-D5 — Wake-up**: one main-actor task sleeping until the deadline on the monotonic analysis clock
  (`MonotonicClock.nowNanoseconds`, the clock `TempoSnapshot` anchors use), as `ParameterQuantizer` does; an early
  wake-up applies nothing and reschedules. Unit tests turn wake-ups off and call `tick(at:)`.
- **SHOW-003-D6 — Boundary order**: `willStep(deadline)` runs MOD-017's `tick(at:)` before the step, so a parameter
  change due at the same beat applies first and the cue's scene then stands (deterministic regardless of which task
  wakes first).
- **SHOW-003-D7 — SHOW-002 interplay**: `ShowAutoAdvanceCoordinator.tick` calls `show.timedNext()`. `timeline.due`
  already returns once per due cue; while the step waits, the countdown shows 0 and the new cue's countdown starts
  when `stepNow` moves (the existing `cueStarted` hook).
- **SHOW-003-D8 — Announcements**: cue lane (ACC-004 `.cue`): "Cue queued for the next beat|bar", "Queued cue
  cancelled", "Cue changed now, no tempo". The step's own messages are unchanged.
