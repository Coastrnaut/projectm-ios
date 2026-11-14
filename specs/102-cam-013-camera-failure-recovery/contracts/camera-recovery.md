# Contract: Camera recovery (CAM-013)

## C1 — Provider

- `CameraFrameProvider.stopReason: CameraStopReason?` (main thread). Non-nil only while `state` is
  `interrupted` or `failed`; set before `onStateChange` fires for that state; nil after `stop()`
  and when running. Default implementation: nil.
- `StubCameraFrameProvider`:
  - `interrupt(_ reason: CameraStopReason = .otherInterruption)`: running or starting →
    `interrupted`, picture dropped. A failure reason is ignored here.
  - `endInterruption()`: `interrupted` → `running`, picture stored again.
  - `fail(_ reason: CameraStopReason = .runtimeError)`: running, starting or interrupted →
    `failed`, slot closed (picture dropped).
  - `withdrawAccess()`: later starts find access denied (revocation as iOS delivers it: at the
    next start).
- `AVCameraFrameProvider`: `static func stopReason(interruption: AVCaptureSession.InterruptionReason?)`
  and `static func stopReason(error: AVError.Code?)` (research CAM-013-D1); a runtime error
  releases the session.

## C2 — Feed state

- `CameraFeedState.offersRetry` is true exactly for `interrupted` and `failed`.
- `notice(position:reason:)`: the reason's notice when the state is `interrupted` or `failed` and
  a reason is given; otherwise `notice(position:)`.

## C3 — Host

- `retryCamera()`: ignored unless the loop runs, the user has not stopped the camera and the feed
  offers Retry; runs at once when the backoff allows, else holds one pending retry (later taps
  ignored) that runs when the wait ends. A retry is `stop()` + `start()` of the camera.
- A `failed(mediaServicesReset)` triggers one automatic `retryCamera()` per run of failures.
- Any stop of the loop and `stopCamera()` cancel the pending retry and reset the recovery.

## C4 — UI

- The camera notice (identifier `cameraNotice`, text `cameraNoticeText`) shows the reason text; when
  `offersRetry`, a button `cameraRetry`: title "Retry" (label "Retry camera"), or "Retrying…"
  (label "Retrying camera", disabled) while a retry waits. Denied/restricted: `cameraOpenSettings`,
  no Retry.
- The "Camera on" badge is shown only for starting and running (CAM-012, unchanged).
- Announcement: the notice text through `AccessibilityAnnouncer` kind `.camera`.

## C5 — DEBUG injection (`-uitestCameraEvents`, with `-uitestCamera <scenario>`)

Buttons `camera:interrupt:<reason>` (each interruption reason), `camera:end`,
`camera:fail:runtimeError`, `camera:fail:mediaServicesReset`, `camera:withdraw`; hidden value
`cameraRecovery` = the host's `recoveryProbe`. Release builds contain none of this.
