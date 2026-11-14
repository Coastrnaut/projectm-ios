# Contract: REC-009 Recording status overlay

## C1: Lines (device screen only)

| Identifier | Shown | Text | VoiceOver label |
|---|---|---|---|
| `recordingIndicator` (existing) | recording, finishing | "REC 0:07" / "0:07 / 0:10" | unchanged |
| `recordingDroppedFrames` | recording | "Dropped frames: 3"; warning "Dropping frames: 12 (3%)" with `exclamationmark.triangle` | the text; "Warning: " prefix when warned |
| `recordingStorageStatus` | recording | "2.1 GB free, about 14 min left"; "850 MB free, under 1 min left"; "Free storage unknown" (low/critical with `exclamationmark.triangle`) | the text; "Warning: " prefix when low or critical |

No animation; no colour-only signal.

## C2: Status rows (recording lane, cause system, persistent)

| ID | When | Visible / announced |
|---|---|---|
| X9f | dropped warning first reached (throttled) | "Recording is dropping frames" |
| X9g | storage low reached (throttled) | "Storage low: about 3 min of recording left" |
| X9g | storage critical reached (throttled) | "Storage almost full: under 1 min of recording left" |

Throttle: rising levels only, ≥ 30 s of recorded time between two announcements of one kind.

## C3: Exclusion

No app UI is ever drawn into a recording; there is no option to include it. Test:
`RecordingStatusOverlayAppTests.testOverlayIsNeverInTheRecording`.
