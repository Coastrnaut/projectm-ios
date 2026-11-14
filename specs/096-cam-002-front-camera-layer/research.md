# Research: CAM-002 Front Camera Layer

## CAM-002-D1: Where and how the mirror is applied

- **Decision**: In `CameraPictureGeometry`'s output → texture mapping, and the identical arithmetic
  in the camera fragment shader. For output point (x, y): upright a = offsetX + x · visibleWidth,
  b = offsetY + y · visibleHeight; if mirrored, a = 1 − a; then the existing rotation mapping.
  The flip is about the upright picture's vertical center, so the centered aspect-fill crop is
  unchanged and only the camera layer flips (the spectrum layer above it does not).
- **Rationale**: one point, already unit-tested on the CPU and mirrored by the shader; costs one
  branch per fragment, no extra pass or texture.
- **Alternatives**: `AVCaptureConnection.isVideoMirrored` (real camera only, the stub would not
  exercise it, and per-connection state would be a second place); flipping the composite (also
  flips the spectrum and text); a CAMetalLayer transform (screen only, not saved output).

## CAM-002-D2: Where the outputs read frames (audit)

- Screen: `CameraVisualHost.frame` composites into the drawable (`Compositor.composite`).
- REC-001 Save Frame: `FrameCaptureSource` for `CameraVisualHost` → `compositor.requestFrameCapture`;
  the compositor copies its next composite after the flash guard.
- REC-003 Record: `VideoRecordingTap.record` → `compositor.encodeOutput(into:commandBuffer:)`, the
  same composite through the output pass, in the same command buffer as the drawable.
- OUT-001 external display: the coordinator moves the host's view into the external window; same
  compositor and composite.
- **Decision**: no output changes; the acceptance test reads all three paths for one frame.

## CAM-002-D3: No stale pictures across a switch

- **Decision**: `CameraFrame.position` is stamped per picture (stub: its position at store time;
  AV: the connection's input port `sourceDevicePosition`). `CameraLayerSource.render` draws only
  a frame whose position equals `provider.position`; otherwise it throws `.notReady` and drops its
  held frame. A switch also clears the slot.
- **Rationale**: correct whatever the queue timing; no lock or wait added.

## CAM-002-D4: Switching a running AV session

- **Decision**: main thread: bump generation, close the slot, state `starting`. Session queue:
  `beginConfiguration`, remove the old input, add the new device's input (if refused, re-add the
  old one and report `unavailable`), `commitConfiguration`. Then `videoQueue.async` opens the slot
  (buffers queued before that are dropped while closed), then main: new `RotationCoordinator`,
  state `running`. The session keeps running (no `stopRunning`), the audio source is untouched.
- **Alternatives**: stop and start a new session (badge flickers idle, slower, a second
  permission check); two sessions (forbidden: one camera layer instance).

## CAM-002-D5: Orientation of the front camera

- **Decision**: keep `AVCaptureDevice.RotationCoordinator(device:previewLayer: nil)` and
  `videoRotationAngleForHorizonLevelCapture` (iOS 17+, available on iOS 26 and 27; CAM-001's
  API), created for the new device on each switch. The coordinator accounts for the front sensor's
  mounting; the mirror is applied after rotation, so mirrored and unmirrored pictures are both
  upright. The real angles are checked on D1-D3 (`{device}`).

## CAM-002-D6: Settings and storage

- **Decision**: `settings.camera.position` (`back`/`front`, unknown → back),
  `settings.camera.mirrorFront` (absent → true), `settings.camera.mirrorBack` (absent → false).
  Cleared with `AppSettings.allKeys` (`-uitestResetNotice`), listed in `ALLOWED_KEYS`.
- Scenes and show cues record the visual chosen before Camera (`recordedVisual`), so no camera
  setting enters them (SCN-001, SHOW-001 rules unchanged).

## CAM-002-D7: Usage text and indicator

- **Decision**: usage text in spec Clarifications, changed in `project.yml`, `PermissionCatalog`
  and the policy together; badge "Front camera on" for the front camera.
