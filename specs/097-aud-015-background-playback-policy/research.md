# Research: AUD-015 Background Playback Policy

## AUD-015-D1: Two independent flags in the capture layer

- **Decision**: CaptureManager tracks `isBackgrounded` and `isLocked` separately. Background sets
  the first, lock the second, unlock clears only the lock, and entering the foreground clears both
  (the app is visible, so the device is unlocked). Automatic resume needs both clear.
- **Rationale**: the single flag let an unlock while still in the background resume the
  Microphone (spec Baseline gap 1). PERF-011's `PresentationAvailability` already uses these rules
  for rendering; the capture layer now matches it. CaptureKit does not depend on
  PresentationLifecycle, so the two flags are repeated rather than imported (two booleans).
- **Alternatives**: forward only "can present" transitions from LifecycleCoordinator (would change
  every CaptureKit test and CaptureLab's direct wiring); depend on PresentationLifecycle from
  CaptureKit (a new package edge for two booleans).

## AUD-015-D2: Hold a start or resume that completes while away

- **Decision**: after a successful start, and before an automatic or user resume, the manager asks
  the policy; if the app is away and the action is `pausePlayback` or `stopCapture`, the source is
  suspended at once (start) or not resumed (resume), and the state is Paused.
- **Rationale**: lifecycle events are serialized with commands, but a command queued before the
  background event can finish after it (spec gap 2).
- **Alternatives**: refuse the start (would show a failure for a user action that was valid when
  made).

## AUD-015-D3: The notice on return

- **Decision**: `CaptureManager.backgroundNotice` holds the reason of the last pause or stop the
  policy applied while away. The app shows it only once the app can present again and the source
  shows no FR-015 reason, clears it after 8 s (a cancellable task, as the photo and video notices
  do), on Dismiss, and the manager clears it on any start, Stop, user pause or resume. VoiceOver
  hears it once when it appears.
- **Rationale**: FR-050's automatic resume is quick; without a notice the user cannot tell that
  the microphone was off. Reusing the notice pattern keeps the UI consistent.
- **Alternatives**: a new StopReason (would change states and the export schema); a modal alert
  (blocks the visuals).

## AUD-015-D4: No `audio` background mode, no "keep playing" setting

- **Decision**: the shipped app passes `declaresAudioBackgroundMode` read from its Info.plist
  (`UIBackgroundModes` contains `audio`: false) and `keepPlayingInBackground: false`.
- **Rationale**: `check_compliance.py` allows only `[screen-capture]` (ADR-0001 ruling 17); adding
  `audio` is an App Store-facing change. Reading the plist keeps the policy truthful if that ever
  changes.

## AUD-015-D5: System/App Capture

- **Decision**: `followSystem`: no app action away, no automatic restart, existing "Ended by
  system" banner. The `screen-capture` mode and iOS's own recording indicator make the capture
  visible; a lock ends it (-3817, T041 on D1).
