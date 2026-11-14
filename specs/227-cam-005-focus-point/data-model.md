# Data Model: CAM-005 Camera Focus Point

All values are session state; nothing is stored (CAM-005-R9).

- **CameraFocusPoint** `{x, y: Double}` in 0…1 (camera point-of-interest space); `centre` = (0.5, 0.5);
  initializer clamps and replaces non-finite values with 0.5.
- **CameraFocusMode** `autoFocus | continuousAuto | locked | other` (read back from the camera).
- **CameraFocusState** `{canFocus: Bool, isRunning: Bool, mode: CameraFocusMode, point: CameraFocusPoint}`;
  `notRunning(canFocus:)` = continuous auto at the centre; `isAdjustable` = canFocus && isRunning.
- **CameraDrawnPicture** `{width, height: Int, rotation: CameraRotation}`: the picture the camera
  layer drew last (nil when none).
- **CameraFocusMapping input**: touch (x, y), rect (x, y, width, height) in points, drawn picture,
  crop (CAM-007), mirrored (CAM-002) → `CameraFocusPoint?`.
- **CameraFocusTapOutcome** `focused(CameraFocusPoint) | outsidePicture | unsupported | notRunning`.

State transitions: notRunning → (start) running/continuous centre → (tap) autoFocus at p →
(lens/position switch, stop) continuous centre.
