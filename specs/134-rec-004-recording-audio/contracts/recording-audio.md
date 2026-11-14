# Contract: recording audio (REC-004)

## C1 Policy (FrameRecording)

`RecordingAudioPolicy.decide(source: RecordingAudioSourceKind?, includeMicrophone: Bool, microphoneGranted: Bool) -> RecordingAudioDecision`

- `.inAppPlayback` → `.include(.appAudio)` regardless of the microphone values.
- `.systemCapture` → `.exclude(.otherAppsAudio)` regardless of every other value (REC-004-R2).
- `.microphone` → `.exclude(.microphonePermissionMissing)` unless granted; else `.exclude(.microphoneSettingOff)` unless the setting is on; else `.include(.microphone)`.
- nil → `.exclude(.noSource)`.

## C2 Recording tap (AudioCore)

- `NormalizedPCMRing.armRecordingTap()`: drains the tap, zeroes the stamp, arms it. Control side.
- `disarmRecordingTap()`: disarms and drains. Also done by `reset()` and `resetForHandoff()` before their first new-session write.
- Producer: every ring write also goes to the tap only while armed, then stores the stamp (frames since arming, uptime ns).
- `recordingTap: any RecordingTapReading` (one consumer: the recording's feed). `read(into:maxFrames:)` drains up to `maxFrames` and returns `RecordingTapChunk(frames:firstSampleNanoseconds:)`; 0 frames when empty or disarmed. Never blocks, never allocates.
- `CaptureManager.recordingTap` exposes it (nonisolated).

## C3 Recorder (FrameRecording)

- `MetalFrameRecorder.init(device:url:drawableWidth:drawableHeight:settings:realTime:fault:audio:)`; `audio` defaults to false (REC-003 behavior unchanged: no audio track).
- `appendAudio(_ samples: UnsafePointer<Float>, frames: Int, firstSampleNanoseconds: UInt64)`: interleaved stereo 44.1 kHz. Ignored when the recorder has no audio track, after `endAudio()`, after finish, or before the first video frame. Copies the samples, places them (`RecordingAudioTimeline`), appends on the writer queue. Never waits on the caller's thread.
- `endAudio()`: idempotent; no audio is placed afterwards; the audio input is marked finished at the file's finish.
- The file has an audio track iff the recorder was made with `audio: true` and at least one chunk was appended. A recorder with `audio: true` that received no audio writes no audio samples; AVFoundation omits an empty track.

## C4 App

- `RecordingAudioSetting.includeMicrophone` (key `settings.recording.includeMicrophone`, default false).
- `VideoRecordingCoordinator`: at Record, `decision = RecordingAudioPolicy.decide(…)` from the context (source mode, microphone permission, setting); `audio: decision.includesAudio`; arms the tap only then. Per frame (the tap's `record`), after the frame, drains the tap into the recorder. The 0.25 s check ends the audio when the mode differs from the recording's, the tap is disarmed, or (microphone) the setting is off; the end disarms the tap, calls `endAudio()`, sets `audioEnded`, posts the "audio ended" status event once.
- `audioStatusText`: while recording, the recording's decision text or "Recording audio ended."; otherwise the decision the context would give now (the Record hint, Settings).
- Status events: start of a recording with its audio status; audio ended early. Kind `.recording`, cause `.user` at start and `.system` for the early end.
- UI: Settings → "Recording" section: toggle "Include microphone audio" (`recordingMicrophoneToggle`), footer, and the current audio status (`recordingAudioStatus`). Under the recording indicator: `recordingAudioLine`. Record control hint: the audio status.

## C5 Tolerance

A sound and a video frame stamped at the same host time are at most 20 ms apart in the written file (fixture, REC-004-S1).
