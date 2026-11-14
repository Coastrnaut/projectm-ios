# Implementation Plan: CAM-013 Camera Failure Recovery

**Branch**: `feature/cam-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/102-cam-013-camera-failure-recovery/spec.md`

## Summary

The camera layer already draws nothing unless the feed is running (CAM-001-R8), so the picture is
cleared on every interruption and error today. CAM-013 adds what is missing around it: the reason,
a Retry with backoff, automatic recovery after a media reset, a released session after an error,
counts, and stand-in injection for every event.

In `Packages/Compositor` (target `CameraLayer` only; plain Swift files build on Linux):

- New `CameraStopReason` (`CameraStopReason.swift`): `anotherApp`, `multitasking`,
  `systemPressure`, `background`, `otherInterruption`, `mediaServicesReset`, `runtimeError`; each
  with its feed state (`interrupted` or `failed`), notice text (spec Clarifications), whether the
  system brings the camera back (`resumesWhenEnded`: every interruption) and whether the app
  retries by itself (`retriesAutomatically`: media reset only). Research CAM-013-D1, D2.
- New `CameraRecovery` (`CameraRecovery.swift`): a pure value on caller-supplied seconds
  (monotonic): attempts in a row, last attempt time, running-since, the one automatic retry,
  counts per reason and of retries; `delayBeforeNextAttempt(now:)` from the backoff table
  0, 2, 4, 8, 16, 30 s; resets after 10 s of running. Research CAM-013-D3.
- `CameraFeedState`: `offersRetry` (interrupted or failed), `notice(position:reason:)`; the generic
  `interrupted` text gains "or tap Retry"; `failed` gets its own text ("stopped because of an
  error"), which no longer promises a return.
- `CameraFrameProvider.stopReason` (default nil). `StubCameraFrameProvider`: `interrupt(_:)`,
  `endInterruption()`, `fail(_:)`, `withdrawAccess()` set the reason before the state changes.
  `AVCameraFrameProvider`: maps `AVCaptureSessionInterruptionReasonKey` and the runtime error's
  `AVError.Code` to a reason (`static stopReason(interruption:)`, `stopReason(error:)`); on a
  runtime error it tears the session down (stops it, drops the cache and observers) and stays
  `failed`, so iOS's indicator goes off (research CAM-013-D4). Interruptions keep the session
  (the system resumes it; research CAM-013-D2).

In the app:

- `CameraVisualHost`: owns a `CameraRecovery`, an injectable clock and scheduler (tests: fake
  clock, manual scheduler). `retryCamera()` runs at once or holds one pending retry until the
  backoff ends (`retryPending`); a retry is `camera.stop()` + `camera.start()`. A media reset
  triggers one automatic retry. Any loop stop (pause, background, presentation loss, scene) and
  Stop camera cancel a pending retry and reset the recovery (CAM-013-R6, R11). `stopReason`,
  `recoveryProbe` for DEBUG.
- `AppCoordinator`: `cameraStopReason`, `cameraRetryPending`, `retryCamera()`; the notice change is
  announced through `announcer.announce(_:kind: .camera)` (ACC-004's path; ACC-011 adds the same
  `.camera` kind and routes it through its status-event router at integration).
- `PermissionNotice.offersRetry`; `PermissionCatalog.cameraNotice(for:position:reason:)`;
  `PermissionNoticeView` gains optional `onRetry` and `retryPending` (button `<prefix>Retry`,
  "Retry"/"Retrying…", VoiceOver "Retry camera"/"Retrying camera"). Denied and restricted keep
  Open Settings without Retry.
- DEBUG: `UITestCameraEventPanel` (`-uitestCameraEvents`): buttons inject each event into the
  stand-in; hidden readout `cameraRecovery`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/camera-recovery.md](contracts/camera-recovery.md); checks: [quickstart.md](quickstart.md);
decision record: ADR-0017 amendment (decisions 11-14; no default overridden).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: AVFoundation (notification keys only), Compositor, SwiftUI. No new
dependency, no networking.

**Storage**: none. Counts are in memory for the session.

**Testing**: `Packages/Compositor`: `CameraRecoveryTests` (reason table, backoff on a fake clock,
auto-retry rule, counts; Linux shape) and pixel tests in `CameraLayerTests` (each reason clears
the composite, end and restart bring pixels back). App: `CameraRecoveryTests` (host composite
before/after an injected interruption and Retry, the table with notice/badge/Retry, runtime error
then recovery, media reset auto-retry, backoff with a fake clock, denied at start, background,
AV reason mapping). UI: `CameraRecoveryUITests` with `-uitestCamera granted -uitestCameraEvents`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package target.

**Performance Goals**: nothing per frame: recovery runs only on state changes.

**Constraints**: public APIs only; explicit closure types; typed steps for strings and numbers; no
C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions (fake clock);
unit tests about 1-2 s, UI test under 30 s (owner rule 7). Parallel work: ACC-011 (status events,
app views; keep edits to `VisualizerView`, `PermissionNoticeView`, `AccessibilityAnnouncer` and
`cameraStateChanged` small), CMP-006 (Compositor outside `CameraLayer`), a test-budget agent
(`DynamicTypeInspectorUITests`, `SessionRecoveryUITests`: not touched).

**Scale/Scope**: 2 new package sources, about 9 files touched, 1 debug panel, 3 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | `AVCaptureSession` notifications and documented keys, `AVError.Code` | Pass |
| VI Modular boundaries | Rules are a pure value in `CameraLayer`; the host executes them; views only show | Pass |
| VII Real-time safety | No audio-thread change; recovery runs on the main thread on state changes | Pass |
| X Evidence | Simulator stand-in only; real interruptions on D1-D2 are `{device}` tasks | Pass |
| Privacy | A stale picture is never shown; counts are numbers in memory; nothing stored or sent; the camera restarts only where it already ran | Pass |
| No networking | None; `check_compliance.py` | Pass |
| Accessibility (ACC-001, ACC-004) | The notice and Retry have labels; announcement via the shared announcer; no new animation (`check_motion_policy.py`) | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/102-cam-013-camera-failure-recovery/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/camera-recovery.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/CameraLayer/
├── CameraStopReason.swift        # new
├── CameraRecovery.swift          # new
├── CameraFeedState.swift         # offersRetry, notice(position:reason:), texts
├── CameraFrameProvider.swift     # stopReason
├── StubCameraFrameProvider.swift # injection
└── AVCameraFrameProvider.swift   # reason mapping, teardown on error
Packages/Compositor/Tests/CompositorTests/
├── CameraRecoveryTests.swift     # new
└── CameraLayerTests.swift        # + per-reason pixel clearing
Apps/projectM-iOS/
├── Visuals/CameraVisualHost.swift
├── Coordinators/AppCoordinator.swift, PermissionCatalog.swift, AccessibilityAnnouncer.swift
├── Views/PermissionNoticeView.swift, VisualizerView.swift
├── Debug/UITestCameraEventPanel.swift   # new
├── Tests/CameraRecoveryTests.swift      # new
└── UITests/CameraRecoveryUITests.swift  # new
docs/adr/0017-rear-camera-layer.md
```

**Structure Decision**: extend the existing `CameraLayer` target and the Camera visual host; no
new target.

## Complexity Tracking

None.
