# Contract: CAM-005 Focus point

## C1 `CameraFocusMapping.devicePoint(touchX:touchY:rectX:rectY:rectWidth:rectHeight:picture:crop:mirrored:) -> CameraFocusPoint?`

- Pure; any platform. nil when the rect or picture is empty/non-finite, the touch is outside the
  rect, or the touch is in Fit's bars (`CameraPictureGeometry.contains` false).
- Otherwise equals `CameraPictureGeometry(picture, output = rect size, crop, mirrored).textureCoordinate`
  of the normalized touch, clamped to 0…1.

## C2 `CameraFocusConfiguring` / `CameraFocusControl`

- `focus(at:on:)`: unsupported → no configuration, returns current state. Begin refused → nothing
  changes. Else one configuration: point, then `autoFocus` if supported else `continuousAuto`.
- `reset(_:)`: when the mode or point differ from continuous at the centre and supported, one
  configuration returning to continuous automatic focus at the centre.
- `state(of:)`: read back.

## C3 `CameraFrameProvider`

- `focus: CameraFocusState`, `onFocusChange`, `setFocusPoint(_:)` (running and supported only).
- Lens/position switch and every stop reset the previous device before its input is removed.
- Defaults for providers without focus: cannot focus, no-op.

## C4 App

- `CameraVisualHost.focus(atWindowPoint:) -> CameraFocusTapOutcome`; `focusAtCentre()`.
- Double-tap only while the Camera visual is shown; single tap unchanged.
- Ring `cameraFocusRing` (accessibility id), 1 s; unsupported text "This camera can't focus on a point.";
  VoiceOver action "Focus at centre", announcement "Focusing at centre" (`.camera` lane).
- DEBUG: `-uitestCameraFocusPoint <list|none>` chooses the stand-in cameras with a focus point (nil: all);
  diagnostics probe `cameraFocusProbe` = "x,y,mode" of the read-back state.
