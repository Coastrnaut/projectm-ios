# Data model: AUD-014

Nothing here is persisted or exported.

## InterruptionPolicy (CaptureKit, pure)

| Type | Values |
|---|---|
| `Source` | `inAppPlayback`, `microphone`, `systemAppCapture` |
| `Transport` (before the interruption) | `playing`, `paused`, `stopped` |
| `PausedBy` (who holds it now) | `nobody`, `user`, `system` (the output was lost) |
| `SystemSignal` | `notInterrupted`, `pending`, `endedWithoutResume`, `endedShouldResume` |
| `Input` | `source`, `before`, `pausedBy`, `signal`, `isPresentable`, `userChangedTransport`, `sourceIsUsable` |
| `Hold` | `user`, `outputDisconnected`, `interrupted`, `notPresentable` |
| `Decision` | `resume`, `stayPaused(Hold)`, `stayStopped`, `fail(StopReason)`, `notApplicable` |

"Paused by the app lifecycle" (background, lock) is not a `Transport` pause: it is `before:
.playing` with `isPresentable: false`.

## OpenInterruption (CaptureManager, private, In-App Playback only)

| Field | Meaning |
|---|---|
| `eligible` | playback was playing (or only held by the lifecycle) when the interruption began |
| `signal` | `pending` → `endedWithoutResume` or `endedShouldResume` |
| `userChangedTransport` | pause, Stop playback, seek, next or previous since "began" |
| `outputLost` | the output route was lost since "began" |

Lifetime: created by "began"; cleared by a successful resume, a stop, a failure, the end by the
system and a new attempt. Transitions:

```text
(none) ──began──▶ pending ──ended(resume)──▶ endedShouldResume ──policy: resume──▶ (none)
                     │                              │ not presentable: kept until foreground/unlock
                     └─ended(no resume)─▶ endedWithoutResume ──Play──▶ (none)
pending ──began──▶ pending (unchanged)
endedWithoutResume ──began──▶ pending, eligible = false
endedShouldResume ──began──▶ pending, eligible kept
```

Also in the manager: `isPresentable` (last lifecycle event was foreground/unlock, or none) and
`userPauseIsStop` (the user pause is Stop playback).

## AudioSessionSignal (CaptureKit, internal)

`interruptionBegan(outputDisconnected: Bool)`, `interruptionEnded(shouldResume: Bool)`,
`outputRouteLost`, `engineConfigurationChanged`, `mediaServicesReset`.

## Held position (InAppPlaybackGraph)

`heldFrame` as in AUD-006. New input for it: `PlaybackTapGate.deliveredFrames`, the frames the
current tap has written since the last cut (atomic; reset by every cut).

## Unchanged

`AudioState`, `StopReason`, `SourceEvent`, `LifecycleEvent`, the lifecycle-log names, the
diagnostics export schema, `PlaybackTransport.State`.
