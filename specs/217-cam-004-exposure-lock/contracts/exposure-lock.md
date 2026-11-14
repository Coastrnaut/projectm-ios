# Contract: CAM-004 exposure lock

## C1 — `CameraExposureConfiguring` (CameraLayer, platform-free)

```swift
public protocol CameraExposureConfiguring: AnyObject {
    func supportsExposure(_ mode: CameraExposureMode) -> Bool
    var currentExposureMode: CameraExposureMode { get }
    func beginExposureConfiguration() -> Bool   // false: configuration could not be taken
    func applyExposureMode(_ mode: CameraExposureMode)
    func endExposureConfiguration()
}
```

`AVCaptureDevice` (iOS) and `FakeCameraExposureDevice` conform.

## C2 — `CameraExposureControl`

- `lock(_:)`: unsupported → returns the read-back mode with no `begin` call; else begin, apply
  `.locked`, end; returns the read-back mode. Never throws or traps; `end` always follows a
  successful `begin`.
- `release(_:)`: not locked → no configuration; else begin, apply `.continuousAuto` (supported) or
  leave the mode, end; returns the read-back mode.

## C3 — Provider (`CameraFrameProvider` additions, main thread)

- `exposure: CameraExposureState`, `onExposureChange`, `setExposureLocked(_:)`.
- Defaults for providers without exposure: `canLock` false, no-op.
- Lens or position switch: release before the input is removed; stop/failure: release, then
  `notRunning`. Each change is reported once through `onExposureChange`.

## C4 — Settings row

- Identifier `cameraExposureLock` (Toggle, label "Lock exposure"), explanation text identifier
  `cameraExposureNote`.
- Unsupported: disabled, "This camera can't lock exposure."; supported but not running: disabled,
  "Exposure can be locked while the camera is running."; running and supported: enabled, no note.
