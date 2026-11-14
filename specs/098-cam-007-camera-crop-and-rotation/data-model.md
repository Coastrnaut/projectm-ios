# Data Model: CAM-007 Camera Crop and Rotation

## CameraCropMode (CameraLayer)

| Case | Raw value | Title | Meaning |
|---|---|---|---|
| `fill` (default) | `"fill"` | Fill | cover the layer picture; overflow cropped |
| `fit` | `"fit"` | Fit | contain the whole picture; transparent bars |

## CameraCropAnchor (CameraLayer)

| Case | Raw value | Title | Upright point (x, y) |
|---|---|---|---|
| `center` (default) | `"center"` | Center | (0.5, 0.5) |
| `top` | `"top"` | Top | (0.5, 0) |
| `bottom` | `"bottom"` | Bottom | (0.5, 1) |

## CameraCrop (CameraLayer, Sendable, Equatable)

- `mode: CameraCropMode`, `anchor: CameraCropAnchor`, `zoom: Float`.
- `static let zoomChoices: [Float] = [1, 1.5, 2, 3]`; `init` snaps any other zoom (or a non-finite
  one) to 1.
- `static let fill = CameraCrop(mode: .fill, anchor: .center, zoom: 1)` (the default; CAM-001's
  picture).
- `static func zoomTitle(_:) -> String` ("1×", "1.5×") and `zoomSpokenValue(_:)` ("1 times",
  "1.5 times"), built in typed steps.

## CameraPictureGeometry (extended)

- New init parameter `crop: CameraCrop = .fill`. Fields unchanged (`visibleWidth`,
  `visibleHeight`, `offsetX`, `offsetY`, `rotation`, `mirrored`); `visible` may now exceed 1
  (Fit) and `offset` may be negative.
- New `contains(x:y:) -> Bool`: the output point shows the picture (upright coordinate within
  [0, 1], tolerance 1e-4).
- Tests derive the scale from `visible` and the sizes; no extra API.

## App settings (shared by both cameras)

| Property | Key | Values | Absent / unknown |
|---|---|---|---|
| `cameraCropMode` | `settings.camera.cropMode` | `fill`, `fit` | `fill` |
| `cameraCropAnchor` | `settings.camera.cropAnchor` | `center`, `top`, `bottom` | `center` |
| `cameraZoom` | `settings.camera.zoom` | 1, 1.5, 2, 3 (Double) | 1 |

`cameraCrop: CameraCrop` combines them (read-only). All three keys are in `AppSettings.allKeys`
and `ALLOWED_KEYS` (`scripts/run_device_tests.py`). They never start the camera and are not
recorded in scenes or cues.

## Flow

Settings change → `VisualizerView.onChange` → `AppCoordinator.cameraSettingsChanged()` →
`CameraVisualHost.crop` → `CameraLayerSource.crop` → next frame's geometry (with the frame's
rotation and the drawable's size) → shader.
