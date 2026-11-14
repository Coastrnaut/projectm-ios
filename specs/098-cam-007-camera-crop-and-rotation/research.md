# Research: CAM-007 Camera Crop and Rotation

## Audit: today's fit and rotation path (commit `d964e8d`)

- `AVCameraFrameProvider` follows `AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture`
  (KVO) and stores the angle, rounded to a quarter turn (`CameraRotation`), in the newest-picture
  slot; every `CameraFrame` carries its `rotation`. The capture connection itself is not rotated.
- `CameraLayerSource.render` builds `CameraPictureGeometry(pictureWidth:pictureHeight:rotation:outputWidth:outputHeight:mirrored:)`
  every frame from the frame's size and rotation and the layer picture's size. The geometry makes
  the picture upright (width and height swap for 90/270), scales it with
  `max(outputW/uprightW, outputH/uprightH)` (aspect fill), and centers the crop
  (`offset = (1 − visible) / 2`).
- The fragment shader maps output point p to `ab = offset + p × visible`, flips `ab.x` when
  mirrored (CAM-002), then turns `ab` into the texture coordinate by the rotation.
- The layer picture is the drawable's size (`CameraVisualHost.layoutDrawable` sets it on every
  layout, so a device rotation changes the aspect); nothing is cached between frames.

So rotation already reaches the layer and the fill is recomputed each frame; what is missing is a
user choice of fit and crop that the same recomputation preserves.

## CAM-007-D1: placement rule ("object-position")

- **Decision**: upright size `(uw, uh)`, output `(ow, oh)`. Base scale `s0 = max(ow/uw, oh/uh)` for
  Fill, `min(ow/uw, oh/uh)` for Fit; `s = s0 × zoom`. Shown fraction `visible = (ow/(uw·s),
  oh/(uh·s))`. Offset `= (1 − visible) × anchor`, anchor `= (0.5, ay)`, `ay` 0 (Top), 0.5 (Centre),
  1 (Bottom).
- **Why**: output point `a` shows upright point `offset + a·visible = a` for `a = anchor`, so the
  anchor point always lands on the same relative output point, for every output aspect, rotation,
  mode and zoom: exactly "preserves the chosen crop behavior" in a measurable form. In Fill,
  `visible ≤ 1`, so `offset ∈ [0, 1 − visible]`: the layer is always covered. In Fit at 1×,
  `visible ≥ 1`, `offset ≤ 0` and `offset + visible ≥ 1`: the whole picture is visible. Picture
  pixels per output pixel are `1/s` in both directions: no stretch. With Centre and 1× the result
  equals CAM-001's formula.
- **Alternatives**: centring a crop window on the focus and clamping it to the picture (the focus
  then moves on screen whenever the clamp engages, so "same relative position" fails); free pan
  (more UI, no request).

## CAM-007-D2: Fit bars

- **Decision**: the shader returns transparent black when the upright coordinate is outside
  [0, 1] (tolerance 1e-4 so Fill's edge pixels never drop out). The geometry offers the same test
  (`contains`). In the Camera visual the camera is the bottom layer, so the bars show the
  composite's black background on screen, in saved frames and recordings.
- **Alternatives**: clamp-to-edge smear (looks broken), black written by the layer (hides layers
  below in future stacks; transparent matches the layer's fallback).

## CAM-007-D3: rotation needs no new path

- **Decision**: keep the rotation source and the per-frame geometry; only add the crop input. A
  portrait→landscape turn changes the drawable aspect and the frame's rotation angle; the same
  formula with the same crop gives the same anchor placement and zoom ratio.
- **Device caveat**: the order in which a new drawable size and a new rotation angle arrive may
  differ by a frame or two on hardware; each frame is still undistorted (both values are read
  together per frame). Measured only on devices (CAM-007-S6).

## CAM-007-D4: storage

- **Decision**: three UserDefaults keys shared by both cameras: `settings.camera.cropMode`
  (`fill`/`fit`), `settings.camera.cropAnchor` (`centre`/`top`/`bottom`), `settings.camera.zoom`
  (Double from {1, 1.5, 2, 3}); unknown values read as defaults. Not in scenes or cues.

## CAM-007-D5: zoom choices

- **Decision**: four discrete steps 1×, 1.5×, 2×, 3× in a segmented picker. Continuous zoom and
  pinch need a gesture design (and conflict with the visualizer's own gestures); out of scope.
  3× keeps at least a third of the picture's width and height, enough for a 1080p sensor on a
  phone screen.
