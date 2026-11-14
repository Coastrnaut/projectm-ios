# Data Model: CAM-004 Camera Exposure Lock

All values are session state (main thread mirror); nothing is stored (CAM-004-R8).

## CameraExposureMode (enum)

`locked`, `continuousAuto`, `other` (any other mode the camera reports, e.g. single auto or custom).

## CameraExposureState (struct, Equatable, Sendable)

| Field | Type | Meaning |
|---|---|---|
| `canLock` | Bool | The current camera supports locked exposure. |
| `isRunning` | Bool | The camera runs; changes are possible only then. |
| `mode` | CameraExposureMode | Read back from the camera (`continuousAuto` when not running). |

Derived: `isLocked` (`mode == .locked`), `isAdjustable` (`canLock && isRunning`).
`.notRunning(canLock:)` constructs the state of a stopped camera.

## Transitions

| From | Event | To |
|---|---|---|
| any | camera starts running | `isRunning`, mode read back (automatic) |
| running, canLock | lock | mode read back (`locked` on success) |
| running, locked | unlock | mode read back (`continuousAuto`) |
| running, !canLock | lock | unchanged; no configuration attempted |
| running, locked | lens/position switch | old camera released; new camera read back |
| any | stop, failure, background | camera released; `notRunning` |
