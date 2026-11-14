# ADR-0017: Rear Camera Layer

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CAM-001 (`specs/033-cam-001-rear-camera-layer`); amended by CAM-002 (`specs/096-cam-002-front-camera-layer`)
- **Constitution**: I, VI, X; Privacy

## Context

The roadmap's CAM rows add the device camera as a visual layer. The constitution's Privacy section
asks for a separate specification and a privacy review for a new sensor; the app had no camera
access at all. CMP-001 (ADR-0013) defined the layer contract, but the app does not render through
the compositor yet.

## Decisions

1. **The camera is a layer, not a visual of its own.** `CameraLayerSource` (target `CameraLayer`
   in `Packages/Compositor`) implements the CMP-001 contract and reads pictures from a
   `CameraFrameProvider`, which is either the real `AVCaptureSession` provider (iOS) or a
   deterministic stub (tests, simulator, DEBUG UI tests).
2. **Until CMP-002, the app shows it as one fixed stack**: Settings › Visual › "Camera" = camera
   layer with the circular spectrum layer on top, in its own compositor host. CMP-002 replaces the
   choice with user-built stacks.
3. **Privacy defaults** (spec 033, "Privacy review"): the permission is asked only when the user
   chooses Camera; the camera runs only while Camera is shown, running and in the foreground;
   the choice is not restored at launch; pictures stay in memory, are never stored, sent or
   analysed (no Vision); the status bar is not hidden while the camera runs, so iOS's indicator
   stays visible. The App Store privacy answers stay "Data Not Collected" (on-device use only); the
   owner confirms them in App Store Connect.
4. **Denial never blocks**: the layer shows its transparent fallback, the spectrum keeps running,
   and a banner explains how to allow access in Settings.

## Consequences

- The app gains `NSCameraUsageDescription` and an optional camera permission.
- Real-camera behaviour (prompt, revocation, interruption, orientation, thermal) is verified only
  in the device stage.
- Later CAM rows (front camera, lenses, exposure, focus, white balance) extend the provider; any
  image analysis needs its own specification and privacy review.

## Amendment 2026-11-14: front camera and mirror (CAM-002)

Decided by Claude under owner rule 4; `specs/096-cam-002-front-camera-layer`. No default is
overridden, so this amends ADR-0017 instead of opening a new ADR.

5. **One camera visual, two positions.** The Camera visual gains a stored setting "Camera: Back /
   Front" (`settings.camera.position`, default back) in a Settings "Camera" section. The camera
   layer kind still allows one instance, so one capture session, one badge and one Stop camera.
   The Camera choice itself stays session only; the position never starts the camera.
6. **The mirror lives in the camera layer only.** `CameraPictureGeometry.mirrored` (and the same
   arithmetic in the shader) flips the upright picture left to right with the crop centered. The
   screen, Save Frame (REC-001), Record (REC-003) and the external display (OUT-001) all read the
   one composite, so they always agree; layers drawn above (the spectrum) are not flipped.
   Defaults: on for the front camera, off for the rear, each stored
   (`settings.camera.mirrorFront`, `settings.camera.mirrorBack`). `AVCaptureConnection` mirroring
   is not used.
7. **Switching never shows the previous camera.** Every picture carries the position it came
   from and the layer draws only pictures of the chosen camera; the AV provider swaps the running
   session's input inside begin/commitConfiguration and reopens its picture slot only after the
   video queue has drained. The audio source is untouched.
8. **Privacy text.** The badge reads "Front camera on" for the front camera; the usage
   description now names both cameras and says a picture is saved only when the user saves a
   frame or records. App Store answers stay "Data Not Collected".
