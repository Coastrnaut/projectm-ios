---
description: "Tasks for CAM-003 Camera lens selection"
---

# Tasks: CAM-003 Camera Lens Selection

**Input**: `specs/204-cam-003-lens-selection/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance S1, S2, S3; UI test). Budgets (owner rule 7): a unit
test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, a UI test < 30 s; no wall-clock assertions.

Format: `- [ ] CAM-003-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] CAM-003-T01 Record the PosterBoard report count; create the simulator "CAM3 iPhone 17" (iOS 27.2).

## Phase 2: Foundational

- [ ] CAM-003-T02 Implement `Packages/Compositor/Sources/CameraLayer/CameraLens.swift`: `CameraLens` (order, titles, unknown → wide), `CameraLensInventory`, `FixedCameraLensInventory` (distinct, display order), `resolve` (R1, R5; data-model.md).
- [ ] CAM-003-T03 Implement `CameraInputSwitch.swift`: `CameraInputConfiguring`, `CameraInputSwitch.replace` (contract C2), `FakeCameraCaptureSession` with failing lenses (R6, R7, R10).
- [ ] CAM-003-T04 Implement `AVCameraLensInventory.swift` (DiscoverySession for the three back types; `AVCaptureSession: CameraInputConfiguring`) (R1, R3; research D1).

## Phase 3: User Story 2 — switching never crashes (P1, acceptance second half)

- [ ] CAM-003-T05 [US2] Write `Packages/Compositor/Tests/CompositorTests/CameraLensTests.swift`: switch routine outcomes (switched; creation fails → keptPrevious, session untouched; refused → keptPrevious; old also refused → wide; nothing → noInput); 30 switches on a running stand-in, a third to a failing lens: running, exactly one input, `lens` equals the input's lens after every switch (S2); stand-in select while idle/denied only records; front ignores the lens.
- [ ] CAM-003-T06 [US2] Protocol additions in `CameraFrameProvider.swift` (contract C1); stand-in provider in `StubCameraFrameProvider.swift` (inventory, failing lenses, fake session); `AVCameraFrameProvider.swift` (camera for position and lens, `selectLens` through `CameraInputSwitch` on the session queue, revert on keptPrevious, unavailable on noInput) (R6 to R9). Evidence: T05 passes.

## Phase 4: User Story 1 — only available lenses (P1, acceptance first half)

- [ ] CAM-003-T07 [US1] App: `settings.camera.lens` in `AppSettings.swift` (+ `allKeys`), `LibrarySettings.swift`, `scripts/run_device_tests.py`; lens inventory and forwarding in `AppCoordinator.swift`; `cameraLens` and stand-in args (`-uitestCameraLenses`, `-uitestCameraLensFails`) in `CameraVisualHost.swift`; the Lens row in `SettingsView.swift` `cameraSection` (R2, R4, R5, R9, R11).
- [ ] CAM-003-T08 [US1] Write `Apps/projectM-iOS/Tests/CameraLensTests.swift`: row lenses for the three inventories (0, 2, 3; front → 0) (S1); settings round trip, unknown → wide, missing on device → wide with the stored value kept (S3); key in `allKeys` and the backup policy; host forwards the lens to a running stand-in and keeps running when the lens fails.
- [ ] CAM-003-T09 [US1] Write `Apps/projectM-iOS/UITests/CameraLensUITests.swift` (< 30 s each): wide-only stand-in → no Lens row; three-lens stand-in → row with exactly 3 segments, switching through every lens including a failing telephoto leaves the camera visual "Live".

## Phase 5: Polish

- [ ] CAM-003-T10 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; type-check budget on changed files; PosterBoard count; delete the simulator and derived data.
- [ ] CAM-003-T11 {device} D1: Wide ↔ Ultra Wide ten times while running (picture follows, badge stays, no crash); D2 and D3: no Lens row (S4).

## Dependencies

T01 → T02-T04 → T05/T06 → T07 → T08, T09 → T10. T11 after integration, on devices.
