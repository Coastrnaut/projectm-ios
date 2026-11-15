# Tasks: SHOW-013 Auto Scene Rotation

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/scene-rotation.md](contracts/scene-rotation.md), [quickstart.md](quickstart.md). Tests are requested (roadmap
acceptance; owner rule 7 budgets).

## Phase 1: Setup

- [ ] SHOW-013-T01 Create simulator "SHOW13 iPhone 17" (iOS 27.2), run `xcodegen generate`, record the PosterBoard report count before runs

## Phase 2: Foundational (model)

- [ ] SHOW-013-T02 Add `SceneRotationSettings`, `SceneRotationPlan` (C1) and `SceneRotationSchedule` (C2) in Packages/ShowControl/Sources/ShowControl/SceneRotation.swift
- [ ] SHOW-013-T03 [P] Package tests: 1000 seeded steps (0 disabled, 0 immediate repeats, same seed same sequence, every enabled scene reached), one/zero enabled idle, current outside the collection, folder collection with subfolders, unknown folder = all, schedule timer / bars at 120 BPM / no tempo / minimum gap with and without Reduce flashing, settings decode and clamp, in Packages/ShowControl/Tests/ShowControlTests/SceneRotationTests.swift

## Phase 3: User Story 1 — Rotate scenes on a timer (P1) MVP

- [ ] SHOW-013-T04 [US1] `SceneRotationCoordinator` (C3: settings storage, on/off, seed, tick loop, holds, pick → step path, `sceneChanged`, status texts) in Apps/projectM-iOS/Coordinators/SceneRotationCoordinator.swift
- [ ] SHOW-013-T05 [US1] Wiring: lazy `sceneRotation` in Apps/projectM-iOS/Coordinators/AppCoordinator.swift; holds, tempo, Reduce flashing and the `cueStarted` chain in Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift; DEBUG `-uitestSceneRotation`
- [ ] SHOW-013-T06 [US1] App acceptance tests (no switch at 29 s, real switch at 30 s through the step path, manual Go restarts, holds and a running countdown pause, 50 rotations never apply a disabled scene, bars mode steps at once, status texts for zero and one enabled scene and the timer) in Apps/projectM-iOS/Tests/SceneRotationAcceptanceTests.swift

## Phase 4: User Story 2 — Collection and disabled scenes (P1)

- [ ] SHOW-013-T07 [US2] `SceneRotationSection` (toggle, collection, mode, interval/bars, status, "Scenes in rotation" list) in Apps/projectM-iOS/Views/SceneRotationSection.swift; one line in Apps/projectM-iOS/Views/SettingsView.swift tail sections; pass the coordinator from Apps/projectM-iOS/Views/VisualizerView.swift
- [ ] SHOW-013-T08 [US2] Key lists (C4): Apps/projectM-iOS/Coordinators/AppSettings.swift, Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift, scripts/run_device_tests.py, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift
- [ ] SHOW-013-T09 [US2] UI test (< 30 s): seeded show + `-uitestSceneRotation 2` → applied scene changes twice by itself, never repeating; the Settings section shows the toggle on, in Apps/projectM-iOS/UITests/SceneRotationUITests.swift

## Phase 5: User Story 3 — Rotate on the beat (P2)

- [ ] SHOW-013-T10 [US3] Bars mode in the coordinator uses SHOW-011's bar lines and steps at once; app test with a seeded tempo in Apps/projectM-iOS/Tests/SceneRotationAcceptanceTests.swift

## Phase 6: Polish

- [ ] SHOW-013-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, ShowControl Linux shape, LibraryBackup package tests, `LibraryBackupAppTests`
- [ ] SHOW-013-T12 Spec status, PosterBoard counts, delete the simulator and derived data
- [ ] SHOW-013-T13 {device} On D1: a show of 4+ scenes, 120 BPM tapped, Rotate scenes on, Bars 4: scenes change on the downbeat every 8 s, never repeating, a disabled scene never shows; Timer 15 s also rotates

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06, T07, T10; T07 → T09; T08 with T04; all → T11 → T12. T13 needs a person and a device.

## Parallel opportunities

T03 alongside T04 (different files). T06 and T10 share a file (same writer, sequential).

## Implementation strategy

MVP is US1 (model + coordinator). US2 adds the Settings controls; US3's bars mode is in the same coordinator.
