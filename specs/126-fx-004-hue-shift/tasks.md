# Tasks: FX-004 Hue Shift

**Input**: design documents in `specs/126-fx-004-hue-shift/` (spec, plan, research, data-model,
contracts/hue-shift.md, quickstart)

**Tests**: requested by the roadmap row (snapshot, shader unit, device GPU) and the spec (FX-004-S1-S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute; UI test under 30 s.

Format: `- [ ] FX-004-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-004/`.

## Phase 1: Setup

- [ ] FX-004-T01 Audit: confirm no picture hue rotation exists (`grep -rli hue` over `Packages/*/Sources` and
  `Apps/projectM-iOS`) and that FX-003's grade, guard and setting are as described; record it in spec.md's
  audit.

## Phase 2: Foundational

- [ ] FX-004-T02 Extend `Packages/Compositor/Sources/Compositor/ColorGrade.swift`: field `hue` "−180…180
  (0)", step hint 1, `clamped` ("NaN → 0, out of range → nearest bound"), Codable with a missing `hue` → 0,
  `ColorGradeCoefficients.hueMatrix` (T00, T01, T10, T11 of research FX-004-D1, typed steps) and `hueFlag = 32`,
  and the reference step 6 in `apply` (D1 steps 1-4, the gamut step D3), after saturation (D4).
- [ ] FX-004-T03 [P] Write `Packages/Compositor/Tests/CompositorTests/HueShiftReferenceTests.swift` (CPU, Linux
  shape): the red reference table of D6 (0, 30, 90, 120, 180, 240, −120), greys bit-identical for every angle
  (0…1, over-range, 0), luminance kept within 1e-9 over ≥ 10,000 sampled colours and angles in under 2 s
  (FX-004-S3), rows of M sum to 1 and wᵀM = wᵀ, ±180 equal, hue 0 → flag off and FX-003 vectors unchanged,
  commutation with saturation away from clamps, composition with every other operator, clamping and decoding.
- [ ] FX-004-T04 Extend `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`: `CMPGrade.hue` (float4
  after `tone`, 64 bytes), `cmp_grade` step 6 behind flag 32, `GradeBlock.hue`; update the GradeBlock layout test
  in `Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift` to 64 bytes.

## Phase 3: User Story 1 - Shift the colours (P1, the acceptance)

**Goal**: grey ramp neutral, red patch predictable. **Independent test**: `HueShiftOutputTests`.

- [ ] FX-004-T05 [US1] Write `Packages/Compositor/Tests/CompositorTests/HueShiftOutputTests.swift` (GPU,
  through `OutputPassRig`, sRGB and half-float formats): grey ramp (0…1 plus 1.5, 2, 4) at 30, 90, 180, −120° —
  every pixel's channels exactly equal and equal to the hue-0 output within one 8-bit step / 0.002 (FX-004-S1);
  red patch at 0, 120, 240° matches the reference then `ToneMap.map` within the same tolerances (FX-004-S2);
  a mixed image matches the reference at 30° with other operators active.
- [ ] FX-004-T06 [P] [US1] Add `effect.colorGrade.hue` ("Hue (degrees)", unit `.degrees`, after saturation) to
  `Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift` and `grade(from:)`; update
  `Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift` (six descriptors).
- [ ] FX-004-T07 [US1] App setting: `hue` and `settings.colorGrade.hue` in
  `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift` (in `allKeys`, so the UI-test reset includes it;
  reset; readout `hueText` "+30°" / "0°" / "−120°"); the key in
  `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (FILE-005 included keys; FILE-011's
  "Settings" erase category is derived from them in `LibraryErasePolicy.settingsCategoryKeys`) and
  `scripts/run_device_tests.py` (privacy allow-list).
- [ ] FX-004-T08 [US1] Settings → Color: a "Hue" row (`colorHueSlider`, VoiceOver step 10°, spoken via a new
  `SpokenUnit.signedDegrees` "plus 30 degrees") in `Apps/projectM-iOS/Views/ColorGradeSection.swift` and
  `Apps/projectM-iOS/Views/AccessibleParameter.swift`; footer unchanged.
- [ ] FX-004-T09 [US1] App tests: hue persistence, read rule, reset and readouts in
  `Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift`; spoken value and ACC-012's `effective(_:clamp:)`
  leaving the hue unchanged under Strict (FX-004-R6) in the same file; the Hue slider's presence
  in `Apps/projectM-iOS/UITests/ColorGradeUITests.swift`; backup/erase key tests still pass.

## Phase 4: User Story 2 - Zero is exactly "off" (P1)

- [ ] FX-004-T10 [US2] In `HueShiftOutputTests.swift`: hue 0 with every other control neutral is bit-identical to
  the bypass output, and hue 0 with other controls active is bit-identical to the same grade's FX-003 output
  (FX-004-S4); FX-003's `ColorGradeOutputTests` still pass.
- [ ] FX-004-T11 [P] [US2] RenderGoldens unchanged: `swift test --package-path Packages/RenderGoldens`.

## Phase 5: User Story 3 - Flash limiter (P1)

- [ ] FX-004-T12 [US3] In `HueShiftOutputTests.swift`: with hue 120° the composite flash guard engages on frames
  flashing above the threshold, and a steady colour's measured luminance is the same with and without the shift
  (FX-004-S5).

## Phase 6: Polish

- [ ] FX-004-T13 Amend `docs/adr/0050-output-color-grade.md` (operator 6, 64-byte block, red reference, grey
  proof) and run `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
  `check_status_events`, `test_scripts`.
- [ ] FX-004-T14 App on an own iOS 27.2 simulator: `-only-testing:projectM-iOSTests` and
  `-only-testing:projectM-iOSUITests/ColorGradeUITests`, with the long-body warnings flags; LibraryBackup package
  tests; Compositor package suite under 1 minute.
- [ ] FX-004-T15 `{device}` On D1 (quickstart step 5): hue +120 on the Photo visual, greys unchanged, frame rate
  unchanged.

## Dependencies

T01 → T02 → (T03, T04) → T05, T10, T12; T06 after T02; T07 → T08 → T09; T11 after T04; T13-T14 last; T15 after
integration.

## Parallel examples

T03 with T04; T06 with T07; T11 with T09.

## Implementation strategy

MVP = Phases 1-3 (acceptance). Phases 4-5 are tests on the same code; Phase 6 closes the records.
