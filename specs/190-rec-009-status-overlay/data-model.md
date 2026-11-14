# Data Model: REC-009 Recording status overlay

All values live in memory for the current recording only (REC-009-R7).

## RecordingStatusSummary (FrameRecording, pure)

| Field | Type | Rule |
|---|---|---|
| droppedSlots | Int | REC-006 live count |
| writtenFrames | Int | frames appended |
| droppedWarning | Bool | `dropped ≥ 10 && dropped × 50 ≥ written + dropped` (D2) |
| availableBytes | Int64? | latest REC-015 reading; nil = unknown |
| secondsLeft | Int64? | (available − stop threshold) ÷ max(estimate, measured), ≥ 0; nil when unknown |
| storageLevel | `RecordingStorageLevel?` | `.ok`, `.low` (< 300 s), `.critical` (< 60 s); nil when unknown |
| droppedText | String | "Dropped frames: 3" / "Dropping frames: 12 (3%)" |
| storageText | String | "2.1 GB free, about 14 min left" / "850 MB free, under 1 min left" / "Free storage unknown" |

## RecordingWarningThrottle (FrameRecording, pure)

Per `RecordingWarningKind` (`.droppedFrames`, `.storage`): last announced level (0 none, 1 warning/low, 2 critical) and the recorded seconds of the last announcement. `submit(kind, level, at:) -> Bool` (announce now?). Reset per recording.

## State on the coordinator (app)

- `statusSummary: RecordingStatusSummary?` (observable; nil unless recording).
- `statusWarning: RecordingStatusWarning?` (observable, with a sequence number so equal texts post again).
- Private: last storage reading, throttle.
