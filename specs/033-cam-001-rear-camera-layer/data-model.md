# Data Model: CAM-001 Rear Camera Layer

Nothing is persisted. All entities live in memory.

## CameraFeedState (CPU, every platform)

| State | Meaning | Layer draws | Notice |
|---|---|---|---|
| `idle` | not started (or stopped) | fallback | none |
| `requestingAccess` | iOS prompt shown (only after the user chose Camera) | fallback | none |
| `starting` | authorized, session starting | fallback | none |
| `running` | pictures arriving | newest picture (fallback until the first) | none |
| `denied` | user denied | fallback | "Camera access is off…" + Open Settings |
| `restricted` | access restricted (Screen Time, MDM) | fallback | restricted text + Open Settings |
| `unavailable` | no back camera / input cannot be added | fallback | "No rear camera is available…" |
| `interrupted` | another app or the system took the camera | fallback | "The camera is paused by the system…" |
| `failed` | runtime error | fallback | same as interrupted |

Transitions: `idle → (unavailable | requestingAccess | starting | denied | restricted)`;
`requestingAccess → (starting | denied)`; `starting → running | unavailable | failed`;
`running ⇄ interrupted`; `running → failed`; any `→ idle` on stop. A stop always ends in `idle`.

Derived: `showsPicture` (running), `notice` (text or nil), `offersSettings` (denied, restricted),
`accessibilityValue` ("Live", "Starting", "Camera access off", "Camera restricted", "No rear camera",
"Paused by the system", "Off").

## CameraScenario (stub only)

`granted`, `notDeterminedGrant`, `notDeterminedDeny`, `denied`, `restricted`, `unavailable`; parsed
from `-uitestCamera <rawValue>` in DEBUG.

## CameraFrame (Metal platforms)

`texture` (`.bgra8Unorm_srgb`, read-only), `width`, `height` (texture pixels), `rotation`
(`CameraRotation`: 0, 90, 180, 270 clockwise to upright), `sequence` (UInt64, increasing). Held only
by `LatestCameraFrame` until replaced or cleared.

## CameraPictureGeometry (CPU)

Input: picture size, rotation, output size. Output: `scale` and `offset` (two SIMD2 floats) mapping
output UV (0…1, top-left) to rotated-picture UV, cropping equally on both sides of the longer
overflow. Degenerate sizes (≤ 0) give the identity.

## AppSettings / VisualChoice

`VisualChoice.camera` ("Camera"), `isNative == false`, `replacesProjectM == true`, `usesCamera ==
true`. `AppSettings.visual = .camera` is not written to UserDefaults; a stored `camera` value (never
written by the app) reads as projectM.
