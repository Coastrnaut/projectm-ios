# Tasks: ACC-009 One-Handed Performance Mode

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/one-handed-layout.md](contracts/one-handed-layout.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap's acceptance ("Layout switch preserves every critical action on phone sizes").
Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min, UI test < 30 s. Simulator results are UI
evidence only.

## Phase 1: Setup

- [ ] ACC-009-T01 Create the private simulators "ACC9 iPhone 17" and a small iPhone (iOS 27.2), run `xcodegen generate`, initialise the preset submodules, keep the `Build` symlink, baseline build-for-testing

## Phase 2: Foundational

- [X] ACC-009-T02 Implement `OneHandedHand`, `CriticalAction` (identifiers, groups), `CriticalActionContext` with `standard(_:)` and `displayed(_:)` (C2) and `OneHandedLayout` (C1: zone, rows, shrink, `fits`, `reservedInsets`, `baseTarget(scaled:)`) in Packages/ShowControl/Sources/ShowControl/OneHandedLayout.swift — Verified 2026-11-14: `OneHandedLayoutTests` (7) passed on the host
- [X] ACC-009-T03 [P] Package tests: phone-size table (SE, 13 mini, 17e, 17, 17 Pro Max × portrait/landscape × base 44/50/56 × 4 states × 2 hands) asserting set equality with `standard`, side ≥ 44 (pad ≥ 60 with the pad), inside safe area, inside zone, no overlap, inside the reserved band, `fits`; pad stability with controls hidden/shown; order (Stop farthest); a forced-shrink case (a short area where 56 pt must shrink, never below 44 pt, no action dropped, `fits` false only when even 44 pt cannot fit); in Packages/ShowControl/Tests/ShowControlTests/OneHandedLayoutTests.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl --filter OneHandedLayoutTests`: 7 passed (0.01 s; 480 table cases); full ShowControl suite 130 tests, 0 failures (4.6 s)

## Phase 3: User Story 1 — every critical action under the thumb (P1, MVP)

- [ ] ACC-009-T04 [US1] `OneHandedSetting` (key `settings.controls.oneHanded`, "left"/"right", absent = Off; `-uitestResetNotice` removes it; `isPhone`; `isActive`) and the AppCoordinator helpers (`oneHandedActive`, `oneHandedContext`) in Apps/projectM-iOS/Coordinators/OneHandedSetting.swift; one lazy property in Apps/projectM-iOS/Coordinators/AppCoordinator.swift
- [ ] ACC-009-T05 [US1] `OneHandedControlsLayer` (targets at the layout's frames with standard identifiers, labels, values, hints; reports reserved insets; DEBUG `oneHandedZone` probe) and `OneHandedSection` (Off / Left hand / Right hand rows) in Apps/projectM-iOS/Views/OneHandedControls.swift
- [ ] ACC-009-T06 [US1] Leave the moved actions out of the card while active: Apps/projectM-iOS/Views/ControlsOverlay.swift (`buttons` filter, empty primary row skipped), Apps/projectM-iOS/Views/TempoControls.swift (`showsTap`), Apps/projectM-iOS/Views/ShowControls.swift (`showsArrows`)
- [ ] ACC-009-T07 [US1] Wire the layer and the section: Apps/projectM-iOS/Views/VisualizerView.swift (layer in `statusLayers`, inset condition, Settings argument), Apps/projectM-iOS/Views/SettingsView.swift (row after Show HUD), "oneHanded" anchor in Apps/projectM-iOS/Debug/UITestSettingsSection.swift
- [ ] ACC-009-T08 [US1] App unit tests: setting storage and reset, iPad inactive, context mapping, every `CriticalAction` identifier present in the standard card's list in Apps/projectM-iOS/Tests/OneHandedAppTests.swift
- [ ] ACC-009-T09 [US1] UI tests (S3): standard → Settings → Right hand; every critical identifier present, hittable, inside the zone; Pause works; on both simulators, in Apps/projectM-iOS/UITests/OneHandedUITests.swift

## Phase 4: User Story 2 — one-handed with the pad (P2)

- [ ] ACC-009-T10 [US2] One-handed arrangement of `PerformancePadLayer` (targets at the layout's pad frames, readouts above, B key kept, no inset report) in Apps/projectM-iOS/Views/PerformancePad.swift and the argument in VisualizerView
- [ ] ACC-009-T11 [US2] Package test S2 (pad frames identical with controls hidden and shown) in OneHandedLayoutTests and a UI check that `perfNextCue` etc. lie in the zone with the pad on, in OneHandedUITests

## Phase 5: User Story 3 — nothing hides anything (P2)

- [ ] ACC-009-T12 [US3] UI test S4: Left hand with the HUD on; every critical action in the bottom-left zone and none intersects `sceneHUD`, in OneHandedUITests
- [ ] ACC-009-T13 [US3] QA-009 manifest entry `oneHandedControls` (launch `-settings.controls.oneHanded right`) and its test methods in Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift and PrimaryScreensAccessibilityUITests.swift; run standard and AX5
- [ ] ACC-009-T14 {device} On D1: Right and Left hand, portrait and landscape, with and without the pad: every critical action reached with the thumb of the holding hand (quickstart step 5)

## Phase 6: Polish

- [ ] ACC-009-T15 Register the key (R9): `ALLOWED_KEYS` in scripts/run_device_tests.py, FILE-005 `includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, `appKeys` in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift; check that no scene, cue, MIDI or OSC code reads the key (grep); run `LibraryBackupAppTests`
- [ ] ACC-009-T16 Type-check budget build, the six repo checks, `qa009_manifest_check`, `check_privacy_manifest` and `check_network_symbols` on the Debug app
- [ ] ACC-009-T17 Spec status, delete the simulators and derived data, PosterBoard counts

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06 → T07 → (T08, T09); T07 → T10 → T11; T07 → T12, T13; T15 after T04;
T16–T17 last. Parallel: T03 with T04; T08 with T10.

## Implementation strategy

MVP = US1 (the acceptance clause). US2 adds the pad arrangement; US3 adds the HUD and QA-009 checks.

## Analyze notes (speckit-analyze, 2026-11-14)

- C1 (fixed): R9's "never in scenes, cues, MIDI or OSC" had no check; T15 now greps for the key outside the setting.
- C2 (fixed): R4's shrink rule had no test; T03 now has a forced-shrink case.
- I1 (accepted, LOW): the footer wording lives in the code (C3), the spec states its purpose only.
- Coverage: R1 T05/T07/T09, R2 T02/T03/T06/T09, R3 T02/T03/T09, R4 T02/T03, R5 T02/T05/T07/T12, R6 T04/T08, R7 T10/T11, R8 T05/T13, R9 T04/T15, R10 T13; S1-S5 map to T03, T11, T09, T12, T13. No constitution conflict.
