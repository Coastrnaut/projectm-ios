# Data model: CAM-006 Camera White Balance

All values are session state; nothing is stored (CAM-006-R10).

- **CameraWhiteBalanceMode**: `locked`, `continuousAuto`, `other` (any other mode the camera reports,
  e.g. single automatic adjustment).
- **CameraWhiteBalanceGains**: `red`, `green`, `blue` (Float). `validated(maximum:)` → clamped copy or
  nil (CAM-006-D2). `isValid(maximum:)`: every channel finite and within 1…maximum.
- **CameraWhiteBalanceState**: `canLock` (Bool), `isRunning` (Bool), `mode` (read back;
  `continuousAuto` while not running). Derived: `isLocked` = running and `locked`; `isAdjustable` =
  `canLock` and running. `notRunning(canLock:)`.

State transitions (running camera that can lock): continuousAuto —lock→ locked —release→
continuousAuto; locked —interruption→ (not running, mode kept on the device) —end→ locked;
locked —lens/position switch or stop→ continuousAuto on that device.
