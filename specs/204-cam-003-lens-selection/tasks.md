---
description: "Tasks for CAM-003 Camera lens selection"
---

# Tasks: CAM-003 Camera Lens Selection

**Input**: `specs/204-cam-003-lens-selection/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance S1, S2, S3; UI test). Budgets (owner rule 7): a unit
test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, a UI test < 30 s; no wall-clock assertions.

Format: `- [ ] CAM-003-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] CAM-003-T01 Record the PosterBoard report count; create the simulator "CAM3 iPhone 17" (iOS 27.2). — Verified 2026-11-14: PosterBoard reports 25 before; simulator "CAM3 iPhone 17" (iOS 27.2, 5A1DABAA) created.

## Phase 2: Foundational

- [X] CAM-003-T02 Implement `Packages/Compositor/Sources/CameraLayer/CameraLens.swift`: `CameraLens` (order, titles, unknown → wide), `CameraLensInventory`, `FixedCameraLensInventory` (distinct, display order), `resolve` (R1, R5; data-model.md). — Verified 2026-11-14: CameraLensTests (Compositor) testInventoryListsDistinctLensesWidestFirstAndOffersOnlyTwoOrMore and testStoredLensMissingOnDeviceResolvesToWide pass on the host and in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE).
- [X] CAM-003-T03 Implement `CameraInputSwitch.swift`: `CameraInputConfiguring`, `CameraInputSwitch.replace` (contract C2), `FakeCameraCaptureSession` with failing lenses (R6, R7, R10). — Verified 2026-11-14: CameraLensTests.testSwitchOutcomes: switched, creation failure → keptPrevious with zero configurations, refusal → keptPrevious, previous refused → fellBackToWide, nothing addable → noInput, zero input changes outside begin/commit; host and Linux shape.
- [X] CAM-003-T04 Implement `AVCameraLensInventory.swift` (DiscoverySession for the three back types; `AVCaptureSession: CameraInputConfiguring`) (R1, R3; research D1). — Verified 2026-11-14: compiles in the iOS app build (build-for-testing on CAM3, TEST BUILD SUCCEEDED); discovery asks only the three physical back types; real lenses pending device (T11).

## Phase 3: User Story 2 — switching never crashes (P1, acceptance second half)

- [X] CAM-003-T05 [US2] Write `Packages/Compositor/Tests/CompositorTests/CameraLensTests.swift`: switch routine outcomes (switched; creation fails → keptPrevious, session untouched; refused → keptPrevious; old also refused → wide; nothing → noInput); 30 switches on a running stand-in, a third to a failing lens: running, exactly one input, `lens` equals the input's lens after every switch (S2); stand-in select while idle/denied only records; front ignores the lens; after each switch the held picture is a new one (sequence increases, R8). — Verified 2026-11-14: Compositor CameraLensTests 6 pass on the macOS host (0.004 s total): 30 switches, every third to a failing telephoto, running with exactly one input after each, lens names the input, new picture sequence after each effective switch, startCount 1.
- [X] CAM-003-T06 [US2] Protocol additions in `CameraFrameProvider.swift` (contract C1); stand-in provider in `StubCameraFrameProvider.swift` (inventory, failing lenses, fake session); `AVCameraFrameProvider.swift` (camera for position and lens, `selectLens` through `CameraInputSwitch` on the session queue, revert on keptPrevious, unavailable on noInput) (R6 to R9). Evidence: T05 passes. — Verified 2026-11-14: T05 passes against the stand-in (same CameraInputSwitch routine as the AV provider); AVCameraFrameProvider compiles for iOS (app build); its real switching is pending device (T11).

## Phase 4: User Story 1 — only available lenses (P1, acceptance first half)

- [X] CAM-003-T07 [US1] App: `settings.camera.lens` in `AppSettings.swift` (+ `allKeys`), `LibrarySettings.swift`, `scripts/run_device_tests.py`; lens inventory and forwarding in `AppCoordinator.swift`; `cameraLens` and stand-in args (`-uitestCameraLenses`, `-uitestCameraLensFails`) in `CameraVisualHost.swift`; the Lens row in `SettingsView.swift` `cameraSection` (R2, R4, R5, R9, R11). — Verified 2026-11-14: build-for-testing on CAM3 with the type-check flags: TEST BUILD SUCCEEDED, no type-check warning in changed code (SettingsView.swift:260 and VisualizerView.swift:61 are pre-existing); SettingsTests 9, LibraryBackupAppTests (incl. testIncludedKeysAndFolderNamesAgreeWithTheStores) and LibraryBackup package 77 pass.
- [X] CAM-003-T08 [US1] Write `Apps/projectM-iOS/Tests/CameraLensTests.swift`: row lenses for the three inventories (0, 2, 3; front → 0) (S1); settings round trip, unknown → wide, missing on device → wide with the stored value kept (S3); key in `allKeys` and the backup policy; host forwards the lens to a running stand-in and keeps running when the lens fails; reading the inventory never starts the stand-in camera (startCount 0, R3). — Verified 2026-11-14: CameraLensTests (app) 3 pass on CAM3 (iOS 27.2) in 1.7 s: rows 0/2/3 lenses and none for Front; persistence, unknown → wide, missing → wide with the value kept, key in allKeys and includedKeys; host switch on the running stand-in, failing telephoto keeps ultra wide, startCount 0 before resume and 1 after all switches.
- [X] CAM-003-T09 [US1] Write `Apps/projectM-iOS/UITests/CameraLensUITests.swift` (< 30 s each): wide-only stand-in → no Lens row; three-lens stand-in → row with exactly 3 segments, switching through every lens including a failing telephoto leaves the camera visual "Live". — Verified 2026-11-14: CameraLensUITests 2 pass on CAM3: single lens shows no Lens row (19.9 s); three lenses show exactly Ultra Wide/Wide/Telephoto, Telephoto (failing) returns to Ultra Wide, camera visual "Live" and sourceStarts 1 after Done (25.5 s). FrontCameraUITests still passes (20.7 s).

## Phase 5: Polish

- [X] CAM-003-T10 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; type-check budget on changed files; PosterBoard count; delete the simulator and derived data. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts all exit 0; check_privacy_manifest OK and check_network_symbols OK (19 images) on the Debug simulator app; PosterBoard reports 25 before and 25 after; simulator and derived data deleted at the end.
- [ ] CAM-003-T11 {device} D1: Wide ↔ Ultra Wide ten times while running (picture follows, badge stays, no crash); D2 and D3: no Lens row (S4).

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 T02/T04/T08; R2 T07-T09; R3 T04, T08 (no start from listing); R4, R5 T07/T08; R6, R7 T03/T05; R8 T05 (new picture after a switch); R9 T05; R10 T03/T06; R11 T09. S1 T08/T09; S2 T05; S3 T08; S4 T11. Fixes applied: R8 and R3 assertions added to T05 and T08. No constitution conflicts.

## Dependencies

T01 → T02-T04 → T05/T06 → T07 → T08, T09 → T10. T11 after integration, on devices.
