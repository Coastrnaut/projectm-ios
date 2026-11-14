# Research: REC-008 Timed recording stop

## REC-008-D1: Where the end is decided

- **Decision**: Reuse `RecordingSettings.maxDurationSeconds`: the coordinator sets it to min(length, 600) for the recording. The REC-006 timeline already answers `durationReached` for a frame whose slot tick m × I is at or beyond the limit, before the frame is encoded, so a frame at or after the end never reaches the writer and the file's last frame is slot (fps × length − 1).
- **Rationale**: Media time on the exact grid; no wall clock; one rule for the 10-minute limit and the timed stop.
- **Alternatives**: A wall-clock timer in the coordinator (rejected: stalls and the 0.25 s check granularity give extra or missing frames); a separate media limit (duplicate of the existing rule).

## REC-008-D2: Finishing without blocking the frame loop

- **Decision**: `MetalFrameRecorder.beginFinish()` sets `stopped` and creates the finish task under the recorder's lock and returns at once; the finish waits for the frames in flight through `DispatchGroup.notify` on the writer's queue, then calls the writer's async finish. The tap calls it on the frame path right after the audio pump of the frame that returned `durationReached`; the coordinator's `stop(.timedStop)` awaits the same task (`finish()` is idempotent).
- **Rationale**: The file starts closing on the frame that crossed the end, with no main-actor hop; nothing on the frame loop waits.
- **Alternatives**: Leave the finish to the coordinator's `Task` (works, but the writer keeps taking audio until then and the finish start depends on main-actor scheduling).
- **Spy**: The writer protocol (`RecordingSampleSink`) is wrapped in tests by a sink that records the thread of each `finish` call and whether any `append` or `finish` ran on the frame-loop thread; the test asserts `recordFrame` and `beginFinish` return before `finish` begins (a gate the test holds closed) and that no frame call waited.

## REC-008-D3: Audio end

- **Decision**: `RecordingAudioTimeline.limitSample` (nil = none) = round(length × 44,100); `place` cuts a chunk so it ends at or before the limit and places nothing at or after it. The recorder sets it from `settings.maxDurationSeconds`.
- **Rationale**: Audio never outlasts the video; a straddling chunk keeps its part before the end, so audio ends at the end when it was offered.
- **Alternatives**: Trim at finish with `endSession` only (the file's track would still contain samples past the end in its edit list).

## REC-008-D4: Lengths and setting

- **Decision**: Off, 10, 30, 60, 300 s; key `settings.recording.timedStop`, raw values `off`, `10`, `30`, `60`, `300`. DEBUG launch argument `-uitestTimedStop <raw>` sets the value for UI tests.
- **Rationale**: All divide every recording rate exactly; under the 10-minute limit.

## REC-008-D5: Stop reason and notice

- **Decision**: New `RecordingStopReason.timedStop` with the generic notice "Recording stopped at the set length."; the coordinator shows the specific text "Recording stopped after 10 seconds." (`RecordingTimedStopLength.stoppedNotice`). `StatusEventCatalog.recordingNotice` classifies the prefix "Recording stopped after " as X13.
- **Rationale**: Follows REC-007's pattern of texts in the app catalog; the package stays free of app lengths.
