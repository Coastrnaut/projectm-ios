# Contract: Front camera and mirror (CAM-002)

## CameraLayerSource

- `var mirrored: Bool` — main thread; applies from the next `render`; never starts, stops or
  re-asks the camera.
- `render` draws a picture only when `provider.state == .running`, a picture exists, and
  `picture.position == provider.position`; otherwise `.notReady` (transparent fallback).
- Mapping per output point (0…1, top-left) = `CameraPictureGeometry(…, mirrored:)
  .textureCoordinate(x:y:)`; the shader does the same.

## CameraFrameProvider

- `position`, `select(_:)` as in data-model.md. `select` with the current position is a no-op.
- After `select` returns, `latestFrame()` returns nil or a picture of the new position.

## StubCameraFrameProvider

- `init(…, position: = .back, availablePositions: = [.back, .front])`.
- Pattern `.marker(background:marker:)`: the picture's top-left quarter (x < w/2, y < h/2) is
  `marker`, the rest `background`.
- `selectCount` counts effective switches.

## CameraVisualHost

- `cameraPosition: CameraPosition` (get/set), `mirrored: Bool` (get/set), forwarded to the provider
  and the layer; neither restarts the audio analysis or the frame loop.

## App UI

| Element | Identifier | Label | Value |
|---|---|---|---|
| Camera picker (segmented) | `cameraPositionPicker` | Camera | Back / Front |
| Mirror toggle | `cameraMirrorToggle` | Mirror | on/off (1/0) |
| Badge status | `cameraIndicatorStatus` | Camera on / Front camera on | Live / Starting |
| Camera notice | `cameraNotice` | catalog or CAM-002 unavailable text | — |
