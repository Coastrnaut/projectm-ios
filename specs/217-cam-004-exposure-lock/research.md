# Research: CAM-004 Camera Exposure Lock

## CAM-004-D1 — Which AVFoundation controls

- **Decision**: `AVCaptureDevice.isExposureModeSupported(.locked)` decides support;
  `exposureMode = .locked` locks, `.continuousAutoExposure` releases (when supported, else
  `.autoExpose`), each inside `lockForConfiguration()` / `unlockForConfiguration()`; the mode is read
  back from `exposureMode` afterwards.
- **Rationale**: the documented way to change device configuration; `lockForConfiguration` can throw
  (device in use), so a failure must leave the state unchanged and be reported as read back.
- **Alternatives**: `.custom` with `setExposureModeCustom(duration:iso:)` (out of scope, flashing
  risk); exposure bias (out of scope, Clarifications).

## CAM-004-D2 — Where the code runs

- **Decision**: one platform-free routine `CameraExposureControl` over a protocol
  `CameraExposureConfiguring`, conformed to by `AVCaptureDevice` (iOS) and `FakeCameraExposureDevice`.
  The real provider calls it on its private session queue, reading the device from the session's
  input, and posts the read-back state to the main thread; the stand-in calls it synchronously.
- **Rationale**: mirrors CAM-003-D2 (`CameraInputSwitch`); the Mac tests exercise the same routine;
  device configuration is serialized with session reconfiguration.
- **Alternatives**: calling AVFoundation from the main thread (can block on a busy device).

## CAM-004-D3 — Lens and position switches, stops

- **Decision**: before a switch removes the input, the old device is released to continuous
  automatic exposure on the same queue; the new device is read back (it starts automatic). On stop
  and on a runtime failure the device is released before `stopRunning`; the published state returns
  to "not running" at once.
- **Rationale**: devices are process-wide objects; a lock left on a removed device would come back
  locked on the next start (CAM-004-R6, R7).

## CAM-004-D4 — Capability while not running

- **Decision**: the provider reports the current camera's capability without starting it (the real
  provider asks the `AVCaptureDevice` for the chosen position/lens; no authorization is needed to
  read device properties); the state's mode is "not running" until a start.
- **Rationale**: the unsupported explanation can show even before the camera runs; the switch is
  enabled only while running (CAM-004-R2).

## CAM-004-D5 — Stand-in arguments

- **Decision**: DEBUG `-uitestCameraExposureLock <list|none>`: the stand-in cameras that can lock
  (lens raw values and `front`); default: every camera can lock.
- **Rationale**: one argument covers supported, unsupported and mixed (lens switch) cases.
