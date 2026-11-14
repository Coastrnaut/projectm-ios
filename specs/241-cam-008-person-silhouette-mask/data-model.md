# Data Model: CAM-008 Person Silhouette Mask

| Entity | Fields | Rules |
|---|---|---|
| `CameraPersonMaskMode` | `off`, `person`, `background` (raw strings) | Stored as `settings.camera.personMask`; unknown → `off`. |
| `PersonMaskBitmap` | `width`, `height`, `bytes` (8-bit coverage, row-major, top row first), `space` (`texture`/`upright`) | `bytes.count == width × height`; memory only. |
| `PersonSegmentationQuality` | `fast`, `balanced`, `accurate` | `accurate` never chosen by policy. |
| `PersonMaskPlan` | `run(quality, stride)` or `paused` | From `PersonMaskPolicy`. |
| `PersonMaskAvailability` | `available`, `unsupported`, `failed`, `paused` | Only `available` masks; note text per state in the app. |
| `PersonMaskSchedule` | `stride`, `offeredSinceStart`, `inFlight` | Starts on first offer; then every `stride`-th offer when none in flight. |
| `PersonMask` (held) | bitmap, `serial`, camera `position` | Used only for the camera position being drawn. |

State: the masker's availability changes `available ↔ paused` with the thermal state; `→ failed` on
an analysis error (sticky); `unsupported` is fixed at creation.
