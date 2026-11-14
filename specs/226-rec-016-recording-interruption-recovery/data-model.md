# Data Model: REC-016

- **RecordingWriterFault** (public, Sendable): `kind` (`appendFails` | `writerFails` | `finishFails` | `startFails`), `afterFrames` (≥ 0), `error` (NSError). Factories: `diskFull(afterFrames:)` (append kind, out-of-space error; REC-015), `appendFailure(afterFrames:)`, `writerFailure(afterFrames:)`, `finishFailure`, `startFailure`.
- **RecordingSalvageOutcome** (public enum): `finished` (healthy writer finished early), `partial` (completed fragments kept), `nothing` (deleted).
- **RecordedVideo.interruption** (`RecordingFailure?`, default nil): set when the file was kept after a writer failure; frames and duration then come from the read-back.
- **RecordingSettings.fragmentIntervalSeconds** (`Double`, default 1.0, clamped ≥ 0.1).
- **RecordingStopReason.thermal** — notice "Recording stopped because the device is too hot."
- **RecordingStopReason.writerFailed** — notice changes to "Recording stopped because of a write error. The part recorded before it was kept." (used only when a part was kept; a failure without a kept part keeps the failure notice).
- **RecordingRefusal.thermal** — notice "The device is too hot to record. Try again when it cools down."
- **RecordingThermalLevel** (`nominal`, `fair`, `serious`, `critical`; Comparable) and **RecordingThermalGuard** (`warned: Bool`; `update(_:) -> RecordingThermalAction` = `none` | `warn` | `stop`); `warningNotice` "The device is getting hot. Recording stops if it gets hotter."
- **RecordingResourceLedger** (Apple-only): `liveRecorders`, `liveWriters` (Int, read any thread).
