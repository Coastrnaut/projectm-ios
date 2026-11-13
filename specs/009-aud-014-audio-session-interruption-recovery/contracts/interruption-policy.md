# Contract: the interruption policy (AUD-014-R1 to R9)

`InterruptionPolicy.decide(_:)` in `Packages/CaptureKit/Sources/CaptureKit/InterruptionPolicy.swift`.
Types: [data-model.md](../data-model.md). The rules are evaluated in order; the first that matches
gives the outcome. `InterruptionPolicyTests` checks all 3 × 3 × 3 × 4 × 2 × 2 × 2 = 864 inputs
against this table.

| # | Condition | Outcome |
|---|---|---|
| 1 | source is System/App Capture | `notApplicable` (an interruption does not change it; never restarted without the picker: FR-051, FR-055) |
| 2 | the source cannot be used any more | `fail(inAppPlaybackFailed)` for In-App Playback, `fail(microphoneUnavailable)` for Microphone |
| 3 | before = stopped | `stayStopped` |
| 4 | Microphone, before = paused | `stayStopped` (Microphone has no pause) |
| 5 | Microphone, signal = pending or endedWithoutResume | `stayPaused(interrupted)` |
| 6 | Microphone, not presentable | `stayPaused(notPresentable)` |
| 7 | Microphone otherwise | `resume` |
| 8 | In-App, pausedBy = user | `stayPaused(user)` |
| 9 | In-App, pausedBy = system | `stayPaused(outputDisconnected)` |
| 10 | In-App, before = paused | `stayPaused(user)` |
| 11 | In-App, the user changed the transport | `stayPaused(interrupted)` |
| 12 | In-App, signal = pending or endedWithoutResume | `stayPaused(interrupted)` |
| 13 | In-App, not presentable | `stayPaused(notPresentable)` |
| 14 | In-App otherwise | `resume` |

So In-App Playback resumes exactly when: it can be used, it was playing, nobody holds it paused,
the user did not change the transport, iOS indicated a resume (or there was no interruption: a
hardware change or a reset), and the app is in the foreground and unlocked.

## Who asks, and when

| Caller | When | Input notes |
|---|---|---|
| `CaptureManager` | "interruption ended" for In-App Playback with an open interruption | `before` = playing if the record is eligible, else paused/stopped; `pausedBy` from the user pause and the lost route |
| `CaptureManager` | foreground / unlock with an open interruption | the same record; `isPresentable` now true |
| `AVInAppPlaybackBackend` | after `AVAudioEngineConfigurationChange` and after a media-services reset | `signal: .notInterrupted`, `before` = playing unless the graph is held, `sourceIsUsable` = the rebuild succeeded |

`stayPaused(notPresentable)` with `endedShouldResume` is the deferred resume of AUD-014-R5: the
record is kept and the manager asks again at the next foreground/unlock.

Microphone rows 4 to 7 describe what `CaptureManager` already does for Microphone (feature 001);
that code is not routed through the policy and is not changed (AUD-014-R9).

## Outcomes in the app

| Outcome | State and reason shown | Transport |
|---|---|---|
| `resume` | Waiting, then Active audio once verified | playing from the held position |
| `stayPaused(interrupted)` | Interrupted (or Paused with the Interrupted reason while not presentable) + explanation | paused at the held position |
| `stayPaused(outputDisconnected)` | Paused — audio route changed + explanation | paused at the held position |
| `stayPaused(user)` | Paused, no reason | paused where the user left it |
| `stayPaused(notPresentable)` | Paused with the Interrupted reason | paused; resumes on foreground/unlock |
| `stayStopped` | Paused, no reason (AUD-006-R23) | stopped at 0:00 |
| `fail(reason)` | Stopped with the reason (FR-015) | unavailable |
