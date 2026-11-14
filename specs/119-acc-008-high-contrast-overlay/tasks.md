# Tasks: ACC-008 High Contrast Overlay

**Input**: design documents in `specs/119-acc-008-high-contrast-overlay/` (spec, plan, research,
data-model, contracts/overlay-surface.md, quickstart)

**Tests**: requested by the roadmap row (accessibility unit and UI tests) and the spec (ACC-008-R8, R9,
S1-S5). Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; UI test under 30 s.

Format: `- [ ] ACC-008-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac
cannot finish.

## Phase 1: Setup

- [ ] ACC-008-T01 Generate the project and an own iOS 27.2 simulator ("ACC8 iPhone 17"), count
  PosterBoard reports, and record the baseline type-check warnings with
  `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150` (log
  `.autonomous/logs/acc-008/build0.log`).

## Phase 2: Foundational

- [ ] ACC-008-T02 Create `Apps/projectM-iOS/Views/OverlaySurface.swift`: `OverlayContrast` (normal 4.5,
  large 3.0, `scrimOpacity`, `increasedScrimOpacity` 1.0, tint 0x409CFF, prominent tint 0x0062CC,
  `scrim(increasedContrast:)`), the `OverlaySurface` modifier (material if included, black scrim, dark
  scheme, tint; reads `statusAppearance`), `overlaySurface(_:material:includesMaterial:)`,
  `overlayProminentTint()`, and the DEBUG `OverlaySurfaceProbe` (contract C4).

## Phase 3: User Story 1 - Controls over a bright preset (P1)

**Goal**: the controls' text meets the target over white. **Independent test**: the fixture rows for the
controls.

- [ ] ACC-008-T03 [US1] Write `Apps/projectM-iOS/Tests/OverlayContrastTests.swift`: fixture frames
  (white, black, gradient, noise), the twin rendering and glyph-core measure (research D1), and the
  controls' specimens (title, secondary times and tempo, tint button, bordered button, status symbol).
- [ ] ACC-008-T04 [US1] Move `ControlsBacking` in `Apps/projectM-iOS/Views/ControlsOverlay.swift` to
  `overlaySurface(RoundedRectangle(cornerRadius: 16), material: .thickMaterial)` (layout unchanged).
- [ ] ACC-008-T05 [US1] Scrim sweep test: the lightest 0.01 step where every specimen meets its target
  over white equals `OverlayContrast.scrimOpacity`; set the constant from it.

## Phase 4: User Story 2 - Badges, captions and notices (P1)

**Goal**: every audited element meets the target over all four frames. **Independent test**: the full
fixture table.

- [ ] ACC-008-T06 [US2] `statusBadgeBackground`'s material case uses the surface in
  `Apps/projectM-iOS/Views/StatusCues.swift` (opaque bordered case unchanged, now in the dark scheme too).
- [ ] ACC-008-T07 [P] [US2] Swap `.background(.regularMaterial, …)` for `.overlaySurface(…)` in
  `StatusCaptionView.swift`, `ShowControls.swift` (ShowNotice), `BackgroundNoticeView.swift`,
  `PermissionNoticeView.swift`, `SessionRecoveryOfferCard.swift`, `CaptureResultPanels.swift`,
  `SceneSwitcherView.swift`, `EmergencyBlackoutButton.swift` (all under `Apps/projectM-iOS/Views/`).
- [ ] ACC-008-T08 [US2] Same swap for the route explanation, banners and notices in
  `Apps/projectM-iOS/Views/VisualizerView.swift` (not in `body`); `overlayProminentTint()` on Restore
  (OutputBlackoutBadge) and on the recovery card's Reopen; critical tint on the camera badge's Stop
  (`CameraIndicator.swift`).
- [ ] ACC-008-T09 [US2] Extend the fixture table to every element of the audit (spec table; contract C1)
  over the four frames, plus Increase Contrast (opaque) rows and the elements kept as they are
  (performance overlay, paused label; ACC-008-R7); print each row; the table runs in under 10 s (S3).

## Phase 5: User Story 3 - Trust the measurement (P2)

- [ ] ACC-008-T10 [US3] Negative controls in `OverlayContrastTests.swift`: a 0x777777 label on the backing,
  and white and secondary text on the previous 45% backing over white, measure below 4.5:1; the "before"
  rows of the audit (material counted as transparent) are printed.
- [ ] ACC-008-T11 [US3] Unit tests for `OverlayContrast.scrim(increasedContrast:)` and the tint values'
  ratios on the scrim colour (computed, no rendering).

## Phase 6: Running app

- [ ] ACC-008-T12 Probe in `VisualizerView`'s `diagnostics` (not `body`) and
  `Apps/projectM-iOS/UITests/OverlayContrastUITests.swift`: `scrim:<level>` normally, `scrim:1.00` with
  `-uitestIncreaseContrast YES` (under 30 s).

## Phase 7: Polish

- [ ] ACC-008-T13 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; no new type-check warnings
  over the baseline; `grep` shows no `.regularMaterial`/`.ultraThinMaterial` backing left in the audited
  views (ACC-008-R3); the diff touches no renderer, compositor or audio file (ACC-008-R10).
- [ ] ACC-008-T14 Test runs on the own simulator: `projectM-iOSTests`, `OverlayContrastUITests`,
  `ColorBlindControlsUITests`, `StatusUITests`; PosterBoard count after; delete the simulator.
- [ ] ACC-008-T15 Record the measured table (before → after), the scrim level and the method in
  research D1/D2 and the spec status.
- [ ] ACC-008-T16 `{device}` D1 over the brightest presets, standard and Increase Contrast (quickstart D).

## Dependencies

T01 → T02 → (T03-T05) → (T06-T09) → (T10, T11) → T12 → T13-T15. T16 last stage. T07 files are
independent of each other.

## Parallel example

T07's eight files can be edited in any order; T10 and T11 are independent tests in one file (one writer).

## Implementation strategy

MVP is US1 (the controls). US2 extends the same surface; US3 proves the measure.
