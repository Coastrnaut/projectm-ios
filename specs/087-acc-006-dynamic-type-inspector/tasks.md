# Tasks: ACC-006 Dynamic Type Inspector

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/dynamic-type-inspector.md
**Tests**: UI tests are the deliverable (R6); each < 30 s (owner rule 7). Simulator results are never
device evidence.

## Phase 1: Inspector and baseline (US3)

- [ ] ACC-006-T01 [US3] Create `Apps/projectM-iOS/UITests/DynamicTypeInspectorUITests.swift`: ten
  screen groups × AX5/AX3, `.dynamicType` + `.textClipped` audit with `AuditFilter`, affordance
  helpers (`scrollTo`, `requireReachable`, `requireOnScreen`, `requireAcceptsInput`), survey switches
  `ACC006_SIZE` / `ACC006_SURVEY` (contract C1, C2; R6).
- [ ] ACC-006-T02 [US3] Run the suite at AX5 in survey mode on the unfixed app and record the baseline
  in spec.md (B1-B9).

## Phase 2: Fixes (US1, US2)

- [ ] ACC-006-T03 [P] [US1] `Views/ControlsOverlay.swift`: stack status and tempo at AX sizes; names
  wrap to three lines (R1).
- [ ] ACC-006-T04 [US2] `Views/ControlsOverlay.swift`: `ViewThatFits` scroll fallback with layout
  priority and auto-hide restart on drag (R2; research D2).
- [ ] ACC-006-T05 [P] [US1] `Views/TempoControls.swift`: one line and 0.7 scale only at standard sizes.
- [ ] ACC-006-T06 [P] [US1] `Views/PermissionNoticeView.swift`: vertical layout at AX sizes (R1).
- [ ] ACC-006-T07 [P] [US1] `Views/UserPresetEditorView.swift`: wrapping Name field at AX sizes, Return
  → space (R1, R3).
- [ ] ACC-006-T08 [P] [US2] `Views/SceneRepairReportView.swift`: buttons scroll with the report at AX
  sizes (R2).
- [ ] ACC-006-T09 [P] [US1] `Packages/CaptureUI`: `AudioRouteIndicator` text and `TransportBar` title
  wrap to three lines at AX sizes (R1).

## Phase 3: Filters, verification, docs (US3)

- [ ] ACC-006-T10 [US3] Re-run ACC-004's `AccessibilityScreensUITests`; remove its Dynamic Type filters
  that no longer fire; update `specs/082-acc-004-voiceover-scene-browser/contracts/accessibility-tree.md`
  C3 and this feature's contract C2 outcome (R7).
- [ ] ACC-006-T11 [US3] Verify: inspector suite at AX5 and AX3 twice with zero unfiltered issues and
  every test < 30 s (S1-S3); survey at AX1, AX2, AX4 and the largest standard size; regression suites
  of changed screens and `projectM-iOSTests`, CaptureUI package tests (S4); compliance, docs, motion,
  permission catalog and script checks; Release build has no inspector code (R8, by construction: the
  suite is test-only).
- [ ] ACC-006-T12 {device} D1 at AX5 and an iPad at AX5 (portrait and landscape): the quickstart's
  device walk; record in `docs/test-reports/accessibility-dynamic-type.md` (S5).

## Dependencies

T01 → T02 → T03-T09 (parallel, different files except T03/T04) → T10 → T11 → T12 (last, device).
