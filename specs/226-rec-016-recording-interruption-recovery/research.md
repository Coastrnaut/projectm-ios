# Research: REC-016 Recording interruption recovery

## REC-016-D1 Fragmented MP4 vs segment rotation

Experiment on the Mac Studio (2026-11-14, macOS AVFoundation, H.264 64×48, 45 frames at 30 fps,
then a duplicate timestamp to drive the writer to `.failed`, error -11800/-16364):

| Writer | After the failure |
|---|---|
| plain MP4 | file of 1 349 bytes, no movie header: no track, 0 frames readable |
| `movieFragmentInterval` 0.5 s | file of 2 398 bytes: `ftyp mdat moov mdat moof …`; 30 of 45 frames readable, duration 1.0 s |
| fragmented, normal finish | `ftyp mdat moov` only: AVAssetWriter defragments at finish, 45 frames, 1.5 s |
| fragmented, `cancelWriting` | file deleted |

Decision: fragments (1 s). A normally finished file is an ordinary MP4, so nothing downstream
(Photos, share, QA-008) sees a difference. Rotation was rejected (several files per recording, join
step, more UI). Rationale for 1 s in spec Clarifications.

## REC-016-D2 Salvage by writer state

- Writer still `.writing` (the append failed at our level, e.g. an injected append failure): finish it
  normally at the last appended frame + one interval → a complete file.
- Writer `.failed`: never call `cancelWriting` (it deletes the file); keep the file as it is and read
  it back.
- Out of storage: keep REC-015-R7 (delete).
- Usable = `RecordedVideoInspector.inspect` returns a video with ≥ 2 frames; else delete.

## REC-016-D3 Injecting a real writer failure

A duplicate presentation time on the real `AVAssetWriterInput` turns the writer `.failed`
asynchronously (observed within 300 ms). The fault sink does this on the writer queue and waits (test
and DEBUG only, ≤ 2 s) for the status, so "writer failure" and "finish failure" exercise AVFoundation's
own failed state, not a double.

## REC-016-D4 Start failure leak

`MetalFrameRecorder.init` creates the writer before the texture cache; a throw after that left a
started writer and its file. Fix: on any throw after the writer exists, cancel it (deletes the file).

## REC-016-D5 Release proof

`RecordingResourceLedger` (Apple-only, `Mutex`) counts live `MetalFrameRecorder` and `VideoFileWriter`
instances (the writer owns the pixel-buffer pool). After the end the recorder also flushes its texture
cache. Tests compare counts to the baseline taken before the recording.

## REC-016-D6 Thermal

`ProcessInfo.thermalState` is mapped to `RecordingThermalLevel`; `RecordingThermalGuard` (plain Swift)
returns warn once at Serious and stop at Critical. Lowering quality mid-file is impossible (fixed
writer settings), so stopping is the graceful option at Critical.
