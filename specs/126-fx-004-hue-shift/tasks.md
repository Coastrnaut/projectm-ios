# Tasks: FX-004 Hue Shift

**Input**: design documents in `specs/126-fx-004-hue-shift/` (spec, plan, research, data-model,
contracts/hue-shift.md, quickstart)

**Tests**: requested by the roadmap row (snapshot, shader unit, device GPU) and the spec (FX-004-S1-S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute; UI test under 30 s.

Format: `- [ ] FX-004-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-004/`.

## Phase 1: Setup

- [X] FX-004-T01 Audit: confirm no picture hue rotation exists (`grep -rli hue` over `Packages/*/Sources` and
  `Apps/projectM-iOS`) and that FX-003's grade, guard and setting are as described; record it in spec.md's
  audit. — Verified 2026-11-14: grep -rli hue over Packages/*/Sources and Apps/projectM-iOS (only SHD-002's HSV node, VisualPalette, ACC-003 ramp); recorded in spec.md's audit.

## Phase 2: Foundational

- [X] FX-004-T02 Extend `Packages/Compositor/Sources/Compositor/ColorGrade.swift`: field `hue` "−180…180
  (0)", step hint 1, `clamped` ("NaN → 0, out of range → nearest bound"), Codable with a missing `hue` → 0,
  `ColorGradeCoefficients.hueMatrix` (T00, T01, T10, T11 of research FX-004-D1, typed steps) and `hueFlag = 32`,
  and the reference step 6 in `apply` (D1 steps 1-4, the gamut step D3), after saturation (D4). — Verified 2026-11-14: ColorGrade.swift builds in the Linux shape and on the host; HueShiftReferenceTests 10/10 (logs-fx-004/reference-linux-shape.log).
- [X] FX-004-T03 [P] Write `Packages/Compositor/Tests/CompositorTests/HueShiftReferenceTests.swift` (CPU, Linux
  shape): the red reference table of D6 (0, 30, 90, 120, 180, 240, −120), greys bit-identical for every angle
  (0…1, over-range, 0), luminance kept within 1e-9 over ≥ 10,000 sampled colours and angles in under 2 s
  (FX-004-S3), rows of M sum to 1 and wᵀM = wᵀ, ±180 equal, hue 0 → flag off and FX-003 vectors unchanged,
  commutation with saturation away from clamps, composition with every other operator, clamping and decoding. — Verified 2026-11-14: HueShiftReferenceTests 10/10 plus ColorGradeReferenceTests 8/8 in the Linux shape, 0.037 s (10,000 samples, worst luminance error ≤ 1e-9, 1,000 greys exact).
- [X] FX-004-T04 Extend `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`: `CMPGrade.hue` (float4
  after `tone`, 64 bytes), `cmp_grade` step 6 behind flag 32, `GradeBlock.hue`; update the GradeBlock layout test
  in `Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift` to 64 bytes. — Verified 2026-11-14: testGradeBlockLayoutMatchesTheShader (64 bytes, hue at 32) and HueShiftOutputTests 5/5 (logs-fx-004/hue-gpu.log); full Compositor suite 426 + 3 pass in 10.5 s (logs-fx-004/compositor-full.log).

## Phase 3: User Story 1 - Shift the colours (P1, the acceptance)

**Goal**: grey ramp neutral, red patch predictable. **Independent test**: `HueShiftOutputTests`.

- [X] FX-004-T05 [US1] Write `Packages/Compositor/Tests/CompositorTests/HueShiftOutputTests.swift` (GPU,
  through `OutputPassRig`, sRGB and half-float formats): grey ramp (0…1 plus 1.5, 2, 4) at 30, 90, 180, −120° —
  every pixel's channels exactly equal and equal to the hue-0 output within one 8-bit step / 0.002 (FX-004-S1);
  red patch at 0, 120, 240° matches the reference then `ToneMap.map` within the same tolerances (FX-004-S2);
  a mixed image matches the reference at 30° with other operators active. — Verified 2026-11-14: testGreyRampStaysNeutralAtEveryAngle (37/37 greys spread 0 and bit-identical to hue 0 at 30/90/180/−120°, both formats), testRedPatchRotatesPredictably (errors 0.00014 half, 0.0018 sRGB), testMixedImageMatchesTheReferenceWithOtherOperators.
- [X] FX-004-T06 [P] [US1] Add `effect.colorGrade.hue` ("Hue (degrees)", unit `.degrees`, after saturation) to
  `Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift` and `grade(from:)`; update
  `Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift` (six descriptors). — Verified 2026-11-14: ColorGradeCatalogTests 3/3 (six descriptors, hue unit degrees, grade(from:) clamps −500 → −180).
- [X] FX-004-T07 [US1] App setting: `hue` and `settings.colorGrade.hue` in
  `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift` (in `allKeys`, so the UI-test reset includes it;
  reset; readout `hueText` "+30°" / "0°" / "−120°"); the key in
  `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (FILE-005 included keys; FILE-011's
  "Settings" erase category is derived from them in `LibraryErasePolicy.settingsCategoryKeys`) and
  `scripts/run_device_tests.py` (privacy allow-list). — Verified 2026-11-14: ColorGradeSettingTests.testHuePersistsClampsAndResets (key in allKeys, persisted, clamped, NaN/string/Bool → 0, reset removes it); LibraryBackup 44 tests pass (logs-fx-004/librarybackup.log); script tests 153 OK; LibraryEraseAppTests and LibraryBackupAppTests pass in the app run (578/578).
- [X] FX-004-T08 [US1] Settings → Color: a "Hue" row (`colorHueSlider`, VoiceOver step 10°, spoken via a new
  `SpokenUnit.signedDegrees` "plus 30 degrees") in `Apps/projectM-iOS/Views/ColorGradeSection.swift` and
  `Apps/projectM-iOS/Views/AccessibleParameter.swift`; footer unchanged. — Verified 2026-11-14: ColorGradeSettingTests.testHueReadoutSpokenValueAndSlider ("plus 30 degrees", 36 steps, one swipe = 10°); ColorGradeUITests passes twice (24.0 s, 25.6 s; logs-fx-004/ui-tests-final-1.log, -2.log); no long-body or long-expression warning in the changed files (logs-fx-004/app-tests.log).
- [X] FX-004-T09 [US1] App tests: hue persistence, read rule, reset and readouts in
  `Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift`; spoken value and ACC-012's `effective(_:clamp:)`
  leaving the hue unchanged under Strict (FX-004-R6) in the same file; the Hue slider's presence
  in `Apps/projectM-iOS/UITests/ColorGradeUITests.swift`; backup/erase key tests still pass. — Verified 2026-11-14: app unit tests 578/578 on the own iOS 27.2 simulator "FX4 iPhone 17" (27.5 s; logs-fx-004/app-tests.log) incl. testSafetyProfileDoesNotCapTheHue; ColorGradeUITests passes (the test now scrolls from the Hue row's title, since the shared reveal drag landed on the Hue slider's thumb).

## Phase 4: User Story 2 - Zero is exactly "off" (P1)

- [X] FX-004-T10 [US2] In `HueShiftOutputTests.swift`: hue 0 with every other control neutral is bit-identical to
  the bypass output, and hue 0 with other controls active is bit-identical to the same grade's FX-003 output
  (FX-004-S4); FX-003's `ColorGradeOutputTests` still pass. — Verified 2026-11-14: testHueZeroIsBitIdenticalToFX003 (bit patterns equal, both formats); ColorGradeOutputTests 7/7.
- [X] FX-004-T11 [P] [US2] RenderGoldens unchanged: `swift test --package-path Packages/RenderGoldens`. — Verified 2026-11-14: swift test --package-path Packages/RenderGoldens: 39 tests pass, no golden file changed (logs-fx-004/rendergoldens.log).

## Phase 5: User Story 3 - Flash limiter (P1)

- [X] FX-004-T12 [US3] In `HueShiftOutputTests.swift`: with hue 120° the composite flash guard engages on frames
  flashing above the threshold, and a steady colour's measured luminance is the same with and without the shift
  (FX-004-S5). — Verified 2026-11-14: testFlashLimiterMeasuresTheShiftedColour: black↔white 0.095 with and without +120°; black↔blue 1.0 unshifted, 0.169 at +120° (turned red).

## Phase 6: Polish

- [X] FX-004-T13 Amend `docs/adr/0050-output-color-grade.md` (operator 6, 64-byte block, red reference, grey
  proof) and run `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
  `check_status_events`, `test_scripts`. — Verified 2026-11-14: ADR-0050 amended; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK.
- [X] FX-004-T14 App on an own iOS 27.2 simulator: `-only-testing:projectM-iOSTests` and
  `-only-testing:projectM-iOSUITests/ColorGradeUITests`, with the long-body warnings flags; LibraryBackup package
  tests; Compositor package suite under 1 minute. — Verified 2026-11-14: app unit 578/578 and ColorGradeUITests pass on the own simulator with the warning flags; LibraryBackup 44, Compositor 426 + 3 (10.5 s), RenderGoldens 39 pass.
- [ ] FX-004-T15 `{device}` (open: needs D1) On D1 (quickstart step 5): hue +120 on the Photo visual, greys unchanged, frame rate
  unchanged.

Note (2026-11-14, not FX-004's): `SettingsUITests.testLicensesScreen` and
`testReduceFlashingFollowsReduceMotionAndPersists` fail on this simulator with and without the Hue row (rerun with
the row removed: same two failures; logs-fx-004/ui-settings-without-hue-row.log), so they predate this feature.
`SensorySafetyUITests` (below the Color section) passes with the Hue row.

## Dependencies

T01 → T02 → (T03, T04) → T05, T10, T12; T06 after T02; T07 → T08 → T09; T11 after T04; T13-T14 last; T15 after
integration.

## Parallel examples

T03 with T04; T06 with T07; T11 with T09.

## Implementation strategy

MVP = Phases 1-3 (acceptance). Phases 4-5 are tests on the same code; Phase 6 closes the records.
