# Contract: User-Visible States and Messages

The UI renders only these strings for source and audio status, so tests and copy reviews have a
single source of truth. (English only, per Out of Scope.)

## Source labels (FR-013)

| Mode | Label | Unavailable text |
|------|-------|------------------|
| System/App Capture | System/App Capture | Requires a newer iOS version |
| Microphone | Microphone | — |
| In-App Playback | In-App Playback | — |

The Microphone explainer, shown before the permission prompt (FR-005), reads: "Microphone mode
listens to sound in the room through your device's microphone. It does not capture audio directly
from other apps."

## Usage descriptions (FR-019)

| Info.plist key | Text |
|----------------|------|
| `NSMicrophoneUsageDescription` | Same text as the Microphone explainer above |
| Capture key (identified by RI-001) | To be written when RI-001 names the key; it must say that only audio from the content you choose is used, on this device only |

## Source chooser descriptions (FR-080)

| Mode | One-line description |
|------|----------------------|
| System/App Capture | Visualize audio from content you choose to share, where iOS allows it. |
| Microphone | Visualize sound in the room through the microphone. |
| In-App Playback | Visualize the built-in reference track. |

## Audio states (FR-010)

Not started · Waiting · No audio received · Audio received — silent · Active audio · Paused ·
Interrupted · Stopped · Ended by system

## Stop/failure reasons (FR-015)

| StopReason | Message | Actions |
|------------|---------|---------|
| cancelled | Not started — cancelled | Choose source |
| permissionDenied | Microphone permission denied. Enable it in Settings › Privacy › Microphone. | Open Settings, Choose source |
| microphoneUnavailable | Microphone unavailable | Choose source |
| inAppPlaybackFailed | In-App Playback failed | Choose source |
| interrupted | Interrupted | Restart, Choose source |
| audioRouteChanged | Paused — audio route changed | Resume, Choose source |
| endedBySystem | Ended by system | Restart (re-presents the system picker for System/App Capture), Choose source |
| unsupportedOS | Requires a newer iOS version | Choose source |
| error | Something went wrong: ‹description› | Restart, Choose source |

Hints: No audio received → "No audio received. Try another source or use Microphone." Prolonged
silence (FR-018) → "No sound detected — is playback paused?"

## Visualizer (Stage 2)

Controls auto-hide after 5 s (FR-042); the compact source-and-state indicator stays visible.
Messages appear as non-modal banners (FR-083). Paused: last frame dimmed with "Paused" (FR-085).
Empty favorites: "No favorites yet — tap the star on a preset to add one." (FR-088). Preset failure: "Preset could not be loaded" (FR-045).
Photosensitivity notice (FR-071) must be acknowledged before the first visualization.

## Diagnostics export (FR-021)

Note field placeholder: "Optional note, e.g. which app was playing. Do not enter personal
information." Limit: 500 characters.

## Licenses (FR-067)

Settings › Licenses lists each component, preset pack, and asset with its license text. LGPL entries
include the source link and replacement instructions from ADR-0005.

## Accessibility (FR-070)

Every control has an accessibility label equal to its visible text or icon meaning. Audio-state
changes post an announcement with the state string above.

## Claims (FR-062)

No string in the app may name a third-party app as supported. Compatibility notes in in-app help
come only from report rows, with their recorded limitation.
