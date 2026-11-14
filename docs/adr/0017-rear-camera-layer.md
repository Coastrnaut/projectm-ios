# ADR-0017: Rear Camera Layer

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CAM-001 (`specs/033-cam-001-rear-camera-layer`); amended by CAM-002 (`specs/096-cam-002-front-camera-layer`), CAM-007 (`specs/098-cam-007-camera-crop-and-rotation`) and CAM-013 (`specs/102-cam-013-camera-failure-recovery`)
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

## Amendment 2026-11-14: crop and rotation (CAM-007)

Decided by Claude under owner rule 4; `specs/098-cam-007-camera-crop-and-rotation`. The default
picture (aspect fill, centered crop) is unchanged, so this amends ADR-0017 instead of opening a
new ADR.

9. **A user crop in the same geometry.** `CameraCrop` = mode (Fill, default; Fit), anchor (Center,
   default; Top; Bottom) and zoom (1, default; 1.5; 2; 3), stored once for both cameras
   (`settings.camera.cropMode`, `settings.camera.cropAnchor`, `settings.camera.zoom`), never in
   scenes or cues. `CameraPictureGeometry` scales the upright, possibly mirrored picture by one
   factor (cover for Fill, contain for Fit, times the zoom) and places it with
   offset = (1 − visible) × anchor, so the anchor point of the picture always lands on the same
   relative point of the layer picture. The geometry is still rebuilt every frame from the
   picture's size, its rotation (from `AVCaptureDevice.RotationCoordinator`, unchanged) and the
   layer picture's size, so a portrait-to-landscape turn keeps the chosen crop by construction.
   Zoom is a crop in the layer, never the camera's own zoom; the capture session is untouched.
10. **Fit's bars are transparent.** Where Fit leaves the layer uncovered the camera layer is
    transparent (the shader's bounds test equals `CameraPictureGeometry.contains`); in the Camera
    visual they show the black background on screen, in saved frames and in recordings. The
    uniforms are unchanged (visible, offset, rotation and mirror already carry the transform).

## Amendment 2026-11-14: failure recovery (CAM-013)

Decided by Claude under owner rule 4; `specs/102-cam-013-camera-failure-recovery`. No default is
overridden (the camera still runs only while the Camera visual is shown, running and in the
foreground), so this amends ADR-0017 instead of opening a new ADR.

11. **Clear and explain.** An interruption or a runtime error draws no camera picture from the next
    frame (the layer is transparent; decision 4's fallback), and the non-blocking camera notice
    names the reason in plain words (`CameraStopReason`: another app, multitasking, system
    pressure, background, other interruption, media reset, other error) with a Retry button. The
    "Camera on" badge stays hidden unless the camera is starting or running.
12. **The system's return is followed.** Every interruption, contention included, resumes by itself
    when AVFoundation reports its end; the provider keeps its session through an interruption.
    Refusing to resume after contention would leave a running session with a hidden picture.
13. **Retry with backoff; one automatic retry.** Retry stops the camera completely and starts it
    again (permission re-checked). Attempts in a row wait 0, 2, 4, 8, 16, then 30 s; 10 s of
    running or any stop by the user or the app starts a new run. Only a media services reset is
    retried by itself, once. A runtime error releases the session at once, so iOS's indicator
    matches. Counts per reason and of retries are kept in memory as numbers only.
14. **Revocation and background.** iOS ends the app when camera access is turned off in Settings
    (Apple Developer Forums threads 720006 and 64740), so revocation is seen at the next start as
    the denied notice with Open Settings (FILE-013). The camera never runs in the background
    (AUD-015 unchanged); entering it cancels a waiting retry and the return starts afresh. Camera
    frame-rate throttling on pressure and iPad multitasking camera access stay off.
