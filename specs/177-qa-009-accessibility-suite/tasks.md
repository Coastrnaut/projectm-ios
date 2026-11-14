# Tasks: QA-009 Accessibility Snapshot Suite

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/manifest.md](contracts/manifest.md), [quickstart.md](quickstart.md)

Task IDs carry the feature ID (`QA-009-T01…`). Simulator: "QA9 iPhone 17" (iOS 27.2). Every UI test ≤ 30 s
(owner rule 7). Simulator results are UI evidence only.

## Phase 1: Setup

- [X] QA-009-T01 Add DEBUG Settings anchors `.id("effectOrder")`, `.id("recordingQuality")`, `.id("recordingFrameRate")` in `Apps/projectM-iOS/Views/SettingsView.swift` and list them in the comment of `Apps/projectM-iOS/Debug/UITestSettingsSection.swift` (QA-009-R11, research D6) — Verified 2026-11-14: testEffectOrder*/testRecordingQuality*/testRecordingFrameRate* open Settings at these anchors and pass

## Phase 2: Foundational

- [X] QA-009-T02 Write the manifest `Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift`: `PrimaryScreen`, `RequiredControl`, `Layout` (`standard` = `UICTContentSizeCategoryL`, `ax3` = `UICTContentSizeCategoryAccessibilityXL`, `ax5` = `UICTContentSizeCategoryAccessibilityXXXL`), 13 screens with routes and ordered required controls, macros (MOD-010) noted as not built (QA-009-R1, contract M1) — Verified 2026-11-14: 13 screens, 53 identifiers; `scripts/qa009_manifest_check.py` OK
- [X] QA-009-T03 Make ACC-004's `systemDone` filter reusable (internal, not private) in `Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift` (research D2) — Verified 2026-11-14: build-for-testing succeeds; used by the new suite

## Phase 3: User Story 1 + 2 — required controls labelled and reachable, audit passes (P1)

**Independent test**: `PrimaryScreensAccessibilityUITests` default subset passes; a broken label or an unreachable control fails naming screen, layout and control.

- [X] QA-009-T04 [US1] [US2] Write `Apps/projectM-iOS/UITests/PrimaryScreensAccessibilityUITests.swift`: launch per layout, open each route, walk required controls (exists, label trimmed non-empty and ≠ identifier, wholly visible and hittable after at most one held drag ≤ 70 % of the visible area), run the audit per research D2 with the existing filters, failure messages per contract M3, 39 tests with AX3 skipped unless `QA009_FULL=1` (QA-009-R2-R7) — Verified 2026-11-14: default run skips the 13 AX3 tests; `TEST_RUNNER_QA009_FULL=1` runs them; failures name screen, layout and control (seen in every red run)
- [ ] QA-009-T05 [US1] [US2] Run the default subset on QA9; fix every defect found in the views (QA-009-R9) and list each fix in this file; record per-test and total times (S3: each ≤ 30 s, subset < 10 min)
- [ ] QA-009-T06 [US2] Run the full matrix once (`TEST_RUNNER_QA009_FULL=1`); fix AX3-only defects; record per-test times

## Phase 4: User Story 3 — identifiers checked without a simulator (P2)

- [X] QA-009-T07 [P] [US3] Write `scripts/qa009_manifest_check.py` (contract M4) and `QA009ManifestTests` in `scripts/test_scripts.py` (repository passes; a fixture with a renamed identifier fails naming it) (QA-009-R8) — Verified 2026-11-14: `python3 scripts/test_scripts.py` 162 tests OK (QA009ManifestTests 3)

## Phase 5: Polish

- [ ] QA-009-T08 Type-check budget build (`-warn-long-function-bodies=300`, `-warn-long-expression-type-checking=150`): no new warnings in the touched files
- [ ] QA-009-T09 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), privacy manifest and network symbols on the Debug app; update spec status, quickstart times; PosterBoard counts
- [ ] QA-009-T10 {device} VoiceOver and AX5 walk of the manifest screens on D1 (owner; extends ACC-004-T12 / ACC-006-T12)

## Fixes found by the suite (QA-009-R9)

1. MIDI Mappings rows (`MIDIMappingsView.swift`): at AX5 the name and "Not mapped" shared a row with Learn/Delete and wrapped into a half-width column about a screen tall; at standard size "Not mapped" ran into "Learn". A shared row layout now stacks the buttons below at accessibility sizes and leaves a gap at standard sizes (mapping, transport and scene rows).
2. Scene switcher rows (`SceneSwitcherView.swift`): the thumbnail ("Stack Of Rectangles") and play mark ("Play") were exposed as separate elements inside each row; now hidden (the row's value says "current").
3. Scene switcher backdrop: stayed in the accessibility tree as an unlabelled full-screen element despite `.accessibilityHidden(true)` (audit: "Element has no description"); now a described "Close scenes" button with an action.
4. Scene switcher placeholder: the system placeholder grey on the dark card failed contrast; now the secondary label colour.
5. Scene switcher highlighted row: "Cue 1" in secondary grey on the accent fill failed contrast; now primary.
6. Parameter inspector rows (`ParameterInspectorView.swift`), Storage sizes (`StorageUsageView.swift`) and the licence captions (`LicensesView.swift`, "MIT"): texts in the secondary grey "nearly passed" contrast; now primary.
7. `SceneSwitcherLayer.body` split into typed parts (type-check budget).

Open findings (not fixed here): the switcher's rows are reported not hittable by XCTest (a touch works; `hitTest: false` on entries 1 and 3); content behind the switcher stays in the accessibility tree (UIX-002). Both recorded in spec Clarifications.

## Dependencies

T01 → T02 → T04 → T05 → T06; T03 before T04; T07 after T02 (parallel with T04-T06); T08-T09 last.

## Implementation strategy

MVP = T01-T05 (default subset green). Then T06 (full matrix), T07, polish.
