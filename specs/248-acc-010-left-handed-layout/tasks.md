# Tasks: ACC-010 Left-Handed Layout

**Input**: `specs/248-acc-010-left-handed-layout/` (spec, plan, research, data-model, contracts, quickstart)

Tests are requested by the roadmap's acceptance ("Button positions swap and action identifiers remain unchanged") and
the spec's success criteria. Budgets (owner rule 7): unit test ≤ 10 s, UI test < 30 s, any xcodebuild run < 10 min.

## Phase 1: Setup

- [ ] ACC-010-T01 Create the private simulator "ACC10 iPhone 17" (iOS 27.2), run `xcodegen generate`, and confirm the `Build` symlink and preset submodules are in place (worktree root)

## Phase 2: Foundational (pure placement, blocks all stories)

- [ ] ACC-010-T02 Add `ControlsSide` (`right`, `left`, `resolve(oneHanded:leftHanded:)`), `PadTarget` (identifiers `perfPreviousCue`, `perfNextCue`, `perfTapTempo`, `perfBlackout`), `PadPlacement` and `PerformanceLayout.placement(_:)` / `targetFrames(width:height:side:readoutHeight:)` per contract C1 and research ACC-010-D3 in Packages/ShowControl/Sources/ShowControl/HandedPlacement.swift
- [ ] ACC-010-T03 [P] Geometry tests in Packages/ShowControl/Tests/ShowControlTests/HandedPlacementTests.swift: for bar, grid and side columns at three sizes each, Black out and Tap tempo left frames equal the horizontal mirror of the right frames within 1 pt, the cue pair's union mirrors and Previous stays left of / above Next, the identifier sets are equal; side resolution (S1, R3, R5, R6)

## Phase 3: User Story 1 — Pad and emergency button on the left (P1) 🎯 MVP

**Independent test**: LeftHandedUITests switches the setting and finds mirrored frames with identical identifiers.

- [ ] ACC-010-T04 [US1] Add `leftHanded` (key `settings.controls.leftHanded`, Boolean, absent = off, written on change only, removed by `-uitestResetNotice`) and `controlsSide` to Apps/projectM-iOS/Coordinators/OneHandedSetting.swift (R1, R6, R7)
- [ ] ACC-010-T05 [US1] Draw the pad's bar, grid and columns from `placement(side)` with readouts following their groups and aligned toward the screen edge on their side (spec Clarifications), identifiers, labels, values, hints and the B key unchanged, no layout-direction environment or flip (research ACC-010-D1), in Apps/projectM-iOS/Views/PerformancePad.swift (R3, R5)
- [ ] ACC-010-T06 [US1] Add `LeftHandedSection` (switch `leftHandedToggle`, section id `leftHanded`) and `EmergencyBlackoutCorner(side:)` in Apps/projectM-iOS/Views/LeftHandedControls.swift; show the section in `performanceSection` of Apps/projectM-iOS/Views/SettingsView.swift; pass `oneHanded.controlsSide` to the pad and the corner in Apps/projectM-iOS/Views/VisualizerView.swift; with ACC-009 one-handed Left the corner button now follows that hand (R6, research ACC-010-D2) (R1, R2)
- [ ] ACC-010-T07 [US1] UI tests in Apps/projectM-iOS/UITests/LeftHandedUITests.swift: (a) portrait: emergency button and bar frames before and after switching in Settings are mirrored within 1 pt with identical identifiers; (b) landscape with the setting on: side columns swapped and mirrored within 1 pt (S2)

## Phase 4: User Story 2 — The output is never mirrored (P1)

- [ ] ACC-010-T08 [US2] Output isolation test in Apps/projectM-iOS/Tests/LeftHandedAppTests.swift (UIX-013 pattern): an `ExternalDisplayViewController` window shows an asymmetric stand-in visual; its snapshot is byte-identical with the real `PerformancePadLayer` drawn right- and left-handed in the device window; the device slot's visual has an identity transform and the pad is on screen (R4, S3)

## Phase 5: User Story 3 — Kept, backed up, coexists with one-handed (P2)

- [ ] ACC-010-T09 [US3] Preference unit tests (default off, stored on change, removed when off, `controlsSide` with and without one-handed, iPad) in Apps/projectM-iOS/Tests/LeftHandedAppTests.swift (R1, R6)
- [ ] ACC-010-T10 [US3] Add `settings.controls.leftHanded` to `ALLOWED_KEYS` in scripts/run_device_tests.py, `LibrarySettingsPolicy.includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, and `appKeys` in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift; run `LibraryBackupAppTests` (R7, S4)

## Phase 6: Polish

- [ ] ACC-010-T11 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`), the six repo checks, `check_privacy_manifest.py` and `check_network_symbols` on the Debug app; existing `PerformanceLayoutUITests` and `OneHandedUITests` still pass
- [ ] ACC-010-T12 Spec status, PosterBoard counts, delete the simulator and derived data
- [ ] ACC-010-T13 {device} On D1 (and D2 for iPad): quickstart "Device" steps 1-6 with the left hand

## Dependencies

T01 → T02 → (T03 ∥ T04) → T05, T06 → T07, T08; T09, T10 after T04; T11-T12 last. T13 needs a person and a device.

## Parallel examples

- T03 (package tests) alongside T04-T06 (app code).
- T08 and T09 share a file: write them together.

## Implementation strategy

MVP = Phases 1-3 (placement, setting, pad, corner, UI test); then the isolation and key-list checks.

## Analyze notes (speckit-analyze, 2026-11-14)

Coverage: R1 T04, T06, T09; R2 T06, T07; R3 T02, T03, T05, T07; R4 T05, T08; R5 T03, T07; R6 T02, T04, T09; R7 T04,
T10. S1 T03; S2 T07; S3 T08; S4 T10. 13 tasks, 100 % requirement coverage, no constitution conflict, no critical
issue.

- F1 (MEDIUM, applied): T05 did not state the readout alignment from the clarify session or the no-flip rule; added.
- F2 (MEDIUM, applied): R6 changes where SHOW-014's corner button sits in ACC-009's one-handed Left mode; T06 now says so
  (ACC-009-R5 only required it to stay in the status stack, clear of the cluster, which still holds).
- F3 (LOW, accepted): the UIX-007 split editor edge case has no own test: the split editor hosts the same
  `VisualizerView`, and T08 covers the output; nothing in the split panel is edge-anchored.
- F4 (LOW, accepted): VoiceOver order following the visual order (research ACC-010-D5) is SwiftUI's default and has
  no own assertion; identifiers and labels are asserted by T03 and T07.
