# Data Model: ProjectM-iOS Visualizer

All entities are in-memory unless marked **persisted**. Persisted data is limited to FR-065.
Field types are logical (Swift types noted where useful).

## AudioSourceMode (enum)

`systemAppCapture` · `microphone` · `inAppPlayback`

| Mode | Display label (FR-013) | Availability rule |
|------|------------------------|-------------------|
| systemAppCapture | "System/App Capture" | OS ≥ first capture-capable version (FR-008) **and** runtime probe succeeds |
| microphone | "Microphone" | Always listed; may fail with `microphoneUnavailable` / `permissionDenied` |
| inAppPlayback | "In-App Playback" | Always listed; fails with `inAppPlaybackFailed` if the track cannot play |

## AudioSource

| Field | Type | Rules |
|-------|------|-------|
| mode | AudioSourceMode | immutable |
| availability | `.available` / `.unavailable(reason)` | `unsupportedOS` for capture on iOS 26 (FR-004) |
| state | AudioState | see the state machine below |
| stopReason | StopReason? | set when state ∈ {Stopped, Ended by system, Interrupted} or a failure occurs |
| contentIdentity | String? | System/App Capture only. Set **only** if the OS identifies the content **and** Active audio was verified this session (FR-014); else nil |

Invariant: at most one AudioSource is started at a time (FR-001). Switching = stop(old) completes
before start(new) (FR-016).

## AudioState (enum, FR-010)

`notStarted` · `waiting` · `noAudioReceived` · `silent` · `active` · `paused` · `interrupted` ·
`stopped` · `endedBySystem`

UI strings: "Not started", "Waiting", "No audio received", "Audio received — silent", "Active
audio", "Paused", "Interrupted", "Stopped", "Ended by system". `active` is the only state that may
be described as receiving audio.

### Transitions

```text
notStarted ──start ok──▶ waiting
notStarted ──start fails──▶ notStarted (+ StopReason: cancelled / permissionDenied /
                                         microphoneUnavailable / inAppPlaybackFailed / error)
waiting ──no data for 5 s──▶ noAudioReceived                       (FR-012)
active|silent ──no data for 5 s──▶ noAudioReceived                 (a source that stops delivering
                                                                    is never left showing Active)
waiting|noAudioReceived|silent ──peak ≥ −50 dBFS for ≥ 250 ms──▶ active   (FR-011)
waiting|noAudioReceived ──data arrives, below active threshold──▶ silent
active ──peak < −60 dBFS for ≥ 2 s──▶ silent                       (FR-011)
silent for 60 s ──▶ silent + prolongedSilenceHint = true           (FR-018, no state change)
any running ──app background / device lock (mic, in-app)──▶ paused (source suspended; FR-050, FR-054)
paused ──foreground, permission + route OK──▶ waiting (auto-resume ≤ 2 s)
any running ──OS interruption──▶ interrupted                       (FR-051)
interrupted ──OS says may resume──▶ waiting (auto-resume, mic/in-app)
any running ──OS ends capture session──▶ endedBySystem             (US6-AS3)
any running ──route lost (in-app)──▶ paused (StopReason.audioRouteChanged)
any ──user stop──▶ stopped (≤ 1 s, FR-007)
```

Format changes (FR-017) do not cause a transition; they update `AudioFormat` only.
User pause of the **visualization** (FR-046) is not an AudioState transition; it changes
`VisualizationState` only.

### Lifecycle matrix (per adapter)

| Event | System/App Capture | Microphone | In-App Playback |
|-------|--------------------|------------|-----------------|
| Start | system picker → waiting | explainer → permission → waiting | waiting |
| User stop | stopped (≤ 1 s) | stopped (≤ 1 s) | stopped (≤ 1 s) |
| Background / lock | continues if the stream delivers, else endedBySystem (RI-003) | paused (engine stopped) | paused (playback paused) |
| Foreground | as above | auto-resume ≤ 2 s or reason | auto-resume ≤ 2 s or reason |
| Interruption | no change while the stream delivers; endedBySystem if it stops | interrupted → auto-resume or one-tap restart | interrupted → auto-resume or one-tap restart |
| Route change | not applicable (no app output) | continue on new input, or stopReason microphoneUnavailable | output lost → paused (audioRouteChanged) |
| OS ends session | endedBySystem | not applicable | not applicable |
| One-tap restart | re-presents system picker (FR-055) | restarts engine | restarts playback |

## VisualizationState (enum)

`running` · `paused` (user, FR-046) · `suspended` (app backgrounded, FR-050). Independent of
AudioState.

## StopReason (enum, FR-015)

`cancelled` · `permissionDenied` · `microphoneUnavailable` · `inAppPlaybackFailed` · `interrupted`
· `audioRouteChanged` · `endedBySystem` · `unsupportedOS` · `error(description)`

## AudioFormat

| Field | Type | Rules |
|-------|------|-------|
| sampleRate | Double (Hz) | > 0 |
| channelCount | Int | ≥ 1. More than 2 is downmixed (known layout) or uses channels 1–2 (unknown layout), per FR-017 |
| isInterleaved | Bool | — |
| sampleType | float32 / int16 / int32 | converted to Float32. Only an unconvertible format → `error` (FR-017) |

Internal normalized format (research R-05): Float32, interleaved stereo, 44,100 Hz.

## ClassifierThresholds (tunable; spec Assumptions)

| Field | Default |
|-------|---------|
| activePeakDBFS / activeMinDuration | −50 dBFS / 250 ms |
| silentPeakDBFS / silentMinDuration | −60 dBFS / 2 s |
| noAudioTimeout | 5 s |
| prolongedSilenceHint | 60 s |

## AudioDiagnosticsSnapshot (FR-020, FR-022)

| Field | Type |
|-------|------|
| sourceMode, state | AudioSourceMode, AudioState |
| format | AudioFormat (current) and formatChangeCount |
| sampleCount | UInt64 |
| firstSampleTime, lastSampleTime | host time (s) |
| bufferCadence | mean/max interval between buffers (ms) |
| peakDBFS, rmsDBFS | Float (last 1 s window) |
| droppedFrames, lateBuffers | UInt64 (ring overflow, cadence > 2× mean) |
| startToFirstAudio | ms, nil until the first data |

Never contains samples or device identifiers.

## DiagnosticsExport (FR-021)

Serialized snapshot plus run metadata (device model, OS build, app build, timestamps, optional tester
note). Schema: [contracts/diagnostics-export.schema.json](contracts/diagnostics-export.schema.json).

## CompatibilityTestRecord (FR-031) — lives in `docs/test-reports/`, not in the app

device model, OS build, toolchain version, source app + version, capture mode, picker selection,
audio arrived (bool), non-silent (bool), sample rate, channel count, latency avg/worst (ms),
interruption/end behavior, result (`works` | `partial` | `doesNotWork`), limitation (required
if partial), reproduction steps, linked export file(s).

## StageDecision (FR-033) — in the report

stage, decision (go/no-go), approver, date, evidence links, claimable sources.

## Preset

| Field | Type | Rules |
|-------|------|-------|
| id | String | stable: relative bundle path |
| name | String | display name from the file name |
| packID, author, license, sourceURL, sourceVersion | String | all required; joined from `Presets/LICENSES.md` (FR-047, R-09) |
| loadStatus | unknown / ok / failed(reason) | failed presets are skipped (FR-045) |

## Persisted (FR-065) — UserDefaults

| Key | Type |
|-----|------|
| `favorites` | [Preset.id] |
| `lastPresetID` | Preset.id? |
| `settings.performanceOverlay` | Bool, default false (FR-048) |
| `settings.reduceFlashing` | Bool?; nil → follow Reduce Motion (FR-072) |
| `notice.photosensitivityAcknowledged` | Bool (FR-071) |

Nothing else is persisted.
