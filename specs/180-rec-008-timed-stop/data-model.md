# Data Model: REC-008 Timed recording stop

## RecordingTimedStopLength (app)

| Case | Raw | Seconds | Title | Stopped notice |
|---|---|---|---|---|
| off | `off` | 0 | Off | — |
| ten | `10` | 10 | 10 seconds | Recording stopped after 10 seconds. |
| thirty | `30` | 30 | 30 seconds | Recording stopped after 30 seconds. |
| oneMinute | `60` | 60 | 1 minute | Recording stopped after 1 minute. |
| fiveMinutes | `300` | 300 | 5 minutes | Recording stopped after 5 minutes. |

Default: off. Absent or unknown stored value → off.

## RecordingTimedStopSetting (app)

- `length: RecordingTimedStopLength`, stored on change under `settings.recording.timedStop`.
- `-uitestResetNotice` removes the key; DEBUG `-uitestTimedStop <raw>` sets it at launch.

## VideoRecordingCoordinator additions

- `Context.timedStop: RecordingTimedStopLength` (default off).
- `recordingLength: RecordingTimedStopLength?` — fixed at start for the running recording (R10).
- Indicator text: `elapsedText` + " / " + length text when set.
- `durationReached` with a set length → stop reason `timedStop`, notice = the length's stopped notice.

## FrameRecording additions

- `RecordingAudioTimeline.limitSample: Int64?` — nothing placed at or after it.
- `MetalFrameRecorder.beginFinish()` — starts the finish task, returns at once (idempotent with `finish()`).
- `RecordingStopReason.timedStop`.
