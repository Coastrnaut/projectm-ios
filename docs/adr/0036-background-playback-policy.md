# ADR-0036: Background Playback Policy

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: AUD-015 (`specs/097-aud-015-background-playback-policy`)
- **Constitution**: I (public APIs only), IV (truthful labeling), VI (modular boundaries);
  Platform, Security & Privacy (background modes documented from the SDK; no covert capture)
- **Builds on**: FR-050, FR-053, FR-054, FR-055, ADR-0001 ruling 17 (`screen-capture` background
  mode), PERF-011 (presentation availability), AUD-006 (user pause), AUD-014 (interruption resume)
- **Amends**: the data-model lifecycle matrix: automatic resume needs the foreground **and** an
  unlock; a start or resume that completes while away is held

## Context

The app declares only `UIBackgroundModes: [screen-capture]`, and `check_compliance.py` rejects any
other value, including `audio`. The audit (spec Baseline) found the behavior mostly in place, but
with one covert-capture gap: the capture layer kept a single "presentable" flag, so an unlock while
the app was still in the background (unlocked onto the Home Screen or another app) restarted a
paused Microphone session. A start finishing after a background event also ran until the next
event, and nothing told the user what had happened while away.

## Decision

1. **One decision function**, `BackgroundPolicy` in CaptureKit (pure, tested on Linux). Inputs:
   source, in the background, locked, declares the audio mode, the user wants to keep playing.
   Output: an action (run, pausePlayback, stopCapture, continuePlayback, followSystem) and a reason
   that carries the return notice's text.
2. **Microphone: always stops while away**, whatever the background modes. It resumes only on a
   real return (foreground and unlocked), as FR-050 requires.
3. **In-App Playback: pauses while away** unless entitled (the `audio` mode) **and** intended (the
   user's choice). The app has neither: no `audio` mode (an App Store-facing change outside this
   row) and no "keep playing" setting, because a setting that cannot work would mislead. The app
   reads its Info.plist, so the policy stays truthful if the mode is ever added.
4. **System/App Capture: follows the system.** The app does nothing on background; iOS shows its
   recording indicator; a lock ends the capture ("Ended by system"); it never restarts without the
   picker (FR-055).
5. **Background and lock are independent** in CaptureManager, as in PERF-011's
   `PresentationAvailability`: entering the foreground clears both; an unlock clears only the lock.
6. **Held while away**: a start or resume of Microphone or (non-entitled) In-App Playback that
   completes while away is suspended at once and shows Paused.
7. **Return notice**: a non-blocking notice under the status names the source and what happened;
   announced to VoiceOver; 8 s, Dismiss, or the next user command clears it; hidden while an FR-015
   reason shows.
8. **Rendering** stays suspended while away (PERF-011, unchanged).

## Consequences

- No microphone frames reach the app between a background or lock and the next real return
  (tested with a fake backend whose engine writes frames only while it runs).
- `LifecycleCoordinatorTests.testUnlockWhileStillInTheBackgroundResumesNothing` now expects no
  microphone resume before the foreground.
- The export schema is unchanged.
- Device behavior per source (AUD-015-T13 on D1) is still to be recorded; simulator runs are not
  evidence.

## Alternatives rejected

- Add the `audio` background mode and a "Keep playing" setting: App Store-facing, outside the
  compliance allow-list, not needed for a visualizer that cannot draw in the background.
- Stop System/App Capture on background: contradicts ADR-0001 ruling 17.
- Wait for a tap before resuming on return: contradicts FR-050; returning to the app is the
  user's action and iOS shows the microphone indicator.
