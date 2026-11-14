# Contract: Background playback policy (AUD-015)

This is the developer contract. The user-facing text is in `docs/privacy-policy.md` ("When the
app is in the background"); the decision record is ADR-0036.

## Declared background modes

`UIBackgroundModes: [screen-capture]` only (ADR-0001 ruling 17), enforced by
`scripts/check_compliance.py`. No `audio` mode: iOS suspends the app's audio shortly after it
leaves the foreground.

## Policy table

"Away" = in the background, locked, or both. Audio mode = the app declares the `audio` background
mode; keep = the user asked to keep playing. The shipped app has audio mode **no** and keep **no**.

| Source | Foreground and unlocked | Away, audio mode and keep | Away, otherwise |
|---|---|---|---|
| Microphone | run | **stopCapture** (microphoneStoppedInBackground) | **stopCapture** (microphoneStoppedInBackground) |
| In-App Playback | run | continuePlayback (playbackContinuesInBackground) | **pausePlayback** (playbackPausedInBackground) |
| System/App Capture | run | followSystem (systemCaptureFollowsSystem) | followSystem (systemCaptureFollowsSystem) |

`mayResumeAutomatically(context)` is true only when the app is in the foreground and unlocked and
the source is Microphone or In-App Playback. Whether it then resumes is decided as before: FR-050
(permission and route re-checked, FR-053), AUD-006-R22 (a user pause stays), AUD-014-R5, R6 (an
open interruption stays on hold). System/App Capture is never restarted without the system picker
(FR-055).

## Return notice (projectM-iOS only)

| Reason | Text |
|---|---|
| playbackPausedInBackground | "Playback paused while projectM-iOS was in the background." |
| microphoneStoppedInBackground | "The microphone was off while projectM-iOS was in the background. It never listens in the background." |

Shown under the status (identifier `backgroundNotice`, text `backgroundNoticeText`, button
`backgroundNoticeDismiss`) once the app can present and while the source shows no FR-015 reason;
announced to VoiceOver once; clears after 8 s, on Dismiss, or on a start, Stop, pause or resume.

## Guarantees

1. No Microphone frames reach the app between a background or lock and the next real return.
2. An unlock while the app is in the background resumes nothing.
3. A start or resume that completes while away is held Paused.
4. The visualization and presentation-bound resources are suspended while away (PERF-011).
5. The export schema is unchanged.
