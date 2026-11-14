# Tasks: ACC-008 High Contrast Overlay

**Input**: design documents in `specs/119-acc-008-high-contrast-overlay/` (spec, plan, research,
data-model, contracts/overlay-surface.md, quickstart)

**Tests**: requested by the roadmap row (accessibility unit and UI tests) and the spec (ACC-008-R8, R9,
S1-S5). Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; UI test under 30 s.

Format: `- [ ] ACC-008-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac
cannot finish.

## Phase 1: Setup

- [X] ACC-008-T01 Generate the project and an own iOS 27.2 simulator ("ACC8 iPhone 17"), count
  PosterBoard reports, and record the baseline type-check warnings with
  `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150` (log
  `.autonomous/logs/acc-008/build0.log`). — Verified 2026-11-14: build0.log, 9 baseline warnings (all pre-existing), simulator 4757BCDB, 25 PosterBoard reports.

## Phase 2: Foundational

- [X] ACC-008-T02 Create `Apps/projectM-iOS/Views/OverlaySurface.swift`: `OverlayContrast` (normal 4.5,
  large 3.0, `scrimOpacity`, `increasedScrimOpacity` 1.0, tint 0xB8DCFF (first 0x409CFF; research D4), prominent tint 0x0062CC,
  `scrim(increasedContrast:)`), the `OverlaySurface` modifier (material if included, black scrim, dark
  scheme, tint; reads `statusAppearance`), `overlaySurface(_:material:includesMaterial:)`,
  `overlayProminentTint()`, and the DEBUG `OverlaySurfaceProbe` (contract C4). — Verified 2026-11-14: OverlaySurface.swift builds; testScrimLevelsAndTintRatios passes.

## Phase 3: User Story 1 - Controls over a bright preset (P1)

**Goal**: the controls' text meets the target over white. **Independent test**: the fixture rows for the
controls.

- [X] ACC-008-T03 [US1] Write `Apps/projectM-iOS/Tests/OverlayContrastTests.swift`: fixture frames
  (white, black, gradient, noise), the twin rendering and glyph-core measure (research D1), and the
  controls' specimens (title, secondary times and tempo, tint button, bordered button, status symbol). — Verified 2026-11-14: OverlayContrastTests.testControlsMeetTheTargetOverEveryFrame passes (32 rows, 1.3 s).
- [X] ACC-008-T04 [US1] Move `ControlsBacking` in `Apps/projectM-iOS/Views/ControlsOverlay.swift` to
  `overlaySurface(RoundedRectangle(cornerRadius: 16), material: .thickMaterial)` (layout unchanged). — Verified 2026-11-14: controls rows pass; ColorBlindControlsUITests and StatusUITests pass.
- [X] ACC-008-T05 [US1] Scrim sweep test: the lightest 0.01 step where every specimen meets its target
  over white equals `OverlayContrast.scrimOpacity`; set the constant from it. — Verified 2026-11-14: testScrimIsTheLightestPassingLevel passes (0.83 lightest, 0.84 with headroom; fails at 0.82).

## Phase 4: User Story 2 - Badges, captions and notices (P1)

**Goal**: every audited element meets the target over all four frames. **Independent test**: the full
fixture table.

- [X] ACC-008-T06 [US2] `statusBadgeBackground`'s material case uses the surface in
  `Apps/projectM-iOS/Views/StatusCues.swift` (opaque bordered case unchanged, now in the dark scheme too). — Verified 2026-11-14: badge rows and ColorBlindControlsUITests (3) pass.
- [X] ACC-008-T07 [P] [US2] Swap `.background(.regularMaterial, …)` for `.overlaySurface(…)` in
  `StatusCaptionView.swift`, `ShowControls.swift` (ShowNotice), `BackgroundNoticeView.swift`,
  `PermissionNoticeView.swift`, `SessionRecoveryOfferCard.swift`, `CaptureResultPanels.swift`,
  `SceneSwitcherView.swift`, `EmergencyBlackoutButton.swift` (all under `Apps/projectM-iOS/Views/`). — Verified 2026-11-14: grep shows no material backing left in the listed views; notices/panels rows pass.
- [X] ACC-008-T08 [US2] Same swap for the route explanation, banners and notices in
  `Apps/projectM-iOS/Views/VisualizerView.swift` (not in `body`); `overlayProminentTint()` on Restore
  (OutputBlackoutBadge) and on the recovery card's Reopen; critical tint on the camera badge's Stop
  (`CameraIndicator.swift`). — Verified 2026-11-14: testNoticesPanelsAndCardsMeetTheTargetOverEveryFrame and the badge rows pass.
- [X] ACC-008-T09 [US2] Extend the fixture table to every element of the audit (spec table; contract C1)
  over the four frames, plus Increase Contrast (opaque) rows and the elements kept as they are
  (performance overlay, paused label; ACC-008-R7); print each row; the table runs in under 10 s (S3). — Verified 2026-11-14: 172 rows (43 styles × four frames) plus 41 Increase Contrast rows pass; the four table tests take 1.3-3.8 s each, the whole class 11 s.

## Phase 5: User Story 3 - Trust the measurement (P2)

- [X] ACC-008-T10 [US3] Negative controls in `OverlayContrastTests.swift`: a 0x777777 label on the backing,
  and white and secondary text on the previous 45% backing over white, measure below 4.5:1; the "before"
  rows of the audit (material counted as transparent) are printed. — Verified 2026-11-14: testNegativeControlLowContrastLabelFails (3.02 over white) and testPreviousBackingsMissTheTarget (3.17, 1.86, 1.00, 1.00) pass.
- [X] ACC-008-T11 [US3] Unit tests for `OverlayContrast.scrim(increasedContrast:)` and the tint values'
  ratios on the scrim colour (computed, no rendering). — Verified 2026-11-14: testScrimLevelsAndTintRatios and testMeasureMatchesTheWCAGFormula pass.

## Phase 6: Running app

- [X] ACC-008-T12 Probe in `VisualizerView`'s `diagnostics` (not `body`) and
  `Apps/projectM-iOS/UITests/OverlayContrastUITests.swift`: `scrim:<level>` normally, `scrim:1.00` with
  `-uitestIncreaseContrast YES` (under 30 s). — Verified 2026-11-14: OverlayContrastUITests 2/2 (5.8 s, 6.3 s).

## Phase 7: Polish

- [X] ACC-008-T13 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; no new type-check warnings
  over the baseline; `grep` shows no `.regularMaterial`/`.ultraThinMaterial` backing left in the audited
  views (ACC-008-R3); the diff touches no renderer, compositor or audio file (ACC-008-R10). — Verified 2026-11-14: six scripts OK (153 script tests), no type-check warning in changed code (three 161-165 ms warnings in untouched expressions are load noise), no renderer/audio file in the diff.
- [X] ACC-008-T14 Test runs on the own simulator: `projectM-iOSTests`, `OverlayContrastUITests`,
  `ColorBlindControlsUITests`, `StatusUITests`; PosterBoard count after; delete the simulator. — Verified 2026-11-14: projectM-iOSTests 534/534 (25 s), OverlayContrastUITests 2, ColorBlindControlsUITests 3, StatusUITests 8 (each < 17 s); PosterBoard 25 → 25; simulator deleted.
- [X] ACC-008-T15 Record the measured table (before → after), the scrim level and the method in
  research D1/D2 and the spec status. — Verified 2026-11-14: spec After table, research D1, D2, D4.
- [ ] ACC-008-T16 `{device}` D1 over the brightest presets, standard and Increase Contrast (quickstart D).

## Dependencies

T01 → T02 → (T03-T05) → (T06-T09) → (T10, T11) → T12 → T13-T15. T16 last stage. T07 files are
independent of each other.

## Parallel example

T07's eight files can be edited in any order; T10 and T11 are independent tests in one file (one writer).

## Implementation strategy

MVP is US1 (the controls). US2 extends the same surface; US3 proves the measure.
