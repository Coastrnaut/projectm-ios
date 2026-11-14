# Tasks: CAM-013 Camera Failure Recovery

**Input**: `specs/102-cam-013-camera-failure-recovery/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (CAM-013-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1-D3.

## Phase 1: Setup

- [ ] CAM-013-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "CAM13 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] CAM-013-T02 [P] `CameraStopReason` (seven cases, raw values the case names; `feedState`, `isInterruption`, `resumesWhenEnded`, `retriesAutomatically`, `notice` with the data-model texts built in typed steps) in `Packages/Compositor/Sources/CameraLayer/CameraStopReason.swift`
- [ ] CAM-013-T03 [P] `CameraRecovery` (backoff table 0, 2, 4, 8, 16, 30 s; `stableInterval` 10 s; `noteRunning(now:)`, `noteStop(_:now:)` counting and the stable reset, `delayBeforeNextAttempt(now:)`, `recordAttempt(now:)`, `claimAutomaticRetry(for:)`, `reset()`, `counts`, `retries`) in `Packages/Compositor/Sources/CameraLayer/CameraRecovery.swift`
- [ ] CAM-013-T04 `CameraFeedState.offersRetry`, `notice(position:reason:)`, the generic `interrupted` text with "or tap Retry" and the new `failed` text in `Packages/Compositor/Sources/CameraLayer/CameraFeedState.swift`; `CameraFrameProvider.stopReason` (default nil) in `CameraFrameProvider.swift`
- [ ] CAM-013-T05 Package tests `Packages/Compositor/Tests/CompositorTests/CameraRecoveryTests.swift` (plain Swift, also in the Linux shape): the reason table (feed state, texts, return rule, automatic retry, `offersRetry`, no case missing), backoff spacing 0, 2, 4, 8, 16, 30, 30 on a fake clock, ten requests in one second give one attempt, the stable reset after 10 s, one automatic retry per run of failures, counts (CAM-013-R6, R7, R10, R14, S3, S4)

## Phase 3: User Story 1 - Another app takes the camera, and I get it back (P1) — MVP

**Independent test**: inject an interruption into the stand-in: no camera pixels in the next composite, the notice with Retry; Retry or the end brings pixels back.

- [ ] CAM-013-T06 [US1] `StubCameraFrameProvider`: `stopReason`, `interrupt(_:)` (also from starting), `endInterruption()`, `fail(_:)` (closes the slot), `withdrawAccess()`; reason set before the state callback, cleared on running, stop and a camera switch (`select`), in `Packages/Compositor/Sources/CameraLayer/StubCameraFrameProvider.swift`
- [ ] CAM-013-T07 [US1] `AVCameraFrameProvider`: `stopReason`; `static stopReason(interruption:)` and `stopReason(error:)`; interruption keeps the session; a runtime error releases the session (stop running, observers removed, cache flushed) and stays `failed` with its reason; `select` clears the reason, in `Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift`
- [ ] CAM-013-T08 [US1] GPU tests in `Packages/Compositor/Tests/CompositorTests/CameraLayerTests.swift`: for every reason, a running stand-in composites camera pixels, the injected event makes the next composite all zero with the fallback outcome and `stopReason` set; the end (interruptions) or stop+start (errors) brings the pixels back on the next frame (CAM-013-R1, S1, S2)
- [ ] CAM-013-T09 [US1] `CameraVisualHost`: `CameraRecovery`, injectable `clock` and `scheduler`, `retryCamera()` (at once, or one pending retry), automatic retry after a media reset, `stopReason`, `retryPending`, `onRecoveryChange`, `recoveryProbe`; loop stops and `stopCamera()` cancel and reset, in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`
- [ ] CAM-013-T10 [US1] Coordinator and notice: `AppCoordinator.cameraStopReason`, `cameraRetryPending`, `retryCamera()`, the notice announced through `announcer.announce(_:kind: .camera)` (new kind in `AccessibilityAnnouncer.swift`); `PermissionNotice.offersRetry`, `PermissionCatalog.cameraNotice(for:position:reason:)`; `PermissionNoticeView` optional `onRetry`/`retryPending` (button `<prefix>Retry`, "Retry"/"Retrying…", labels "Retry camera"/"Retrying camera"); `VisualizerView` passes them, in `Apps/projectM-iOS/Coordinators/`, `Apps/projectM-iOS/Views/`
- [ ] CAM-013-T11 [US1] The acceptance in `Apps/projectM-iOS/Tests/CameraRecoveryTests.swift`: the host composited offscreen shows the stand-in's orange; an injected interruption → the next composite has zero orange pixels, the catalog notice offers Retry with the reason text, the badge is hidden; Retry → orange returns and the notice is gone; plus the table over every interruption reason (cleared frame, notice text, automatic return on end, badge hidden) (CAM-013-R1-R4, R9, S1-S3)
- [ ] CAM-013-T12 [US1] DEBUG panel `Apps/projectM-iOS/Debug/UITestCameraEventPanel.swift` (`-uitestCameraEvents`; buttons per contract C5, hidden `cameraRecovery`) and its one-line mount in `VisualizerView`; UI test `Apps/projectM-iOS/UITests/CameraRecoveryUITests.swift` (`-uitestCamera granted`): choose Camera, frames advance, inject `anotherApp` → notice text and `cameraRetry`, badge gone, frames stop; the announcement probe (`-uitestDiagnostics`) reads `camera|<reason text>` (CAM-013-R12); Retry → frames advance, notice gone, badge back (CAM-013-S6; under 30 s)

## Phase 4: User Story 2 - The camera breaks, and I can restart it (P1)

**Independent test**: inject a runtime error: no pixels, session released, Retry recovers; backoff on a fake clock.

- [ ] CAM-013-T13 [US2] App tests in `Apps/projectM-iOS/Tests/CameraRecoveryTests.swift`: runtime error → cleared, `failed` notice with Retry, Retry → running; media reset → one automatic retry and running; a second reset in a row waits for Retry; ten Retry taps on a fake clock and manual scheduler start the camera once, later attempts wait 2, 4, 8 s and the pending state reads "Retrying…" (CAM-013-R5-R7, S4); the host's counts per reason and of retries, and its probe, carry numbers only (CAM-013-R10); AV reason mapping table (`stopReason(interruption:)`, `stopReason(error:)`) (CAM-013-R3)

## Phase 5: User Story 3 - Access was turned off (P2)

**Independent test**: denied at start shows Open Settings without Retry; withdrawn access shows the denied notice on the next Retry.

- [ ] CAM-013-T14 [US3] App tests in `Apps/projectM-iOS/Tests/CameraRecoveryTests.swift`: `.denied` stand-in → FILE-013's denied notice, Open Settings, no Retry, no camera pixels; interruption, `withdrawAccess()`, Retry → denied notice; background during an interruption with a pending retry → the stop cancels it, the return runs the camera with no reason (CAM-013-R8, R11, S5)

## Phase 6: Polish & cross-cutting

- [ ] CAM-013-T15 ADR-0017 amendment (decisions 11-14: clear and explain, automatic return, Retry with backoff and the media-reset retry, revocation and background) in `docs/adr/0017-rear-camera-layer.md`
- [ ] CAM-013-T16 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; the touched UI suites (CameraUITests, FrontCameraUITests, CameraCropUITests, CameraPrivacyStatusUITests, PermissionAuditUITests, CameraRecoveryUITests); PosterBoard count after; delete the simulator
- [ ] CAM-013-T17 {device} D1 and D2: quickstart device steps 1-3 (FaceTime or another camera app, Split View on D2, Retry spacing, revocation ends the app and the next start is denied) (CAM-013-S7)
- [ ] CAM-013-T18 {device} D3 (iPadOS 26.5): an interruption and Retry on the iOS 26 path (CAM-013-S7)

## Dependencies

T01 → T02, T03 → T04, T05; T04 → T06, T07 → T08; T06 → T09 → T10 → T11, T12; T09 → T13, T14;
T15 any time after T04; T16 after all code; T17-T18 last (device stage).

## Parallel opportunities

T02 and T03; T07 (AV) and T08 (stub pixel tests) after T06; T13 and T14 after T10.

## Implementation strategy

MVP = Phases 2-3 (reasons, injection, host Retry, notice: the acceptance), then errors and
backoff (US2), then revocation and background (US3), then polish and the device stage.
