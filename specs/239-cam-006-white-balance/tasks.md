# Tasks: CAM-006 Camera White Balance

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/white-balance-lock.md](contracts/white-balance-lock.md)

Tests are requested by the roadmap acceptance ("Lock/unlock persists during session without invalid
device configuration"). Budgets (owner rule 7): unit tests about 1-2 s, each UI test under 30 s.
Simulator results are never device evidence.

## Phase 1: Setup

- [X] CAM-006-T01 Create the feature's simulator "CAM6 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree (no file changes) — Verified 2026-11-14: `xcrun simctl create` (C21B17EA) and `xcodegen generate`

## Phase 2: Foundational (blocks every story)

- [X] CAM-006-T02 Add the white balance seam in `Packages/Compositor/Sources/CameraLayer/CameraWhiteBalance.swift`: `CameraWhiteBalanceMode` (`locked`, `continuousAuto`, `other`), `CameraWhiteBalanceGains` (`red`, `green`, `blue`; `validated(maximum:)` "nil when the maximum is not finite or below 1, or any channel is not finite; otherwise each channel clamped to 1…maximum", `isValid(maximum:)`), `CameraWhiteBalanceState` (`canLock`, `isRunning`, `mode`; `isLocked`, `isAdjustable`, `notRunning(canLock:)`), protocol `CameraWhiteBalanceConfiguring` (contract C1), `CameraWhiteBalanceControl.lock/release/state` (C2) and `FakeCameraWhiteBalanceDevice` (supported modes, reported gains, maximum, custom-gain support, `refusesConfiguration`, counts of configurations, changes outside a configuration and invalid gains applied); Foundation only (Linux) — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter CameraWhiteBalanceTests` (11 passed, 0.003 s) and the same filter with `-DCOMPOSITOR_NO_METAL` (Linux shape: 7 routine tests pass)
- [X] CAM-006-T03 Conform `AVCaptureDevice` to `CameraWhiteBalanceConfiguring` in `Packages/Compositor/Sources/CameraLayer/AVCameraLensInventory.swift` (iOS; `setWhiteBalanceModeLocked(with:completionHandler: nil)` only after re-checking the gains are valid; `.locked` without gains; `.continuousAutoWhiteBalance`) — Verified 2026-11-14: simulator build-for-testing of projectM-iOS (iOS SDK 27.2 compiles the iOS-only conformance), TEST BUILD SUCCEEDED, no type-check warnings in the changed files
- [X] CAM-006-T04 Extend `CameraFrameProvider` in `Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift` with `whiteBalance`, `onWhiteBalanceChange`, `setWhiteBalanceLocked(_:)` plus defaults (`notRunning(canLock: false)`, no-op) (C3) — Verified 2026-11-14: package and app builds; CameraExposureTests (7), CameraFocusTests (9), CameraExposureAppTests (4) still pass

## Phase 3: User Story 1 - Hold the colors steady (P1)

**Goal**: lock and release on a supported, running camera with valid gains only; the state is read back.
**Independent test**: stand-in provider with a lockable camera: lock → `locked`, unlock → `continuousAuto`; invalid reported gains → clamped or refused, never applied.

- [X] CAM-006-T05 [US1] Stand-in: `FakeCameraInput` carries its camera's `FakeCameraWhiteBalanceDevice` (one per camera, kept by `FakeCameraCaptureSession`, `whiteBalanceLockCameras`) in `Packages/Compositor/Sources/CameraLayer/CameraInputSwitch.swift`; `StubCameraFrameProvider` implements `whiteBalance`/`setWhiteBalanceLocked` through `CameraWhiteBalanceControl` in `Packages/Compositor/Sources/CameraLayer/StubCameraFrameProvider.swift` — Verified 2026-11-14: CameraWhiteBalanceTests stand-in provider tests pass
- [X] CAM-006-T06 [US1] Real camera: `AVCameraFrameProvider` runs `CameraWhiteBalanceControl` on its session queue and reads the state back with the exposure (generation-checked) in `Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift`; capability read from the chosen camera without starting it — Verified 2026-11-14: app simulator build compiles AVCameraFrameProvider; behaviour on a real camera is T09
- [X] CAM-006-T07 [US1] Package tests in `Packages/Compositor/Tests/CompositorTests/CameraWhiteBalanceTests.swift`: lock → locked and unlock → continuous inside one configuration each; 0 changes outside a configuration (R4); refused configuration unchanged (R6); gains fuzz (below 1, above maximum, NaN, infinity, bad maximum) → clamped or refused, `invalidGainsApplied` 0 (R5, S2); lock in place without custom gains; a camera without continuous mode keeps the reported mode on release (Edge Cases); stand-in provider lock/unlock read back, `startCount` unchanged (R11) — Verified 2026-11-14: CameraWhiteBalanceTests: 11 tests, 0.003 s (gains fuzz: 7 cases, `invalidGainsApplied` 0)

## Phase 4: User Story 2 - The lock lasts for the session, and only for it (P1)

**Goal**: interruption keeps the lock; lens/position switch and every stop/failure release it.
**Independent test**: stand-in provider: lock, interrupt, end → locked; lock, switch lens/position, stop, fail → previous device continuous.

- [X] CAM-006-T08 [US2] Release the white balance lock wherever CAM-004 releases exposure (`releaseExposure` in both providers: before every input removal, on stop and failure), and keep it across interruptions; tests in `Packages/Compositor/Tests/CompositorTests/CameraWhiteBalanceTests.swift` (R7, R8, R9, S3) — Verified 2026-11-14: CameraWhiteBalanceTests `testLockSurvivesAnInterruption`, `testLensAndPositionSwitchesAndStopsReleaseTheLock`; CameraWhiteBalanceAppTests host lens switch and stop
- [ ] CAM-006-T09 [US2] {device} On D1, Camera visual under colored light: lock → colors hold, `whiteBalanceMode` locked; interrupt (Siri or a call) and return → still locked; switch lens → switch off; stop → automatic (quickstart step 4)

## Phase 5: User Story 3 - Learn why the control is not available (P2)

**Goal**: the row, disabled with the note when unsupported or not running.
**Independent test**: `-uitestCameraWhiteBalanceLock none`: disabled with "This camera can't lock white balance.".

- [X] CAM-006-T10 [US3] `Apps/projectM-iOS/Views/CameraWhiteBalanceRow.swift` (row, notes, coordinator extension, contract C4); `Apps/projectM-iOS/Visuals/CameraVisualHost.swift` (forwarding, `-uitestCameraWhiteBalanceLock <list|none>`); `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (observed `cameraWhiteBalance`, reset on release); `Apps/projectM-iOS/Views/SettingsView.swift` (row after Lock exposure, footer sentence); `Apps/projectM-iOS/Views/VisualizerView.swift` (passes the choice) (R1, R2, R3, R13) — Verified 2026-11-14: UI and app tests below; CameraExposureUITests (2) still pass with the new row beneath
- [X] CAM-006-T11 [P] [US3] App tests in `Apps/projectM-iOS/Tests/CameraWhiteBalanceAppTests.swift`: notes per state, nothing stored (R10), host lock/release/stop with the stand-in, unsupported never configured — Verified 2026-11-14: CameraWhiteBalanceAppTests: 4 passed, 0.05 s on "CAM6 iPhone 17" (iOS 27.2); LibraryBackupAppTests (5) pass
- [X] CAM-006-T12 [P] [US3] UI tests in `Apps/projectM-iOS/UITests/CameraWhiteBalanceUITests.swift`: supported lock/unlock read back without a restart; unsupported disabled with the note; the switch's label is "Lock white balance" (R13) — Verified 2026-11-14: CameraWhiteBalanceUITests: 2 passed (27.0 s, 22.8 s)

## Phase 6: Polish

- [X] CAM-006-T13 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), type-check budget, `check_privacy_manifest`, `check_network_symbols`, PosterBoard counts; delete the simulator and derived data — Verified 2026-11-14: all six repo checks exit 0; `check_privacy_manifest` OK; `check_network_symbols` OK (19 images); PosterBoard reports 26 before and after; simulator and derived data deleted

## Dependencies

T01 → T02 → (T03, T04) → T05, T06 → T07 → T08 → T10 → (T11, T12) → T13. T09 is `{device}` and stays open.

## Implementation strategy

MVP is US1 (seam, stand-in, tests); US2 reuses CAM-004's release points; US3 adds the row. Parallel: T03/T04 (different files), T11/T12.
