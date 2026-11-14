# Research: CAM-013 Camera Failure Recovery

## CAM-013-D1: What iOS reports, and how each event maps to a reason

- **Decision**: `AVCaptureSession.wasInterruptedNotification` carries
  `AVCaptureSessionInterruptionReasonKey` (an `AVCaptureSession.InterruptionReason` raw value).
  Mapping: `videoDeviceInUseByAnotherClient` and `audioDeviceInUseByAnotherClient` →
  `anotherApp`; `videoDeviceNotAvailableWithMultipleForegroundApps` → `multitasking`;
  `videoDeviceNotAvailableDueToSystemPressure` → `systemPressure`;
  `videoDeviceNotAvailableInBackground` → `background`; anything else or no key (future reasons)
  → `otherInterruption`. `runtimeErrorNotification` carries `AVCaptureSessionErrorKey` (an
  `AVError`): code `mediaServicesWereReset` → `mediaServicesReset`; anything else →
  `runtimeError`.
- **Rationale**: these are the documented keys; the mapping is a static function, unit-tested.
- **Alternatives**: one generic "paused" state (today; gives the user no reason).

## CAM-013-D2: Automatic return after an interruption

- **Decision**: Every interruption returns by itself when `interruptionEndedNotification` arrives;
  the provider keeps its session through an interruption. Contention included.
- **Rationale**: AVFoundation resumes an interrupted session by itself when the camera becomes
  available again (Apple's AVCam sample only hides its "camera unavailable" label on the end
  notification). Holding the picture back after contention would leave a running session whose
  picture is hidden: iOS's green indicator on, the in-app badge off — worse for privacy than
  resuming. The user chose the Camera visual and is still on it.
- **Alternatives**: wait for Retry after contention (needs stopping the session on interruption;
  rejected above); stop the session on every interruption (loses the system's own resume).

## CAM-013-D3: Retry and backoff

- **Decision**: Retry = full stop and start (new session, permission re-checked). Attempts in a
  row: first at once, then 2, 4, 8, 16, 30 (cap) seconds after the previous attempt; a tap inside
  the wait becomes one pending retry (the button reads "Retrying…", disabled). The count resets
  after 10 s of running or when the camera is stopped by the user or the app (pause, background,
  presentation loss, scene, leaving the visual). A camera switch is not a retry and has no
  backoff. The clock is `ProcessInfo.systemUptime` (monotonic), injected for tests.
- **Rationale**: exponential backoff with a cap is the standard guard against a tight restart
  loop; a first attempt at once keeps the common case (contention ended, user taps) instant.
- **Alternatives**: a fixed delay (slow for the common case); no limit (a broken camera loops).

## CAM-013-D4: Runtime errors

- **Decision**: On a runtime error the provider stops and releases its session at once (state
  stays `failed`, reason kept), so iOS's indicator turns off. A media services reset is retried
  once automatically (through the backoff); other errors wait for Retry.
- **Rationale**: a session stops running after a runtime error; Apple's AVCam sample restarts the
  session only for `mediaServicesWereReset`. Releasing the session keeps the indicator honest
  and makes the Retry a clean start.
- **Alternatives**: keep the stopped session (today: a dead session held until the visual is
  left).

## CAM-013-D5: Permission revocation

- **Decision**: No in-app handling while running: iOS terminates an app whose camera (or other
  privacy) permission is turned off in Settings. Apple Developer Forums: thread 720006 (an Apple
  engineer: expected behaviour; save enough state to restore the UI on relaunch) and thread
  64740 (Springboard terminates the app on a privacy change). A running process would not see the
  new status anyway. The next start (launch and choice of Camera, Retry, camera switch) reads
  `.denied` and shows FILE-013's denied notice with Open Settings. The Camera choice is never
  restored at launch (CAM-001), so the relaunch shows the previous non-camera visual; the user
  chooses Camera again and sees the denied notice.
- **Rationale**: documented platform behaviour; verified on a device in CAM-013-T17.
- **Alternatives**: polling authorization (useless: the process is ended).

## CAM-013-D6: Background, multitasking and heat

- **Decision**: No change. The host stops the camera on `didEnterBackground` and starts it on
  return (CAM-001-R7); AUD-015 keeps only audio in the background, and `UIBackgroundModes` has no
  camera mode (none exists). `isMultitaskingCameraAccessEnabled` stays off (iPad Split View
  interrupts the camera with `multitasking`). Thermal state lowers only the visual's own rate and
  scale (FR-049); system pressure that stops the camera arrives as `systemPressure`.
- **Rationale**: the conservative path; multitasking camera access and frame-rate throttling on
  pressure need device measurement and are separate decisions.

## CAM-013-D7: Announcements

- **Decision**: The notice text is announced through `AccessibilityAnnouncer.announce(_:kind:)`
  with a new kind `.camera` (its own lane, so a camera change never swallows a preset or playback
  announcement). ACC-011, built in parallel, adds the same `.camera` kind and moves camera
  announcements into its status-event router; at integration the router keeps the reason text
  (it reads the notice the coordinator shows).
- **Rationale**: one shared, rate-limited path (ACC-004-R7); no direct `UIAccessibility.post`.
