# Data Model: AUD-015 Background Playback Policy

Nothing is persisted. All types are value types in CaptureKit.

## BackgroundPolicy.Context

| Field | Type | Meaning |
|---|---|---|
| mode | AudioSourceMode | the active source |
| isBackgrounded | Bool | the app is in the background |
| isLocked | Bool | the device is locked (protected data unavailable) |
| declaresAudioBackgroundMode | Bool | Info.plist `UIBackgroundModes` contains `audio` (false in the app) |
| keepPlayingInBackground | Bool | the user asked In-App Playback to keep playing (no UI; false) |

`isAway = isBackgrounded || isLocked`.

## BackgroundPolicy.Action

`run` (in the foreground and unlocked) · `pausePlayback` · `stopCapture` · `continuePlayback` ·
`followSystem`.

## BackgroundPolicy.Reason

`foreground` · `playbackPausedInBackground` · `playbackContinuesInBackground` ·
`microphoneStoppedInBackground` · `systemCaptureFollowsSystem`. `notice` gives the user-visible
text, nil for `foreground`, `playbackContinuesInBackground` and `systemCaptureFollowsSystem`.

## BackgroundPolicy.Configuration

`declaresAudioBackgroundMode`, `keepPlayingInBackground`; `CaptureManager.backgroundConfiguration`,
default both false. `static func declaresAudioMode(in backgroundModes: [String]) -> Bool`.

## CaptureManager additions

- `backgroundNotice: BackgroundPolicy.Reason?` (observable): set when the policy paused or stopped
  the session while away; cleared by a new attempt, Stop, user pause, user resume and
  `dismissBackgroundNotice()`.
- `isAway: Bool` (read-only): background or locked.

## Transitions (Microphone, In-App Playback in the shipped configuration)

| From | Event | To |
|---|---|---|
| Running / Interrupted | background or lock | Paused (source suspended), notice set |
| Paused (lifecycle) | unlock while backgrounded | Paused (nothing resumes) |
| Paused (lifecycle) | foreground (clears both) or unlock in the foreground | resume per FR-050 / AUD-014 / AUD-006 |
| starting | start completes while away | Paused (source suspended), notice set |
