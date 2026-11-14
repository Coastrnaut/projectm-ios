# Research: SHOW-007 Timeline Transport

- **SHOW-007-D1 — Timeline from dwells, no lanes.** Decision: derive the timeline from SHOW-002 dwells of non-skipped
  cues, ending at the first untimed cue. Rationale: the only scheduled values are cue scenes at cue starts; lanes
  would be a new data model with no user story. Rejected: automation lanes; treating untimed cues as 0 s (they would
  be unreachable by scrubbing yet still "on" the timeline).
- **SHOW-007-D2 — Seek plan, not replay.** Decision: a seek computes its destination and applies only that cue
  (`.apply`), or only moves the countdown inside the active cue (`.reposition`), or does nothing when the countdown
  already matches (`.none`). Rationale: replaying the cues in between would fire every intermediate apply,
  announcement and output (the duplicates the acceptance forbids). Rejected: stepping Next repeatedly.
- **SHOW-007-D3 — Scrub coalescing.** Decision: during a drag only a preview time is held; release commits one seek.
  VoiceOver swipes are single seeks. Rejected: seeking on every slider change (dozens of applies per drag).
- **SHOW-007-D4 — Playhead from the advance timeline.** Decision: reuse `ShowAdvanceTimeline` as a second instance
  that always counts down the active timed cue (even the last one) with the same holds; elapsed = dwell − remaining.
  Rationale: one tested hold/remaining model; SHOW-002's countdown semantics stay unchanged. Rejected: a separate
  wall-clock anchor (duplicate hold logic).
- **SHOW-007-D5 — Seek lands as a cut, not quantized.** Decision: the seek path forces a nil transition (a cut;
  `CueTransitionResolver` still widens it under Reduce flashing) and withdraws any waiting quantized step. Rationale:
  "lands on the target state", and nothing scheduled before the seek fires after it. Rejected: the cue's own
  transition (a 5 s fade after a scrub reads as lag); quantizing the seek (a scrub would wait a bar).
- **SHOW-007-D6 — Pause is Hold.** Decision: Play/Pause drive SHOW-005's Hold. Rationale: one hold state the performer
  can see in both places. Rejected: a second hold source (two toggles that both freeze the show).
- **SHOW-007-D7 — Loop through the timed path.** Decision: with Loop, the last timeline cue arms a countdown whose
  due advance calls `timedGo(first)` (quantized like SHOW-002's advance); one wrap per due time. Loop is stored on the
  device (`settings.show.loop`), excluded from backup like SHOW-003's quantize mode.
