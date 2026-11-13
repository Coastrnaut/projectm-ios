# Research: CAM-001 Rear Camera Layer

Decisions taken 2026-11-13 under the owner's best-judgement rule (owner rule 4).

## CAM-001-D1: Where the camera layer lives and how the app shows it

- **Decision**: Target `CameraLayer` in `Packages/Compositor`; in the app a session-only Visual
  choice "Camera" whose host runs a `Compositor` with [camera layer, circular spectrum layer].
- **Rationale**: The app does not render through the compositor yet; one small host is the minimum
  honest path to make the acceptance observable on screen. Putting the spectrum on top keeps it a
  music visualizer and exercises a two-layer stack. The target sits beside `SpectrumLayers` so CI's
  package loops cover it without workflow changes.
- **Alternatives**: a camera-only visual (no music; rejected); the camera behind every visual
  (projectM is not a compositor layer in the app yet; rejected, CMP-002); a new package (more CI
  wiring for no gain).

## CAM-001-D2: Color conversion

- **Decision**: Request `kCVPixelFormatType_32BGRA` buffers and wrap them through
  `CVMetalTextureCache` as `.bgra8Unorm_srgb`, so sampling decodes the sRGB transfer to linear in
  hardware; alpha is 1, so premultiplication is the identity. The stub uses the same texture format.
- **Rationale**: The camera's BGRA output is display-encoded (sRGB/Rec. 709 primaries, close to the
  sRGB curve); hardware decode costs nothing and matches the contract (linear sRGB primaries).
  Test: a stub byte value 188 reads back as about 0.503 linear (sRGB EOTF), within 1/255.
- **Alternatives**: YUV (420f) with a shader matrix (less bandwidth, more code and a range/matrix
  choice to verify on device; deferred); shader-side decode (same result, more code).

## CAM-001-D3: Geometry (aspect fill and orientation)

- **Decision**: The provider reports each picture's clockwise rotation (0/90/180/270) needed to make
  it upright. A CPU function maps output UV to camera UV: rotate the picture's size, scale to fill
  (crop the overflow equally), then rotate the coordinates. The shader receives four floats
  (scale, offset) and the rotation as a uniform via `setFragmentBytes` (no buffer allocation).
- **Rationale**: Rotation in the sampler avoids AVFoundation rotating buffers (cost) and keeps the
  layer deterministic and testable with a striped stub (only the middle stripe survives a fill).
  The real provider derives the rotation from `AVCaptureDevice.RotationCoordinator`
  (`videoRotationAngleForHorizonLevelCapture`), read on the main thread and stored atomically.
- **Alternatives**: `AVCaptureConnection.videoRotationAngle` (rotated buffers, extra copies).

## CAM-001-D4: Session configuration

- **Decision**: `AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)`;
  preset `.hd1280x720` when supported, else `.medium`; `AVCaptureVideoDataOutput` with
  `alwaysDiscardsLateVideoFrames = true`, BGRA, its own serial queue; no audio input; no photo or
  movie output; nothing is written anywhere. `startRunning`/`stopRunning` run on a private serial
  session queue (they block). Interruption (`AVCaptureSession.wasInterruptedNotification`,
  `interruptionEndedNotification`) and `runtimeErrorNotification` map to `interrupted` / `failed`
  and drop the latest picture; an interruption's end restores `running`.
- **No camera**: checked before authorization, so a device without a back camera (and the
  simulator) never shows a permission prompt (CAM-001-R6).
- **Authorization**: `authorizationStatus(for: .video)`; `.notDetermined` → `requestAccess` (only
  reached from `start()`, which only the user's Camera choice triggers); denied/restricted map to
  their states.

## CAM-001-D5: Threading and memory

- **Decision**: `LatestCameraFrame`, a small class with an `OSAllocatedUnfairLock`, holds the newest
  `CameraFrame` (texture, size, rotation, sequence number). The capture queue replaces it; the
  render thread reads it with `withLockIfAvailable` (a try-lock): on contention it reuses the
  picture it used last frame, so `render` never waits (CMP-001 contract). Stopping clears the slot
  and flushes the texture cache, so no picture is kept (CAM-001-R9).
- **Rationale**: CoreVideo owns the per-frame wrappers; the layer allocates nothing per frame.

## CAM-001-D6: Lifecycle (when the camera runs)

- **Decision**: `CameraVisualHost.resume()` starts the provider and the frame loop;
  `pause()` and `suspendForPresentationLoss()` stop both. `AppCoordinator` calls `resume()` only from
  `resumeActiveVisual()` when Camera is shown, and `pause()` from `pauseActiveVisual()`, which every
  stop path already calls (pause, Stop, background via LifecycleCoordinator, presentation loss).
  Choosing another visual releases the host (provider stopped, picture dropped). The host also
  observes `UIScene.didDisconnectNotification` and stops at once.
- **Status bar**: `hidesSystemOverlays` is false while Camera is shown (CAM-001-R10).

## CAM-001-D7: Testing without a camera

- **Decision**: `StubCameraFrameProvider(scenario:)` with scenarios `granted`, `notDeterminedGrant`,
  `notDeterminedDeny`, `denied`, `restricted`, `unavailable`, plus `interrupt()`/`endInterruption()`
  and `fail()`; it creates its picture once in `start()`. DEBUG launch flag `-uitestCamera
  <scenario>` puts it in the app; release builds always use `AVCameraFrameProvider`. Tests never
  call the real authorization request. A simulator unit test may construct `AVCameraFrameProvider`
  only to check that, with no back camera, `start()` reports `unavailable` without asking.

## CAM-001-D8: No Vision

- **Decision**: No Vision or any other image analysis in this row (CAM-001-R9). The roadmap's
  "Vision, CoreMotion" tech note covers later CAM rows; each needs its own privacy review.
