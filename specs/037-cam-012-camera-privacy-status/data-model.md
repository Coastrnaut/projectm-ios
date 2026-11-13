# Data Model: CAM-012 Camera Privacy Status

No stored data (CAM-012-R8). Two derived, in-memory values.

## CameraIndicator (value)

| Field | Type | Rule |
|---|---|---|
| `isShown` | Bool | `feedState == .starting || feedState == .running` (CAM-012-R1, R2) |
| `accessibilityValue` | String | "Starting" or "Live" (CAM-001's values) |

Derived from `CameraFeedState` by `CameraIndicator(state:)`; never stored.

State transitions (from CAM-001's provider; indicator in brackets):

```text
idle [off] --start--> requestingAccess [off] --allow--> starting [on] --> running [on]
running [on] --interrupt--> interrupted [off] --end--> running [on]
running/starting [on] --Stop camera | pause | background | scene | presentation loss--> idle [off]
running [on] --error--> failed [off]
```

## Fallback visual

`AppSettings.visualBeforeCamera`: the `VisualChoice` read from the stored `settings.visual` key;
projectM when absent, unknown or `camera` (CAM-001-R11). Read only.

## Host flag

`CameraVisualHost.cameraStoppedByUser`: set by `stopCamera()`; while set, the frame loop runs
without starting the camera. Lives and dies with the host (the coordinator releases the host right
after Stop).
