# Tasks: FX-005 Contrast Curves

**Input**: design documents in `specs/292-fx-005-contrast-curves/` (spec, plan, research, data-model,
contracts/contrast-curves.md, quickstart)

**Tests**: requested by the roadmap row (snapshot, shader unit, device GPU) and the spec (FX-005-S1-S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute; UI test under 30 s.

Format: `- [ ] FX-005-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-005/`.

## Phase 1: Setup

- [X] FX-005-T01 Audit: confirm no contrast curve exists (`grep -rli "contrast\|s-curve\|filmic"` over
  `Packages/*/Sources` and `Apps/projectM-iOS`) and that FX-003's grade, FX-020's `fx.grade` entry and the setting
  are as described; record it in spec.md's audit. — Verified 2026-11-15: grep -rliE "contrastcurve|s-curve|scurve|filmic" and "contrast" over Packages/*/Sources and Apps/projectM-iOS: only ProceduralMaterials' Ring Tunnel slot and UIX-011 swatch contrast ratios, no picture curve; recorded in spec.md's audit.

## Phase 2: Foundational

- [X] FX-005-T02 Create `Packages/Compositor/Sources/Compositor/ContrastCurve.swift`: enum `ContrastCurve`
  (`linear`, `sCurve`, `filmic`; String raw values, CaseIterable, Codable), constants (pivot 0.18, τ 0.1, σ 0.5,
  strength range 0…1, default 0.5, step 0.01), the scalar reference `value(_:curve:strength:)` (contract C1: "input
  NaN → 0, clamped to 0…1; output in 0…1, f(0) = 0, f(1) = 1 exactly"), typed steps. — Verified 2026-11-15: ContrastCurve.swift builds on the host and in the Linux shape; ContrastCurveReferenceTests 6/6 (logs-fx-005/linux-shape-2.log).
- [X] FX-005-T03 Extend `Packages/Compositor/Sources/Compositor/ColorGrade.swift` in a marked FX-005 section:
  fields `contrast` (default `linear`, missing → `linear`) and `contrastStrength` ("0…1, default 0.5, NaN → 0.5"),
  `clamped`, Codable, coefficients `contrast` (c, s, τ, σ) and flags 256 / 512, reference step 7 (FX-002 step, then
  C1 per channel) after the hue (research D1). — Verified 2026-11-15: ContrastCurveReferenceTests 6/6 plus ColorGradeReferenceTests 8/8, HueShiftReferenceTests and ToneMapReferenceTests in the Linux shape (logs-fx-005/reference-linux-shape.log, 0.012 s for the FX-005 suite).
- [X] FX-005-T04 Extend `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`: `CMPGrade.contrast`
  appended after `pad1` (80 bytes), `cmp_contrast` and step 7 in `cmp_grade` behind flags 256/512,
  `GradeBlock.contrast`; update the layout test in `Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift`. — Verified 2026-11-15: ColorGradeOutputTests (layout: 80 bytes, contrast at offset 64) and ContrastCurveOutputTests 4/4 on the host GPU (logs-fx-005/gpu-host.log).

## Phase 3: User Story 1 - Give a visual more punch (P1)

**Independent test**: each preset through the output pass matches the reference; settings and scenes keep it.

- [X] FX-005-T05 [P] [US1] Write `Packages/Compositor/Tests/CompositorTests/ContrastCurveReferenceTests.swift`
  (CPU, Linux shape): each preset at 0.25, 0.5, 1 monotone over a 4,097-point sweep, f(0) = 0 and f(1) = 1 exactly,
  inside 0…1, S-curve keeps 0.18, Filmic ≠ S-curve, greys stay grey through the grade, decoding of old grades. — Verified 2026-11-15: ContrastCurveReferenceTests: 4,097-point sweep, 0 reversals at 0.25/0.5/1 for both curves, ends exact, bounds, pivot, documented values, greys exact.
- [X] FX-005-T06 [P] [US1] Write `Packages/Compositor/Tests/CompositorTests/ContrastCurveOutputTests.swift` (GPU):
  grey ramp plus colours for S-curve and Filmic vs the reference within one 8-bit step / 0.002 half float, and the
  FX-020 Color-before-Trails order gives the same picture as the output-pass order (the curve applies once; R6). — Verified 2026-11-15: ContrastCurveOutputTests on the host GPU: worst error 0.00048 (half float, tolerance 0.002) and 0.0025 (sRGB, tolerance 1/255); Color-before-Trails steady colour matches the single-curve reference within 0.002.
- [X] FX-005-T07 [P] [US1] Add `effect.colorGrade.contrast` (enumeration) and `effect.colorGrade.contrastStrength`
  to `Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift` and its tests. — Verified 2026-11-15: ColorGradeCatalogTests 4/4 on the host and in the Linux shape (8 descriptors; contrast enumeration; grade(from:) clamps and reads unknown names as Linear).
- [X] FX-005-T08 [US1] Scene: `contrast` and `contrastStrength` in `fx.grade`
  (`Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`), round-trip, old documents → Linear, unknown
  name → Linear with a warning; tests in `Packages/SceneFormat/Tests/SceneFormatTests/`. — Verified 2026-11-15: SceneEffectChainTests 11/11 and the whole SceneFormat suite 207/207 on the host (logs-fx-005/scene-all.log).
- [X] FX-005-T09 [US1] App setting: `settings.colorGrade.contrast` and `settings.colorGrade.contrastStrength` in
  `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift` (`allKeys`, read rules, reset, readouts),
  `SceneAutosaveCapture.applyEffects`; keys in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`
  and `scripts/run_device_tests.py` (the UI-test reset and FILE-011's erase follow `allKeys`); ACC-012's
  `effective` leaves the curve unchanged; tests in `Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift`. — Verified 2026-11-15: ColorGradeSettingTests 13/13 (incl. three FX-005 tests), LibraryBackupAppTests, SettingsTests, LibraryEraseAppTests, EffectChainSettingTests on the FX5 iPhone 17 simulator (iOS 27.2; logs-fx-005/app-tests.log).
- [X] FX-005-T10 [US1] Settings → Color: "Contrast" picker and "Contrast strength" `.accessibleParameter` slider in
  `Apps/projectM-iOS/Views/ColorGradeSection.swift`; UI test in `Apps/projectM-iOS/UITests/ColorGradeUITests.swift`. — Verified 2026-11-15: ColorGradeUITests 2/2 on the FX5 iPhone 17 simulator; testContrastPickerShowsStrengthAndResets 11.3 s.

## Phase 4: User Story 2 - Linear is exactly "off" (P1)

- [X] FX-005-T11 [US2] In `ContrastCurveReferenceTests`: Linear and strength 0 bit-identical on the sweep and on
  1,000 random colours (S1), flags off, FX-003/FX-004 vectors unchanged; in `ContrastCurveOutputTests`: Linear
  bit-identical to the grade without FX-005 (neutral and with other controls). RenderGoldens unchanged. — Verified 2026-11-15: ContrastCurveReferenceTests.testLinearAndStrengthZeroAreBitIdentical (sweep plus 1,002 colours bit for bit) and ContrastCurveOutputTests.testLinearIsBitIdenticalToTheOutputWithoutTheCurve (both formats); RenderGoldens 104 tests pass on the host and on the simulator.

## Phase 5: User Story 3 - Extreme pictures stay displayable (P1)

- [X] FX-005-T12 [US3] In `ContrastCurveReferenceTests`: 1e6, −1, NaN, ±∞ (scalar and whole grade) finite inside
  0…1 (S3); in `ContrastCurveOutputTests`: the same pixels on the GPU, and the flash guard still lowers its gain with
  a curve active. — Verified 2026-11-15: ContrastCurveReferenceTests.testExtremeInputsGiveFiniteBoundedOutputs (1e6, −1, NaN, ±Inf, max finite; strengths NaN/7/−3) and ContrastCurveOutputTests (reference image's NaN/Inf/HDR pixels finite on the GPU; limiter gain equal with and without each curve).

## Phase 6: Polish

- [X] FX-005-T13 Amend `docs/adr/0050-output-color-grade.md` (operator, block, flags); repo checks
  (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`,
  `test_scripts`), `LibraryBackupAppTests`, `SettingsTests`, type-check budget, Linux shape of Compositor/SceneFormat. — Verified 2026-11-15: ADR-0050 amended; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 186 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no slow type-check warnings in touched files. Full suites on the host: Compositor (all pass, logs-fx-005/compositor-all.log), LibraryBackup 88/88, SceneFormat 207/207, RenderGoldens 104 (host and simulator).
- [ ] FX-005-T14 {device} On D1: Photo visual with S-curve and Filmic at 100%; frame rate unchanged within noise
  (FX-005-S7).

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06, T07 in parallel) → T08 → T09 → T10 → T11, T12 → T13 → T14.

## Parallel examples

- T05, T06 and T07 touch different files after T04.

## Implementation strategy

MVP: T02-T06 (the operator and its proofs), then persistence and UI (T07-T10), then the cross-cutting checks.
