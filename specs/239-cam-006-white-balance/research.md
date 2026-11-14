# Research: CAM-006 Camera White Balance

## CAM-006-D1 — Which AVFoundation calls

- **Decision**: capability `isWhiteBalanceModeSupported(.locked)`; read `whiteBalanceMode`,
  `deviceWhiteBalanceGains`, `maxWhiteBalanceGain`; lock with
  `setWhiteBalanceModeLocked(with:completionHandler: nil)` when
  `isLockingWhiteBalanceWithCustomDeviceGainsSupported`, else `whiteBalanceMode = .locked`; release
  with `whiteBalanceMode = .continuousAutoWhiteBalance`. All between `lockForConfiguration` and
  `unlockForConfiguration`, on the provider's session queue.
- **Rationale**: Apple documents that gains passed to `setWhiteBalanceModeLocked(with:)` must be in
  1.0…`maxWhiteBalanceGain` per channel or an exception is raised, and that `deviceWhiteBalanceGains`
  can briefly report values outside that range; clamping first is the documented way to stay valid.
  Locking with the clamped current gains holds what the user sees.
- **Alternatives**: `whiteBalanceMode = .locked` only (also valid, but the held gains are whatever the
  system has at that instant; used as the fallback); the `currentWhiteBalanceGains` sentinel (no
  validation possible in tests).

## CAM-006-D2 — Validation rule

- **Decision**: `CameraWhiteBalanceGains.validated(maximum:)`: nil when the maximum is not finite or
  below 1, or any channel is not finite; otherwise each channel clamped to 1…maximum.
- **Rationale**: out-of-range finite values are a known reporting quirk and clamping keeps the
  picture closest to what is shown; NaN/infinity carry no usable color and are refused.
- **Alternatives**: refusing all out-of-range values (would make the lock fail on a common quirk).

## CAM-006-D3 — Lifecycle

- **Decision**: release wherever CAM-004 releases exposure (`releaseExposure` in both providers runs
  before every input removal and on every stop and failure); interruptions do not release (the
  session and device stay), and the state is read back with the exposure when the camera runs again.
- **Rationale**: one place for all lock teardown; identical rules for every lock the user can make.
- **Alternatives**: a separate release path (risk of drift between the locks).

## CAM-006-D4 — Stand-in

- **Decision**: `FakeCameraWhiteBalanceDevice` per camera in `FakeCameraCaptureSession`
  (`whiteBalanceLockCameras` chooses which can lock), with settable reported gains, maximum and
  custom-gain support, and counters `configurations`, `changesOutsideConfiguration`,
  `invalidGainsApplied` (an invalid gain is refused, as AVFoundation would raise). DEBUG argument
  `-uitestCameraWhiteBalanceLock <list|none>`.
