# Research: AUD-014 Audio session interruption recovery

Date 2026-11-12. Sources: the code at `e40e578`, the iOS 27.2 SDK headers
(`AVFAudio.framework/Headers/AVAudioSessionTypes.h`, `AVAudioSession.h`, `AVAudioEngine.h`),
feature 001 (spec, data-model lifecycle matrix, `contracts/ui-states.md`), ADR-0001, AUD-006.
Decisions are numbered AUD-014-D1 to D10.

## Audit of HEAD (file and line)

Paths are under `Packages/CaptureKit/Sources/CaptureKit/`.

| Event | In-App Playback | Microphone | System/App Capture |
|---|---|---|---|
| Interruption began | `InAppPlayback/AVInAppPlaybackBackend.swift:173-183` forwards `.interruptionBegan`; the graph is not paused. `CaptureManager.swift:362-364` applies it when running → `interrupted`. Position: `InAppPlaybackGraph.swift:153-170` falls back to `lastReadFrame` (the last UI read) or the schedule's start frame once the player's time cannot be read | `Microphone/AVMicrophoneBackend.swift:123-134` forwards; manager → `interrupted`; the engine is not torn down | `CaptureManager.swift:363-364`: ignored (FR-051) |
| Ended, shouldResume | `CaptureManager.swift:365-367`: `resumeInner()` when the state is `interrupted`. No check of the foreground, of a seek or track change by the user, or of a lost route | same path; `MicrophoneSource.resume` re-checks permission and input | ignored |
| Ended, no shouldResume | stays `interrupted` (`:366-367`); `resume()` from the transport or the banner works (`:324-339`) | stays `interrupted`; Restart (FR-051) | ignored |
| Ended never delivered | stays `interrupted`; a Play that iOS refuses throws in `AVInAppPlaybackBackend.resume` (`:98-106`) and `resumeInner` ends the session (`CaptureManager.swift:331-337`) | stays `interrupted` | ignored |
| Reason / wasSuspended | not read. `AVAudioSessionInterruptionWasSuspendedKey` is deprecated since iOS 14.5; `AVAudioSessionInterruptionReasonAppWasSuspended` is "not present from iOS 16 onwards" (header) | not read | — |
| `AVAudioEngineConfigurationChange` | not observed anywhere | not observed (the route observer restarts the engine, `:135-147`) | — |
| Media services reset | not observed | `:148-152` → `.failed(.error("Audio services were reset"))` | — |
| Route `oldDeviceUnavailable` | `AVInAppPlaybackBackend.swift:164-172`: `pause()` + `.outputRouteLost`; manager `:368-371` only while running → Paused, `audioRouteChanged`; foreground does not resume it (`:197`) | continue on the new input or `.failed(.microphoneUnavailable)` | — |
| Background during an interruption | `CaptureManager.swift:190-194`: suspend, `pauseReason = nil`, Paused. Foreground (`:195-198`) then resumes regardless of the interruption | same | keeps running |

## What changed (after implementation, 2026-11-12)

| Event | In-App Playback now | Microphone, System/App Capture |
|---|---|---|
| Interruption began | The backend holds the graph at once (`AVInAppPlaybackBackend.handle`), so the position is the one of that moment (player time, or start frame + frames the tap delivered). `CaptureManager` opens an `OpenInterruption` record | unchanged |
| Ended, shouldResume | `InterruptionPolicy` decides: resume only if eligible, not paused by the user, transport untouched, output not lost, app presentable; deferred to the next foreground/unlock otherwise | unchanged |
| Ended, no shouldResume | unchanged state ("Interrupted", FR-051); the record keeps a later foreground from resuming | unchanged |
| Ended never delivered | stays "Interrupted"; a refused Play keeps the session (track, position) | unchanged |
| Reason | `routeDisconnected` is treated as an interruption plus a lost output; the suspended-app marker is still not used (not sent on iOS 16+) | unchanged |
| `AVAudioEngineConfigurationChange` | observed per graph; a playing graph is held and resumed through the cut, a held graph stays held | unchanged (not observed) |
| Media services reset | the graph is rebuilt at its position; continues only if it was playing; failure → "In-App Playback failed" | unchanged (Microphone: visible error) |
| Route `oldDeviceUnavailable` | as before while playing; now also recorded during an interruption and while the lifecycle holds playback, so nothing resumes by itself afterwards | unchanged |
| Background during an interruption | Paused with the "Interrupted" reason; the foreground no longer resumes blindly | unchanged |

## Decisions

### AUD-014-D1: which system signals

- **Decision**: `AVAudioSession.interruptionNotification` with `AVAudioSessionInterruptionTypeKey`,
  `AVAudioSessionInterruptionOptionKey` (`.shouldResume`) and `AVAudioSessionInterruptionReasonKey`
  (only `routeDisconnected`, raw value 4, is acted on); `routeChangeNotification` with
  `AVAudioSessionRouteChangeReasonKey == .oldDeviceUnavailable`;
  `mediaServicesWereResetNotification`; `AVAudioEngineConfigurationChange` on the graph's engine.
- **Rationale**: these exist on every supported version (iOS 26.0+). The iOS 27.2 SDK marks the
  interruption notification and its keys `API_DEPRECATED(... ios(6.0, 27.0))` in favor of
  `AVAudioSessionDidBecomeInactiveNotification` / `AVAudioSessionResumptionRecommendationNotification`,
  which are `API_AVAILABLE(ios(27.0))`. With a 26.0 deployment target the old API compiles without
  a warning and is the only path on D3 (iPadOS 26.5).
- **Alternatives**: observe both families on iOS 27 (rejected: every interruption would be seen
  twice, and the new semantics cannot be verified before the device phase); only the new family
  (rejected: nothing on iOS 26).
- **Open (device)**: that iOS 27.0.1 and 27.2 still deliver the older notification
  (AUD-014-S6 tasks).
- The suspended-app marker is not handled: by the header it is not sent on iOS 16 or later.

### AUD-014-D2: one pure policy function, state kept by its callers

- **Decision**: `InterruptionPolicy.decide(Input) -> Decision`, a total function. The open
  interruption (what happened so far) is a small record in `CaptureManager`.
- **Rationale**: the roadmap row asks for a policy; a table over seven inputs can be tested
  exhaustively (864 rows) and read in a contract. Sequencing (who paused, what iOS said) already
  lives in `CaptureManager`'s serialized queue.
- **Alternatives**: a state machine type with its own event log (rejected: duplicates the
  manager's serialization and the classifier); decisions inline in `CaptureManager` (rejected: not
  testable as a table).

### AUD-014-D3: feature 001's states and reasons are kept

- **Decision**: no new `AudioState`, `StopReason`, `SourceEvent` or lifecycle-log name. After an
  interruption without resume the state stays `interrupted` (FR-051). While the app is in the
  background during an interruption the state is `paused` with reason `interrupted`.
- **Rationale**: FR-051 and `contracts/ui-states.md` stay in force; the diagnostics export schema
  enumerates states and reasons.
- **Alternatives**: a "Paused after interruption" state (rejected: rewrites FR-051 and the schema).

### AUD-014-D4: return to the foreground with an open interruption

- **Decision**: no resume until iOS indicated one (then at once, or on the next foreground/unlock)
  or the user presses Play.
- **Rationale**: at HEAD the foreground resume runs while a call may still hold the audio; the
  activation then fails and the session ends as failed. FR-050 says "if ... the audio route still
  allow it; otherwise the state shows the FR-015 reason", and FR-051 ties the resume to the OS
  indication.
- **Risk**: if a device never delivers the end of an interruption to an app that was in the
  background, the user has to press Play. Observed in the device phase.

### AUD-014-D5: a refused Play during an open interruption

- **Decision**: `resumeInner` failure keeps the session when the record's signal is `.pending`.
- **Rationale**: the track and position must survive (AUD-014-R8, R11). The backend's `resume`
  changes nothing when activation fails; the graph stays held.

### AUD-014-D6: holding the position

- **Decision**: at "began" the backend calls `graph.hold()`. The position is, in this order: the
  player's time if readable; else the schedule's start frame plus max(last successful read, frames
  delivered by the tap since the last cut × track rate / tap rate).
- **Rationale**: when iOS has already stopped the engine, `player.lastRenderTime` may be nil. The
  tap counter needs no UI and no timer, costs one atomic add on the tap thread, and is at most one
  tap block (about 100 ms) behind the audio heard: inside AUD-014-R10's 0.25 s and never ahead by
  more than the few frames rendered between the tap's installation and `play()`.
- **Alternatives**: a main-actor timer that reads the position (rejected: a wake-up 4 times per
  second for the whole session); `AVAudioPlayerNode` completion callbacks (rejected: per segment
  only).

### AUD-014-D7: every restart is AUD-006's cut

- **Decision**: resume after an interruption, after a configuration change and after a rebuild all
  go through `cut()` + `schedule(from: heldFrame)`; a rebuilt graph starts with an empty sink
  (`discardBufferedAudio`).
- **Rationale**: AUD-006-R10 already guarantees that nothing from before a cut is delivered.

### AUD-014-D8: engine configuration change

- **Decision**: observe `AVAudioEngineConfigurationChange` for the graph's engine. If the graph was
  playing: hold, `engine.start()`, cut, schedule from the held frame. If it was held: nothing (the
  next resume starts the engine and reinstalls the tap with the mixer's current format).
- **Rationale**: header: the engine stops and uninitializes itself; nodes stay attached and
  connected; the mixer→output connection is updated by the engine on restart when the client never
  set it (this graph does not). `installGatedTap` already reads the mixer format on each install.

### AUD-014-D9: media-services reset

- **Decision**: build a new `InAppPlaybackGraph` from the current track at the old graph's
  position and held state, after setting the category and activating the session again; drop the
  old graph. Continue playing only if it was playing (policy with `.notInterrupted`); an open
  interruption has already put the graph on hold, so it stays held.
- **Rationale**: Apple's guidance for the reset is to dispose of audio objects and create new
  ones. Microphone keeps its feature 001 behavior (visible error).

### AUD-014-D10: test seams

- **Decision**: the backend exposes `handle(_ signal:)` (internal) and takes a `NotificationCenter`
  (default `.default`). Tests post to a private center (iOS simulator) or call `handle` (host), and
  stop the offline engine behind the graph's back with a test-only hook to imitate iOS.
  The app's UI test posts the real notification names to the default center from a DEBUG panel
  (`-uitestSessionEvents`), the same notifications `AutomationRunner` sc009 posts.
- **Rationale**: `AVAudioSession` does not exist on macOS, so the host needs a platform-neutral
  entry; the simulator run covers the notification mapping.
