# ADR-0017: Rear Camera Layer

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CAM-001 (`specs/033-cam-001-rear-camera-layer`)
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
