# Data Model: AUD-013 Source Latency Calibration

## Visual delay setting (app, `LatencyOffsetSetting`)

| Field | Type | Rule |
|---|---|---|
| `milliseconds[mode]` | Double per `AudioSourceMode` | whole ms, 0…250, default 0; NaN or non-number → 0; clamped |
| `activeMode` | `AudioSourceMode?` | set by the coordinator on session start, switch and stop |
| keys | `settings.latencyOffset.microphone`, `.inAppPlayback`, `.systemAppCapture` | Double; cleared by `-uitestResetNotice` |

Transitions: editing the active mode's value or changing `activeMode` writes
`LatencyOffset.frames(milliseconds:)` of the active value (0 with no mode) into the control.

## Delay control (AudioCore, `LatencyOffsetControl`)

| Field | Type | Rule |
|---|---|---|
| `targetFrames` | Int (atomic, relaxed) | 0…11,025 (clamped on write) |

## Delay reader (AudioCore, `LatencyDelayReader`)

| Field | Owner | Rule |
|---|---|---|
| line | reader thread | 33,075 stereo frames, allocated in `init` |
| `bufferedFrames` | reader thread | 0…capacity |
| `appliedDelayFrames` | reader thread | moves toward the target by ≤ ⌈pulled / 4⌉ per read |
| `droppedFrames` | atomic | overflow drops + renderer excess trims |
| `mode` | immutable | `.analysis` (flush on generation change) or `.renderer` (keep, trim excess beyond applied + 2,205) |
| generation | reader thread | last seen session generation (analysis only) |

States: **pass-through** (target = applied = 0, buffered = 0: forwards the read) ↔ **delaying**.

## Latency estimate (AudioCore, `LatencyOffset.estimateMilliseconds`)

Input: mode, output latency (s), I/O buffer duration (s). Output: whole ms in 0…250.
