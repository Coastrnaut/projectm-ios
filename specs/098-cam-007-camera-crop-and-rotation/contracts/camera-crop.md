# Contract: Camera crop and rotation (CAM-007)

## CameraPictureGeometry

`init(pictureWidth:pictureHeight:rotation:outputWidth:outputHeight:mirrored: = false, crop: = .fill)`

With upright size `(uw, uh)` (swapped for 90/270), output `(ow, oh)`, `s0` = max (Fill) or min
(Fit) of `(ow/uw, oh/uh)`, `s = s0 × crop.zoom`:

- `visibleWidth = ow / (uw × s)`, `visibleHeight = oh / (uh × s)`;
- `offsetX = (1 − visibleWidth) × 0.5`, `offsetY = (1 − visibleHeight) × anchor.y`;
- any size ≤ 0 → `.identity` with the rotation and mirror (unchanged).

Guarantees (tested, CAM-007-S1):

1. `visibleWidth × uw / ow == visibleHeight × uh / oh` (no stretch).
2. Fill: `0 ≤ offset` and `offset + visible ≤ 1` on both axes (covered).
3. Fit at 1×: `offset ≤ 0` and `offset + visible ≥ 1` on both axes (whole picture visible).
4. Output point `(0.5, anchor.y)` shows upright point `(0.5, anchor.y)` (anchor kept).
5. `s / s0 == zoom` for every output size (zoom kept).
6. `crop == .fill` gives exactly CAM-001's geometry.

`textureCoordinate(x:y:)` unchanged (crop, then mirror, then rotation). `contains(x:y:)` is true
when `offset + p × visible` lies in [−1e-4, 1 + 1e-4] on both axes.

## CameraLayerSource

- `var crop: CameraCrop` (default `.fill`) — main thread; applies from the next `render`; never
  starts, stops, reconfigures or re-asks the camera.
- Shader: transparent `(0, 0, 0, 0)` where `contains` is false; otherwise as before.

## CameraVisualHost

- `crop: CameraCrop` (get/set) forwarded to the layer; `make(…, crop: = .fill)`.

## App UI (Settings › Camera, only while Camera is the chosen visual)

| Element | Identifier | Label | Values |
|---|---|---|---|
| Crop picker (segmented) | `cameraCropModePicker` | Crop | Fill / Fit |
| Anchor picker (segmented) | `cameraCropAnchorPicker` | Anchor | Center / Top / Bottom |
| Zoom picker (segmented) | `cameraZoomPicker` | Zoom | 1 times / 1.5 times / 2 times / 3 times (titles 1×, 1.5×, 2×, 3×) |
