# Data Model: CAM-013 Camera Failure Recovery

## CameraStopReason (package `CameraLayer`, plain Swift)

| Case | Feed state | Returns when ended | App retries by itself | Notice |
|---|---|---|---|---|
| `anotherApp` | interrupted | yes | no | "Another app is using the camera. It comes back when the camera is free, or tap Retry." |
| `multitasking` | interrupted | yes | no | "The camera pauses while apps share the screen. It comes back in full screen, or tap Retry." |
| `systemPressure` | interrupted | yes | no | "The camera paused because the device is too warm or busy. It comes back when the device recovers, or tap Retry." |
| `background` | interrupted | yes | no | "The camera paused while the app was in the background." |
| `otherInterruption` | interrupted | yes | no | "The camera is paused by the system. It comes back when the camera is free, or tap Retry." |
| `mediaServicesReset` | failed | no | once | "The camera stopped after a system reset. Tap Retry to start it again." |
| `runtimeError` | failed | no | no | "The camera stopped because of an error. Tap Retry to start it again." |

Raw values are the case names (diagnostic keys and DEBUG injection names).

## CameraRecovery (package, plain Swift value)

| Field | Meaning |
|---|---|
| `attempts` | retries in a row since the last reset |
| `lastAttemptAt` | seconds (caller's monotonic clock) of the last retry |
| `runningSince` | when the feed last became running; nil otherwise |
| `autoRetryUsed` | the one automatic retry of this run of failures was used |
| `counts` | per `CameraStopReason`, how many times it happened (session) |
| `retries` | retries performed (session) |

Rules: `backoff = [0, 2, 4, 8, 16, 30]`; the wait before the next attempt is
`backoff[min(attempts, 5)]` after `lastAttemptAt`; a failure after at least 10 s of running, or
`reset()`, sets `attempts = 0` and `autoRetryUsed = false`; `reset()` keeps the counts.

## State transitions (feed, with reason)

```text
running --interruption(reason)--> interrupted(reason) --ended--> running
running|interrupted|starting --runtime error(kind)--> failed(kind)  [session released]
interrupted|failed --Retry--> idle --> (start) running | denied | restricted | unavailable | interrupted | failed
any --stop (user, pause, background, scene, presentation loss)--> idle  [reason cleared, pending retry cancelled, recovery reset]
```

## Host and coordinator additions (app)

- `CameraVisualHost.stopReason`, `retryPending`, `recovery` (read only), `retryCamera()`,
  `recoveryProbe` ("<state>|<reason or none>|<attempts>|<pending yes/no>|<retries>").
- `AppCoordinator.cameraStopReason`, `cameraRetryPending`, `retryCamera()`.
- `PermissionNotice.offersRetry` (false by default).
