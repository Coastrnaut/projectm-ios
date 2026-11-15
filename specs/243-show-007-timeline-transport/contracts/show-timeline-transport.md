# Contract: Show timeline transport (SHOW-007)

- **T1 Timeline.** Skipped cues have no span; the timeline ends at the first untimed cue; `time(ofCue:elapsed:)` and
  `locate` are inverse for every entry with a span.
- **T2 Seek.** `seek(to: t)` with destination ≠ active cue: exactly one `applyScene`, one transition drive (a cut),
  one `cueStarted`, zero announcements, zero quantized steps; countdown = remaining at t. Destination = active cue:
  zero applies; countdown moved. Same t again: zero events.
- **T3 Scrub.** `begin`, any number of `move`, `end` → one seek of the last moved time; `cancel` → none.
- **T4 Quantized.** A waiting quantized step is withdrawn by a seek and never fires afterwards.
- **T5 Loop.** Loop on, timeline without open end: after the last cue's dwell the first timeline cue applies once
  (one wrap per pass). Loop off: SHOW-002 unchanged. Open end: Loop unavailable.
- **T6 Play/Pause.** Pause = Hold on; Play = Hold off; remaining time kept; Play at Standby seeks to 0.
- **T7 UI.** `showTimelineRow` with `showTimelinePlay` (label "Play"/"Pause"), `showTimelineScrub` (adjustable,
  5 s), `showTimelinePosition` text, `showTimelineLoop` (toggle, value On/Off).
