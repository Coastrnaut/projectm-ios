# Data Model: REC-004 Recording audio mux

## RecordingAudioSourceKind (FrameRecording, plain Swift)

`inAppPlayback`, `microphone`, `systemCapture`. The app maps `AudioSourceMode` to it; no source → nil.

## RecordingAudioDecision

| Case | Includes audio | Status text |
|---|---|---|
| `include(.appAudio)` | yes | "Recording includes app audio." |
| `include(.microphone)` | yes | "Recording includes microphone audio." |
| `exclude(.otherAppsAudio)` | no | "Recording has no audio: other apps' audio is never recorded." |
| `exclude(.microphoneSettingOff)` | no | "Recording has no audio: Include microphone audio is off." |
| `exclude(.microphonePermissionMissing)` | no | "Recording has no audio: microphone permission is off." |
| `exclude(.noSource)` | no | "Recording has no audio." |

`RecordingAudioPolicy.decide(source:includeMicrophone:microphoneGranted:)`:
inAppPlayback → app audio; systemCapture → other apps' audio; microphone → permission missing
(checked first), then setting off, else microphone; nil → no source.

Early end text: "Recording audio ended." (announced once; the line under the indicator shows it).

## RecordingAudioTimeline (plain Swift)

| Field | Meaning |
|---|---|
| `sampleRate` | 44,100 |
| `contiguityWindowSamples` | 4,410 (100 ms) |
| `originNanoseconds` | the first video frame's time (set once) |
| `nextSample` | the position after the last placed sample (nil before the first) |
| `ended` | true after `end()`; nothing more is placed |

`place(frames:firstSampleNanoseconds:) -> Placement?` with `Placement(skipFrames, startSample, frames)`.
Rules in order: ended or no origin → nil; position = round((t − origin) × 44,100 / 1e9); within the
window of `nextSample` → `nextSample`; earlier than `nextSample` beyond the window → trim the overlap;
negative → trim to 0; nothing left → nil.

## Recording tap (AudioCore)

| Element | Meaning |
|---|---|
| ring | SPSC, 22,050 stereo frames, drop-oldest |
| armed | atomic Bool; producer writes only while true |
| stamp | `Atomic<WordPair>`: frames written since arming, uptime ns of the latest write |
| `RecordingTapChunk` | `frames`, `firstSampleNanoseconds` |
| `RecordingTapReading` | `read(into:maxFrames:) -> RecordingTapChunk`, `isArmed`, `droppedFrames` |

Transitions: disarmed → `armRecordingTap()` (drain, stamp 0, armed) → `disarmRecordingTap()`,
`reset()` or `resetForHandoff()` → disarmed (drained).

## Recording audio setting (app)

Key `settings.recording.includeMicrophone`, Bool, default false (absent or not a Bool → false).
Left out of the library backup (`LibrarySettingsPolicy.excludedKeys`), erased with the Settings
category (device switch), removed by `-uitestResetNotice`, listed in `ALLOWED_KEYS`.

## Recorder additions (FrameRecording)

- `MetalFrameRecorder(…, audio: Bool)`: the writer gets an AAC input only when true.
- `appendAudio(_:frames:firstSampleNanoseconds:)`, `endAudio()`, `hasAudioTrack`.
- `RecordingStatistics.audioFramesWritten`, `audioFramesDropped`.
- `RecordedVideoInfo.audioCodec` ("aac " or nil), `audioSampleRate`, `audioChannelCount`.
