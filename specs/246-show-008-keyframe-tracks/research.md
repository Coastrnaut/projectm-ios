# Research: SHOW-008 Keyframe Tracks

- **SHOW-008-D1 — Exact samples by construction.** Decision: a keyframe time returns the stored value object itself;
  between keys the fraction `u = (t − t0) / (t1 − t0)` uses integer nanoseconds of that segment only, and the value is
  `a + (b − a) · f(u)`. Rationale: no running accumulator, so no drift; a key is never recomputed from a formula.
  Rejected: evaluating `a + (b − a) · 1` at the end key (rounding can differ from `b`); a global normalized time.
- **SHOW-008-D2 — Colours in linear light.** Decision: keys store sRGB (as designers and UIX-011 palettes specify
  them); between keys each channel is decoded with the IEC 61966-2-1 transfer, mixed, and encoded back; alpha mixes
  linearly. Rationale: the same light model as VIS-001's palettes. Rejected: mixing sRGB codes (muddy midpoints).
- **SHOW-008-D3 — Stored in the show, lenient.** Decision: optional `tracks` in `show.json`, written only when
  non-empty; a bad track or keyframe is dropped with a counted warning. Rationale: the SHOW-002/004/005 pattern; old
  shows keep their bytes. Rejected: a separate file (two files to keep in step); a version bump.
- **SHOW-008-D4 — A live layer, not scene writes.** Decision: tracks produce a value map applied like MIDI-003/OSC-003
  live values (under them), then MOD-002 and ACC-012's clamp. Rationale: the scene and settings stay what the performer
  saved; turning tracks off or leaving the timeline restores manual values. Rejected: writing settings each frame
  (scene autosave, history and undo would record animation).
- **SHOW-008-D5 — Sampling.** Decision: a main-actor loop at 1/60 s while playing with tracks, 4 Hz otherwise, plus
  immediate samples after a seek or step; apply only on change. Rationale: smooth ramps, idle cost near zero, and a
  seek's value lands exactly once. Rejected: sampling only on the driver's 250 ms tick (visible steps in a ramp).
- **SHOW-008-D6 — Targets.** Decision: the four glow parameters (the only registry parameters the live path applies
  per frame) and Visual Colour (a one-colour palette). Rationale: tracks must visibly drive something without
  widening the registry or the engine. Rejected: every registry parameter (most rebuild generators when changed).
