# Research: SHOW-010 Beat Grid

- **SHOW-010-D1 Integer grid.** Decision: beats are `anchor + k × period` in `Int64` nanoseconds; k comes from floor
  division, so windows before the anchor work and no float step accumulates. Rationale: the acceptance asks for ticks
  "every half second", which at 120 BPM is exactly 500,000,000 ns (SHOW-011 rounds the period to whole ns). Alternative:
  `Double` seconds stepping — drifts and makes equality tests fragile.
- **SHOW-010-D2 Bound and decimation.** Decision: at most 512 ticks; strides 1, 4, 8, 16 … beats (bars stay bars); the
  layout uses the smallest stride with ≥ 4 points between drawn ticks, and `ticks` raises the stride further if the
  count still exceeds 512. Rationale: a 256 h timeline at 300 BPM would be millions of beats. Alternative: clipping
  the list (shows only the start of the timeline).
- **SHOW-010-D3 Numbering and texts.** Decision: bars are 4/4 from the anchor (as SHOW-003 and MOD-017 quantize), and
  numbered so that 0:00 lies in bar 1. Texts: "Bar 3 · Beat 2 · 120 BPM", VoiceOver "120 BPM, tap tempo, bar 3
  beat 2", "detected" for an estimate, "No tempo" without one; without a position (Standby) only the tempo.
- **SHOW-010-D4 Placement.** Decision: the snapshot's anchor is on the monotonic analysis clock and the timeline on the
  show driver's clock; both are monotonic, so the placement uses differences only: `timelineNow − (tempoNow − anchor)`
  modulo the period, recomputed on each read while playing, kept while paused/Standby, 0 before any placement or
  without an anchor. Alternatives: always 0:00 (ignores the tap phase); mapping while paused (the grid would slide
  while the music continues and the show is frozen).
- **SHOW-010-D5 UI testing.** Decision: ticks are decorative (`accessibilityHidden`), so the UI test reads a DEBUG
  probe enabled only by `-uitestBeatGridProbe`, plus the real readout element. The tempo is seeded with ANL-006's
  `-uitestTempoEstimate 120:0.9` (an estimate without beat time: grid from 0:00).
- **SHOW-010-D6 No snapping.** Decision: not in this row (spec Clarifications); `nearestBeat` is offered by the model.
