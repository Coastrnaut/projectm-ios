# Contract: REC-008 Timed recording stop

## C1: The exact end (FrameRecording)

- With `settings.maxDurationSeconds = L` and rate f, the written frames are exactly those on slots 0 … f·L − 1 that were admitted; a frame on slot ≥ f·L returns `durationReached` and is never encoded or appended.
- The file's duration is (last written slot + 1) / f; with every slot filled it is exactly L.
- Audio: nothing at or after sample round(L × 44,100) is placed; a straddling chunk is cut.

## C2: Non-blocking finish

- `recordFrame` never waits; `beginFinish()` never waits (it creates the finish task under the lock).
- After `beginFinish()`, `recordFrame` returns `.finished` and `appendAudio` is ignored.
- `finish()` after `beginFinish()` returns the same result.
- The frame tap calls `audioFeed.pump()` then `recorder.beginFinish()` on a `durationReached` outcome, then reports the stop to the main actor in a `Task`.

## C3: App

- Settings section "Stop recording after", rows Off, 10 seconds, 30 seconds, 1 minute, 5 minutes; identifiers `recordingTimedStop.<raw>`; checkmark on the selected row.
- Indicator while recording with a length: "0:07 / 0:10"; accessibility value "0:07 of 0:10".
- Timed stop: `lastStopReason == .timedStop`, notice "Recording stopped after 10 seconds." (X13, recording lane, cause system); the file is offered (or, with `-uitestRecordingDirectory`, moved and probed).
- Manual and automatic stops before the end keep their own reasons and notices.
- The length is fixed when the recording starts.
