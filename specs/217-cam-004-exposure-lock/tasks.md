# Tasks: CAM-004 Camera Exposure Lock

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/exposure-lock.md](contracts/exposure-lock.md)

Tests are requested by the roadmap acceptance ("supported device changes exposure state;
unsupported device explains limit"). Budgets (owner rule 7): unit tests about 1-2 s, the UI test
under 30 s. Simulator results are never device evidence.

## Phase 1: Setup

- [ ] CAM-004-T01 Create the feature's simulator "CAM4 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree (no file changes)

## Phase 2: Foundational (blocks every story)

- [ ] CAM-004-T02 Add the exposure seam in `Packages/Compositor/Sources/CameraLayer/CameraExposure.swift`: `CameraExposureMode` (`locked`, `continuousAuto`, `other`), `CameraExposureState` (`canLock`, `isRunning`, `mode`; `isLocked`, `isAdjustable`, `notRunning(canLock:)`), protocol `CameraExposureConfiguring` (contract C1), `CameraExposureControl.lock/release` (C2: no configuration when unsupported or already in the target mode; `end` after every successful `begin`) and `FakeCameraExposureDevice` (supported modes, `refusesConfiguration`, counts of configurations and of mode changes outside a configuration); Foundation only, so it builds on Linux
- [ ] CAM-004-T03 Conform `AVCaptureDevice` to `CameraExposureConfiguring` in `Packages/Compositor/Sources/CameraLayer/AVCameraLensInventory.swift` (iOS; `try? lockForConfiguration()`; release uses `.continuousAutoExposure`)
- [ ] CAM-004-T04 Extend `CameraFrameProvider` in `Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift` with `exposure`, `onExposureChange` and `setExposureLocked(_:)` plus defaults (`notRunning(canLock: false)`, no-op) (contract C3)

## Phase 3: User Story 1 - Hold the exposure steady (P1)

**Goal**: lock and release on a supported, running camera; the state is read back.
**Independent test**: stand-in provider with a lockable camera: lock → `locked`, unlock → `continuousAuto`, refused configuration → unchanged.

- [ ] CAM-004-T05 [US1] Stand-in: `FakeCameraInput` carries its camera's `FakeCameraExposureDevice` (one per lens and for the front camera, kept by `FakeCameraCaptureSession`, `lockableCameras`) in `Packages/Compositor/Sources/CameraLayer/CameraInputSwitch.swift`; `StubCameraFrameProvider` implements `exposure`/`setExposureLocked` through `CameraExposureControl` on the session's device in `Packages/Compositor/Sources/CameraLayer/StubCameraFrameProvider.swift`
- [ ] CAM-004-T06 [US1] Real camera: `AVCameraFrameProvider` runs `CameraExposureControl` on its session queue against the session's device input and posts the read-back state (generation-checked) in `Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift`; capability read from the chosen camera without starting it (research CAM-004-D4)
- [ ] CAM-004-T07 [US1] Package tests in `Packages/Compositor/Tests/CompositorTests/CameraExposureTests.swift`: control routine (lock, unlock, refused, unsupported: 0 configurations) and stand-in provider (lock/unlock while running read back, each change reported once, no lock while idle)

## Phase 4: User Story 2 - Learn why the control is not available (P1)

**Goal**: unsupported camera explains its limit; not running is disabled with its own note.
**Independent test**: app with `-uitestCameraExposureLock none` shows "This camera can't lock exposure." and a disabled switch.

- [ ] CAM-004-T09 [US2] Host and coordinator: `CameraVisualHost` forwards `cameraExposure`/`setCameraExposureLocked` and `onExposureChange`, and gives the stand-in its lockable cameras from DEBUG `-uitestCameraExposureLock <list|none>` in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`; `AppCoordinator.cameraExposure` (observed) is set from the host and reset when the host goes in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] CAM-004-T10 [US2] Row: `CameraExposureRow` + `CameraExposureChoice` + coordinator extension (`shownCameraExposure`, `chooseCameraExposureLocked`, note text per contract C4) in `Apps/projectM-iOS/Views/CameraExposureRow.swift`; optional row after the Lens row in `Apps/projectM-iOS/Views/SettingsView.swift`; passed from `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] CAM-004-T11 [US2] App tests in `Apps/projectM-iOS/Tests/CameraExposureAppTests.swift`: note texts for unsupported / not running / running; host with a stand-in: lock through the coordinator reaches the device, unsupported makes 0 configurations; no new key in `AppSettings.allKeys`
- [ ] CAM-004-T12 [US2] UI test in `Apps/projectM-iOS/UITests/CameraExposureUITests.swift` (stand-in, < 30 s each): supported → switch enabled, on → value "1", off → "0"; `-uitestCameraExposureLock none` → disabled with the explanation

## Phase 5: User Story 3 - The lock never outlives its camera (P2)

**Goal**: release before lens/position switches and on every stop.
**Independent test**: lock on wide, switch to ultra wide: wide's device continuous, switch off.

- [ ] CAM-004-T13 [US3] Stand-in and real provider: release before a lens or position switch and on stop/failure; state `notRunning` after a stop (both provider files)
- [ ] CAM-004-T14 [US3] Package tests in `CameraExposureTests.swift`: lens switch and position switch while locked release the old device and report `continuousAuto` on the new one; stop and failure release; an unsupported lens after a switch reports `canLock` false

## Phase 6: Polish

- [ ] CAM-004-T15 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), type-check budget flags on the app build, privacy manifest and network symbol checks on the Debug app; `LibraryBackupAppTests` (no new keys)
- [ ] CAM-004-T08 {device} On D1: quickstart "Device" steps 1-4 (real lock holds brightness, lens switch and visual change release it)
- [ ] CAM-004-T16 Delete the simulator "CAM4 iPhone 17" and the derived data; count PosterBoard reports before and after

## Dependencies

T01 → T02 → T03, T04 → US1 (T05, T06 → T07) → US2 (T09 → T10 → T11, T12) ; US3 (T13 → T14) after US1 → T15 → T16. T08 needs a person and D1.

## Parallel opportunities

T03 and T04 [different files]; T06 alongside T05; T11 and T12 once T10 is done.

## Implementation strategy

MVP = US1 + US2 (the roadmap acceptance). US3 completes the safety rules in the same change.
