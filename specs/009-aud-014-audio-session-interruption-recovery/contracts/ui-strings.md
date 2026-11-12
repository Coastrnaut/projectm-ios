# Contract: user-visible strings added by AUD-014

English only. `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` holds each string verbatim;
`scripts/test_scripts.py` cross-checks every table row below against it. All other strings are
those of feature 001's `contracts/ui-states.md` and of AUD-001, AUD-002 and AUD-006, unchanged.

## Explanations for In-App Playback on hold (AUD-014-R17, R18)

Shown in the status banner under the feature 001 message, for In-App Playback only, and read by
VoiceOver after the status when the reason appears.

| Reason | String |
|--------|--------|
| interrupted | Playback is on hold at its position. It continues when iOS allows it, or press Play. |
| audioRouteChanged | The audio output was disconnected. Press Play to continue. |

Unchanged: the status "Interrupted" with Restart and Choose source, and "Paused — audio route
changed" with Resume and Choose source (FR-051). Microphone and System/App Capture show no
explanation line (AUD-014-R19).

VoiceOver announcement: `‹source› · ‹state›. ‹explanation›`, for example "In-App Playback ·
Interrupted. Playback is on hold at its position. It continues when iOS allows it, or press Play."
