# Tasks: ACC-006 Dynamic Type Inspector

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/dynamic-type-inspector.md
**Tests**: UI tests are the deliverable (R6); each < 30 s (owner rule 7). Simulator results are never
device evidence.

## Phase 1: Inspector and baseline (US3)

- [X] ACC-006-T01 [US3] Create `Apps/projectM-iOS/UITests/DynamicTypeInspectorUITests.swift`: ten
  screen groups × AX5/AX3, `.dynamicType` + `.textClipped` audit with `AuditFilter`, affordance
  helpers (`scrollTo`, `requireReachable`, `requireOnScreen`, `requireAcceptsInput`), survey switches
  `ACC006_SIZE` / `ACC006_SURVEY` (contract C1, C2; R6). — Verified 2026-11-13: DynamicTypeInspectorUITests (30 tests, 15 groups × AX5/AX3) builds and runs; final run 30/30 (full9)
- [X] ACC-006-T02 [US3] Run the suite at AX5 in survey mode on the unfixed app and record the baseline
  in spec.md (B1-B9). — Verified 2026-11-13: survey runs at AX5 on 08d7747 (survey-ax5, s3) recorded as B1-B9 in spec.md

## Phase 2: Fixes (US1, US2)

- [X] ACC-006-T03 [P] [US1] `Views/ControlsOverlay.swift`: stack status and tempo at AX sizes; names
  wrap to three lines (R1). — Verified 2026-11-13: testVisualizerControlsAX5/AX3 and testCameraNoticeAX5 pass with zero unfiltered issues; screenshots show stacked status/tempo and wrapped names
- [X] ACC-006-T04 [US2] `Views/ControlsOverlay.swift`: scroll fallback (a scroll view as tall as the measured content, layout
  priority and auto-hide restart on drag (R2; research D2). — Verified 2026-11-13: testCameraNoticeAX5 reaches Settings by scrolling the controls; UserPresetEditingUITests AX5 and VisualizerUITests (7) pass; ACC-004 controls/showRow audits pass with the standard-size tree kept
- [X] ACC-006-T05 [P] [US1] `Views/TempoControls.swift`: one line and 0.7 scale only at standard sizes. — Verified 2026-11-13: testVisualizerControlsAX5 and testCameraNoticeAX5 (readout no longer reported clipped)
- [X] ACC-006-T06 [P] [US1] `Views/PermissionNoticeView.swift`: vertical layout at AX sizes (R1). — Verified 2026-11-13: testCameraNoticeAX5/AX3, testLocalNetworkNoticeAX5/AX3; PermissionAuditUITests 4/4, CameraPrivacyStatusUITests 1/1
- [X] ACC-006-T07 [P] [US1] `Views/UserPresetEditorView.swift`: wrapping Name field at AX sizes, Return
  → space (R1, R3). — Verified 2026-11-13: testPresetEditorAX5/AX3 (name and text accept input, no clipped-text issue); UserPresetEditingUITests 4/4
- [X] ACC-006-T08 [P] [US2] `Views/SceneRepairReportView.swift`: buttons scroll with the report at AX
  sizes (R2). — Verified 2026-11-13: testRepairSheetAX5/AX3 (last group and all three buttons reached); SceneRepairUITests 1/1
- [X] ACC-006-T09 [P] [US1] `Packages/CaptureUI`: `AudioRouteIndicator` text and `TransportBar` title
  wrap to three lines at AX sizes (R1). — Verified 2026-11-13: swift test --package-path Packages/CaptureUI 59/59; route and title wrap in the AX5 screenshots; TransportUITests 3/3, RouteIndicatorUITests 1/1

## Phase 3: Filters, verification, docs (US3)

- [X] ACC-006-T10 [US3] Re-run ACC-004's `AccessibilityScreensUITests`; remove its Dynamic Type filters
  that no longer fire; update `specs/082-acc-004-voiceover-scene-browser/contracts/accessibility-tree.md`
  C3 and this feature's contract C2 outcome (R7). — Verified 2026-11-13: both ACC-004 filters removed, re-run, came back (acc004.log), restored with the re-check noted; "Cues" filter added (pushed-off artefact); AccessibilityScreensUITests 7/7 (regr4)
- [ ] ACC-006-T11 [US3] Verify: inspector suite at AX5 and AX3 twice with zero unfiltered issues and
  every test < 30 s (S1-S3); survey at AX1, AX2, AX4 and the largest standard size; regression suites
  of changed screens and `projectM-iOSTests`, CaptureUI package tests (S4); compliance, docs, motion,
  permission catalog and script checks; Release build has no inspector code (R8, by construction: the
  suite is test-only). — Partly verified 2026-11-13: zero unfiltered issues in the final run (30/30) and
  29/30 in the run before the last controls change (not two identical consecutive runs); surveys at AX1,
  AX2, AX4, XXXL pass (controls, camera notice, preset editor); regression suites pass (ACC-004 7/7,
  Visualizer 7/7, UserPresetEditing 4/4, Transport 3/3, PermissionAudit 4/4, 13 more suites, projectM-iOSTests
  387/387, CaptureUI 59/59); check_compliance, validate_docs, check_motion_policy,
  check_permission_catalog OK; test_scripts 147 OK. **Not met: S3** (each test < 30 s): 14-100 s per test
  at load average 57-600 from other agents (contract C1 splits keep each test to one launch and one deep scroll).
- [ ] ACC-006-T12 {device} D1 at AX5 and an iPad at AX5 (portrait and landscape): the quickstart's
  device walk; record in `docs/test-reports/accessibility-dynamic-type.md` (S5).

## Dependencies

T01 → T02 → T03-T09 (parallel, different files except T03/T04) → T10 → T11 → T12 (last, device).

## Analysis (speckit-analyze, 2026-11-13)

Cross-check of spec, plan, contract and tasks; fixes applied in the same commit:

| ID | Severity | Finding | Fix |
|---|---|---|---|
| A1 | High | The suite named `UICTContentSizeCategoryAccessibilityL` "AX3"; in UIKit's order it is AX2 (M, L, XL, XXL, XXXL = AX1-AX5) | middle size is `…AccessibilityXL` in the suite, data model and quickstart |
| A2 | Medium | The `controls` element must stay an "other" element for every suite (`otherElements["controls"]`); a scroll view at the root would change its type at AX sizes | plan D2 implementation wraps the content or its scroll fallback in a plain container; T04 verifies with the existing suites |
| A3 | Low | R4's alternative clause (VoiceOver actions for swipe and context-menu actions) is decided in Clarifications but not tested by the inspector | covered by ACC-004's suite (rotor actions exist); stated in contract C1 ("the inspector checks the visible ones") |
| A4 | Low | Every requirement maps to a task: R1 → T03, T05-T07, T09; R2 → T04, T08; R3 → T07, T01; R4 → T01; R5 → T11 (regression suites); R6 → T01; R7 → T10; R8 → T11 | none |

No constitution conflicts. Coverage: 8/8 requirements, 5/5 success criteria have tasks.
