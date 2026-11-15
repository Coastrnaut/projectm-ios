# Research: SHOW-013 Auto Scene Rotation

- **SHOW-013-D1 Seeded pick without immediate repeat.** Decision: candidates = enabled scenes of the collection in show
  order minus the current scene; index = ⌊`SteppedRandom.level(seed, step)` × count⌋ (clamped). Rationale: MOD-008's
  counter-based SplitMix64 is pure and the same on every platform, so a (seed, step) pair always gives the same pick; it is
  uniform over the others, like preset Random (never the current, uniform). Alternatives: a shuffle bag (no immediate
  repeat only within a bag; the bag boundary needs a special case and the order depends on stored state); a
  `SystemRandomNumberGenerator` draw (not reproducible, so not testable against the acceptance).
- **SHOW-013-D2 Bars on SHOW-011's grid.** Decision: the deadline is the Nth call of `nextBoundary(after:beats: 4)`
  starting from the arm time (strictly after each time), then further bar lines until the minimum gap (4 s; 15 s with
  Reduce flashing, the timer's own floor). No tempo with phase → the timer interval. Rationale: reuses the bar definition
  of SHOW-003 and MOD-017 (4/4 from the anchor) and needs no period arithmetic in ShowControl (the bar line is an injected
  closure). Alternative: start + N × 4 × period (ignores phase: not on the downbeat).
- **SHOW-013-D3 Show transport wins.** Decision: rotation holds while SHOW-002's driver shows an unheld countdown (a
  timed cue plays) and under SHOW-002's holds (pause, blackout, repair report, background, Hold); the interval restarts
  when the hold ends. Rationale: two automatic sources moving the same position would fight; the show timeline is the
  more specific plan. Keeping the remaining time across a hold was considered; restarting is simpler and never switches
  right after a pause ends.
- **SHOW-013-D4 One tick loop only while on.** Decision: like SHOW-002's driver, a main-actor task sleeps min(250 ms,
  time to deadline) and calls `tick()`; it exists only while rotation is on. Rationale: no work while off; holds are
  re-read on each tick. Tests set `runsLoop` false and call `tick()` with an injected clock.
- **SHOW-013-D5 UI-test hook.** Decision: DEBUG `-uitestSceneRotation <seconds>` turns rotation on at launch with that
  interval (bypassing the 15 s floor) and seed 1. Rationale: a UI test must finish under 30 s (owner rule 7); the
  argument is compiled out of Release.
