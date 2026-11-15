# Tasks: FX-013 Posterization

**Input**: design documents in `specs/301-fx-013-posterization/` (spec, plan, research, data-model,
contracts/posterize.md, quickstart)

**Tests**: requested by the roadmap acceptance ("Known gradient contains at most configured levels without
dithering") and the spec (FX-013-S1-S8). Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite
under 1 minute; UI test under 30 s.

Format: `- [ ] FX-013-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-013/`.

## Phase 1: Setup

- [ ] FX-013-T01 Audit: confirm no posterization exists (`grep -rliE "posteri|quantiz"` over `Packages/*/Sources` and
  `Apps/projectM-iOS`) and that grade flag bits 64 and 128 are unused; record it in spec.md's audit.

## Phase 2: Foundational

- [ ] FX-013-T02 Create `Packages/Compositor/Sources/Compositor/Posterize.swift`: constants (levels 2…32, default 6),
  the Bayer 4 × 4 matrix, `threshold(x:y:)`, the scalar reference `quantize(_:levels:threshold:)` (contract C1),
  typed steps, no Apple-only API (Linux).
- [ ] FX-013-T03 Extend `Packages/Compositor/Sources/Compositor/ColorGrade.swift` in a marked FX-013 section: fields
  `posterize`, `posterizeLevels`, `posterizeDither` (init defaults, Codable keys appended, missing → defaults),
  `clamped` (levels 2…32), coefficients `poster` and flags 64/128 (128 only with 64), step 8 in `apply(_:x:y:)` after
  the curve (`ToneMap.map` then C1 per channel), `apply(_:)` = position (0, 0); off sets no flag.
- [ ] FX-013-T04 Shader in `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`: append `float4 poster` to
  `CMPGrade` and `GradeBlock` (96 bytes), `cmp_posterize` with own sRGB helpers and a `constant` Bayer table,
  `cmp_grade_at` / `cmp_display_at` with the position (old names kept as wrappers); `cmp_output`,
  `cmp_output_calibrated` pass `uint2(in.position.xy)`; `OutputGradePass.swift` and `CompositeFlashGuard.swift` pass
  their pixel.

## Phase 3: User Story 1 — poster bands (P1) and User Story 3 — off and extremes (P1)

- [ ] FX-013-T05 [P] [US1] `Packages/Compositor/Tests/CompositorTests/PosterizeReferenceTests.swift` (CPU): dense
  gradient (4,096 values) per channel, dithering off, at most L (and exactly L) distinct values for L ∈ {2, 3, 6, 16,
  32}; off identity bit for bit (sweep, 1,000 random colours, with other controls on); extremes (1e6, −1, NaN, ±∞)
  finite and on a level; levels clamped; order after the curve.
- [ ] FX-013-T06 [P] [US1] `Packages/Compositor/Tests/CompositorTests/PosterizeOutputTests.swift` (GPU, through
  `cmp_output`): a horizontal gradient composite in `rgba16Float` and `bgra8Unorm_srgb`, dithering off: at most L
  distinct values per channel for L ∈ {2, 6, 32}; GPU vs CPU level indices equal on ≥ 99% of pixels and within one
  level everywhere; off bit-identical to the output without it; `cmp_output_calibrated` (OUT-009, spec Edge Cases)
  keeps at most L values; flash guard still limits a strobe.
- [ ] FX-013-T07 [US1] Block layout in `Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift` (size
  96, `poster` at 80).

## Phase 4: User Story 2 — dithering (P2)

- [ ] FX-013-T08 [US2] Dither tests in both new files: CPU — at most L values, two runs identical, a flat value
  between levels shows both levels and its 4 × 4 mean is within 1/32 level of the input; GPU — at most L values per
  channel and matches the CPU at each pixel's position (≥ 99%, within one level).

## Phase 5: Integration

- [ ] FX-013-T09 [P] MOD-001 descriptors in `Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift`
  (two booleans, one integer, `discreteManual`; `grade(from:)` reads them) and
  `Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift`.
- [ ] FX-013-T10 [P] Scene fields in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift` (read, warn on
  malformed, write only when on or already present) and `SceneEffectChainTests.swift` (round-trip, old scenes off,
  malformed values).
- [ ] FX-013-T11 App setting in `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift` (three keys in `allKeys`,
  stored, read checked, reset), `SceneAutosaveCapture.swift` (apply from scenes), FILE-005 `LibrarySettings.swift`
  included keys, `scripts/run_device_tests.py` `ALLOWED_KEYS`; tests in `Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift`;
  run `LibraryBackupAppTests` and `SettingsTests`
  (S6 backup and S7 relaunch: the setting test re-creates the setting from the same defaults).
- [ ] FX-013-T12 Settings → Color rows in `Apps/projectM-iOS/Views/ColorGradeSection.swift` (Posterize toggle; Levels
  slider via ACC-005 and Dither toggle while on) and a short UI test in
  `Apps/projectM-iOS/UITests/ColorGradeUITests.swift` (toggle on shows "6 levels", reset turns it off).

## Phase 6: Polish

- [ ] FX-013-T13 Amend `docs/adr/0050-output-color-grade.md` (step 8, block 96 bytes, flags 64/128, position
  functions); run repo checks (compliance, docs, motion policy, permission catalog, status events, script tests),
  RenderGoldens and FX-005's output tests unchanged; type-check budget; spec status.
- [ ] FX-013-T14 {device} On D1: a compositor-backed visual with Posterize at 6 levels and Dither on; frame rate
  within 1 fps of off; bands visible, no shimmer on a still picture.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06, T07, T08) → (T09, T10 in parallel) → T11 → T12 → T13 → T14.
