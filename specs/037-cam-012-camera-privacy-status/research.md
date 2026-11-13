# Research: CAM-012 Camera Privacy Status

## CAM-012-D1: What drives the indicator

- **Decision**: The camera feed state that the provider reports through
  `CameraVisualHost.onFeedStateChange` into `AppCoordinator.cameraState` (already the source of
  CAM-001's notice). Shown for `.starting` and `.running`; hidden for every other state.
- **Rationale**: It is the provider's own state, set synchronously by `start()`/`stop()` and by
  the interruption observers, so the badge cannot outlive the session or appear before it. The
  visual choice alone would show "Camera on" while denied or paused.
- **Alternatives**: `host.isRunning` (the frame loop; true while denied too); the visual choice.

## CAM-012-D2: How Stop stops

- **Decision**: `CameraVisualHost.stopCamera()` sets a `cameraStoppedByUser` flag, then calls
  `CameraLayerSource.stop()` (drops the held picture, calls the provider's `stop()`: slot closed,
  picture dropped, state `.idle`, reported synchronously). `updateLoop()` never starts the camera
  again while the flag is set. The coordinator then sets `settings.visual` to the fallback and
  calls `visualSettingsChanged()`, which releases the host (its `pause()` and `deinit` call
  `stop()` again, a no-op on an idle provider) and resumes the fallback visual.
- **Rationale**: The camera is off before anything else happens (R4), and the switch reuses the
  tested Settings path, so no new visual lifecycle is introduced. AVFoundation's `stopRunning`
  stays on the provider's session queue (CAM-001): waiting for it on the main thread could freeze
  the picture, which the acceptance forbids.
- **Alternatives**: keep the Camera visual with the camera off (rejected in Clarifications);
  `sessionQueue.sync { stopRunning() }` (blocks the main thread up to hundreds of ms).

## CAM-012-D3: Fallback visual

- **Decision**: `AppSettings.visualBeforeCamera`: the stored `settings.visual` key (Camera never
  writes it, CAM-001-R11), projectM when absent or unreadable. Assigning it rewrites the same
  value, so no new state is stored.
- **Alternatives**: always Circular Spectrum (overwrites the user's stored choice).

## CAM-012-D4: No-freeze test without wall-clock asserts

- **Decision**: The host counts composited frames (`framesComposited`, an `Int` incremented after
  `commit()`, no allocation). The unit test hosts the view in a window of the test host's scene,
  waits with an expectation (generous 10 s ceiling) for the count to advance, taps Stop through
  `stopCamera()`, and waits again for it to advance with the camera idle and `framesShown`
  unchanged. After the coordinator's switch the fallback is a different host; the UI test checks
  that it is on screen and the controls respond.
- **Alternatives**: timing a frame interval (wall clock, flaky on a shared Mac).

## CAM-012-D5: Placement and accessibility

- **Decision**: A capsule at the top of the visualizer, above the banners, inside the safe area:
  camera symbol + "Camera on" + a "Stop camera" button. Container identifier `cameraIndicator`,
  label "Camera on", value "Live"/"Starting"; button identifier `stopCamera`, label "Stop camera".
  Stopping posts the VoiceOver announcement "Camera off".
- **Rationale**: Top of screen is where iOS shows its own indicator; the controls sit at the
  bottom, so the two never overlap.
