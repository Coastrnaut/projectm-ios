# Contract: CAM-006 white balance lock

## C1 — `CameraWhiteBalanceConfiguring` (CameraLayer, platform-free)

```swift
public protocol CameraWhiteBalanceConfiguring: AnyObject {
    func supportsWhiteBalance(_ mode: CameraWhiteBalanceMode) -> Bool
    var currentWhiteBalanceMode: CameraWhiteBalanceMode { get }
    var currentWhiteBalanceGains: CameraWhiteBalanceGains { get }
    var maximumWhiteBalanceGain: Float { get }
    var supportsLockingWithGains: Bool { get }
    func beginWhiteBalanceConfiguration() -> Bool   // false: configuration could not be taken
    func applyWhiteBalanceLocked(gains: CameraWhiteBalanceGains?)   // nil: lock in place
    func applyWhiteBalanceContinuous()
    func endWhiteBalanceConfiguration()
}
```

`AVCaptureDevice` (iOS) and `FakeCameraWhiteBalanceDevice` conform.

## C2 — `CameraWhiteBalanceControl`

- `lock(_:)`: unsupported or already locked → no `begin`; with custom gains supported, the current
  gains are validated first and a refusal (nil) means no `begin`; else begin, apply, end. Returns the
  read-back mode. Never throws or traps; `end` always follows a successful `begin`; gains passed are
  always valid.
- `release(_:)`: not locked or continuous unsupported → no configuration; else begin, apply
  continuous, end; returns the read-back mode.
- `state(of:)`: the running device's state.

## C3 — Provider (`CameraFrameProvider` additions, main thread)

- `whiteBalance: CameraWhiteBalanceState`, `onWhiteBalanceChange`, `setWhiteBalanceLocked(_:)`.
- Defaults for providers without white balance: `canLock` false, no-op.
- Lens or position switch: release before the input is removed; stop/failure: release, then
  `notRunning`; interruption: no release, read back when running again.

## C4 — Settings row

- Identifier `cameraWhiteBalanceLock` (Toggle, label "Lock white balance"), note identifier
  `cameraWhiteBalanceNote`.
- Unsupported: disabled, "This camera can't lock white balance."; supported but not running:
  disabled, "White balance can be locked while the camera is running."; running and supported:
  enabled, no note; the note is the VoiceOver hint.
