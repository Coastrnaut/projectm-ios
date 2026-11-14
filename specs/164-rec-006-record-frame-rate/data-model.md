# Data Model: REC-006 Record frame rate

## RecordingFrameRateChoice (FrameRecording, plain Swift)

| Case | Raw value (stored) | Rate |
|---|---|---|
| profileDefault | `profile` | the profile's (REC-005-R1) |
| fps24 | `24` | 24 |
| fps30 | `30` | 30 |
| fps60 | `60` | 60 |

- `supportedRates = [24, 30, 60]`; absent or unknown stored values read as `profileDefault`.

## RecordingRenderLimit

- `reason`: `lowPowerMode` | `thermal`; `maximumFramesPerSecond` (30).

## RecordingFrameRateUnavailableReason

- `displayLimit(maximum)`, `renderLimit(RecordingRenderLimit)`, `encoderLimit(maximum, width, height)`; `text` is shown and spoken.

## RecordingFrameRateAvailability

- `available` | `unavailable(reason)`.

## RecordingRecordPlan (result of resolution)

- `profileResolution`: REC-005's `RecordingProfileResolution` whose plan's settings carry the effective rate.
- `rateFallback`: `(rate, reason)?`; `notice`: profile notice and/or rate notice, nil without fallback.

## RecordingTimeline (rewritten, same API)

- `originNanoseconds`, `lastWrittenTick`, `nextDueTick` (= next free slot × interval), `writtenCount`.
- Private: `nextSlot`, `lastWrittenNanoseconds`, `lastOfferedNanoseconds`, `pending` (candidate tick, ns).
- `admit(t)`: `droppedNotIncreasing` (t ≤ last written frame's time, or before the origin) → slot m → `durationReached` (m × interval ≥ limit) → `skippedRate` (m < next slot, or deferred to a nearer predicted frame) → `candidate(tick: m × interval)`.

## RecordingStatistics (+)

- `droppedSlots`: empty slots between the first and last appended frame.

## RecordedVideo (+)

- `frameRate: Int` (nominal, the settings' rate); `droppedFrames: Int` (= `statistics.droppedSlots`).

## RecordedVideoInfo (+)

- `trackNominalFrameRate: Double`, `minFrameDurationTicks: Int64?`.

## App: RecordingQualitySetting (+)

- `frameRate: RecordingFrameRateChoice`, key `settings.recording.frameRate`, nothing stored until changed; `-uitestResetNotice` removes it; excluded from backup, erased with Settings, in `ALLOWED_KEYS`.

## App: VideoRecordingCoordinator (+)

- `Context.frameRateChoice`; `lastRecording: RecordedVideo?` (the last finished file's facts, including dropped frames and rate).
