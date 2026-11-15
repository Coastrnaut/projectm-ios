# Contract: MED-012 Countdown Overlay

- **C1 Format**: `CountdownFormat.string(seconds:)`: 0 → "00:00", 59 → "00:59", 300 → "05:00",
  3,599 → "59:59", 3,600 → "1:00:00", 5,940 → "1:39:00". Negative input → "00:00".
- **C2 Timer**: `remaining(at:)` is never negative; `displayedSeconds(at:)` = ceil(remaining);
  `advance(at:)` returns true exactly once per run; Reset re-arms.
- **C3 Layer**: the coordinator pushes a spec only when the string changes; while running that is at
  most once per shown second, and after zero never.
- **C4 Scene**: `SceneDocument.countdownSeconds` reads and writes `extra["countdown"]`; a scene
  round trip keeps it; a show cue applying a scene with it restarts the countdown with that duration.
- **C5 Probe (DEBUG)**: `countdownProbe` value "<text|none> <idle|running|paused|finished> finished=<n> drawn=<frames>".
