# Tasks: UIX-007 Split Preview/Editor

**Input**: Design documents from `specs/205-uix-007-split-preview-editor/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/split-editor.md, quickstart.md

Tests are requested by the spec (UIX-007-S1-S3). Budgets (owner rule 7): unit test ≤ 10 s, UI test < 30 s.

## Phase 1: Setup

- [X] UIX-007-T01 Create an iPad simulator "UIX7 iPad" (iOS 27.2) and run `xcodegen generate` in the worktree (no file change) — Verified 2026-11-14: `simctl create` AF46A8D8, `xcodegen generate` OK

## Phase 2: Foundational (geometry)

- [X] UIX-007-T02 [P] Implement `SplitEditorLayout` in `Packages/ShowControl/Sources/ShowControl/SplitEditorLayout.swift` per data-model.md: `fits` (≥ 664 pt), `editorWidth` clamped to "320–min(560, container − 24 − 320)", non-finite → 400, `outputPane`, `scale`, `outputRect` (exact output aspect, centred), `snapped` (snaps 320/400/480 within 24 pt), `nextSnap`, `previousSnap`, `snapName` — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` 94 tests pass (SplitEditorLayoutTests 5, sweep of 216 layouts)
- [X] UIX-007-T03 [P] Write `Packages/ShowControl/Tests/ShowControlTests/SplitEditorLayoutTests.swift`: sweep editor widths (min, each snap, max, odd values 333.3/517.7, out-of-range, NaN) × window sizes (13" landscape 1376×1032, 13" portrait 1032×1376, 11" portrait 834×1210, a 700-wide window, an odd 1024.5×700.25) × output aspects (window, 16:9, 4:3); assert aspect within 1e-6, rect inside pane, rect touches the pane on one axis, `fits` false below 664; snapping and step tests (UIX-007-S1) — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` 94 tests pass (SplitEditorLayoutTests 5, sweep of 216 layouts)

## Phase 3: User Story 1 — Edit beside the live output (P1)

**Independent test**: iPad simulator, open Settings: `splitEditor` exists, no sheet, the output frame lies in the pane.

- [X] UIX-007-T04 [P] [US1] Add `SplitEditorSetting` in `Apps/projectM-iOS/Coordinators/SplitEditorSetting.swift` (key `settings.splitEditor.width`, Double, absent/invalid → 400, `-uitestResetNotice` removes it, DEBUG `-uitestSplitEditorWidth <pt>`) and one `splitEditor` property in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` — Verified 2026-11-14: `SplitEditorSettingTests` 4/4 and `LibraryBackupAppTests` 5/5 on the UIX7 iPad simulator
- [X] UIX-007-T05 [P] [US1] Add the key to `ALLOWED_KEYS` in `scripts/run_device_tests.py` and to `LibrarySettingsPolicy.excludedKeys` in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` — Verified 2026-11-14: `LibraryBackupAppTests.testIncludedKeysAndFolderNamesAgreeWithTheStores`, `SplitEditorSettingTests.testKeyIsExcludedFromBackupsAndErasedWithSettings`, LibraryBackup package 77 tests
- [X] UIX-007-T06 [US1] Build `Apps/projectM-iOS/Views/SplitEditorHost.swift`: host (regular width + `fits` + `showSettings`), trailing safe-area inset with divider and editor, environment `SplitOutputPlacement`, `.splitOutputScaled()` modifier, `splitEditorClose` environment, DEBUG probe `splitOutputFrame` (contract C1, C3, C4) — Verified 2026-11-14: `SplitEditorUITests` 2/2 on the iPad simulator (probe C4 read from UIKit)
- [X] UIX-007-T07 [US1] Wire `Apps/projectM-iOS/Views/VisualizerView.swift` (wrap layers, scale visual, Settings view property shared by sheet and pane, sheet binding false while split) and Done in `Apps/projectM-iOS/Views/SettingsView.swift` (`splitEditorClose` else `dismiss()`) — Verified 2026-11-14: `SplitEditorUITests` (Done closes, R8); `LayerInspectorUITests` 2/2 and `SettingsUITests.testPerformanceOverlay` pass through the split on iPad
- [X] UIX-007-T08 [P] [US1] Write `Apps/projectM-iOS/Tests/SplitEditorSettingTests.swift`: default 400, stored value round trip, invalid → 400, key listed in FILE-005 excluded keys — Verified 2026-11-14: `SplitEditorSettingTests` 4/4

## Phase 4: User Story 2 — Resize without distortion (P1)

**Independent test**: drag the divider; the probe's frame aspect equals the window aspect within 1% and its width changed.

- [X] UIX-007-T09 [US2] Divider drag (live clamp, snap on release, store) in `Apps/projectM-iOS/Views/SplitEditorHost.swift` (contract C2) — Verified 2026-11-14: `SplitEditorUITests.testDraggingTheDividerNeverDistortsTheOutput` (drag widens, drag back snaps to 400)
- [X] UIX-007-T10 [US2] Write `Apps/projectM-iOS/UITests/SplitEditorUITests.swift` on the iPad simulator: open Settings → split, no sheet, probe aspect = window aspect (1%), frame inside the pane; drag divider → width changes, aspect unchanged; the slot's bounds stay the window size (UIX-007-R4); the controls' Settings button lies inside the output pane (UIX-007-R9); Done closes and the output fills the window again (UIX-007-R8, S2) — Verified 2026-11-14: `SplitEditorUITests` 2/2 pass on the UIX7 iPad simulator (11.1 s, 11.2 s)

## Phase 5: User Story 3 — VoiceOver resizing (P2)

- [X] UIX-007-T11 [US3] Divider accessibility (label, value with snap name, adjustable increment/decrement through snaps) in `Apps/projectM-iOS/Views/SplitEditorHost.swift`; the UI test asserts its label and value (contract C2) — Verified 2026-11-14: `SplitEditorUITests` asserts label "Editor width" and value "400 points, Standard"; stepping in `SplitEditorLayoutTests.testSteppingThroughSnapPoints`

## Phase 6: Polish

- [X] UIX-007-T12 Type-check budget run (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) on the changed app files; repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), `check_privacy_manifest`, `check_network_symbols`; Settings UI test on iPhone still a sheet (UIX-007-S3) — Verified 2026-11-14: type-check run (new code under budget; `VisualizerView.layers` 173-231 ms under load avg 48-138 vs 167 ms at baseline, see final report), the six repo checks, `check_privacy_manifest`, `check_network_symbols` OK; iPhone 17 simulator: SettingsUITests, VisualizerUITests (2), FrameCaptureUITests, LayerInspectorUITests, PerformanceLayoutUITests pass, SplitEditorUITests skip (compact width)
- [ ] UIX-007-T13 {device} D2 (iPad Pro M5): quickstart device steps 1-5 (UIX-007-S4)

## Dependencies

T02 → T03, T06; T04 → T06; T06 → T07 → T09 → T10; T11 after T09. T05, T08 parallel after T04.

## Parallel examples

- T02 with T04 and T05 (different files).
- T03 with T08.

## Implementation strategy

MVP: Phases 2-3 (split opens, output undistorted at the stored width); then the drag (US2) and VoiceOver (US3).

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R10 and S1-S4 each map to at least one task (R1 T06/T07/T10, R2 T02/T03, R3 T02/T03/T10,
R4 T10 bounds probe, R5 T09/T10, R6 T11, R7 T04/T05/T08, R8 T07/T10, R9 T06/T10, R10 T06). No
constitution conflicts. Fixes applied: R4 and R9 had no test (MEDIUM): the probe now carries the slot's
bounds size (contract C4) and T10 asserts R4 and R9.
