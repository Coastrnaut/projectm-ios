# Tasks: FX-003 Color Grading

**Input**: design documents in `specs/123-fx-003-color-grading/` (spec, plan, research, data-model,
contracts/color-grade.md, quickstart)

**Tests**: requested by the roadmap row (snapshot, shader unit, device GPU) and the spec (FX-003-S1-S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute; UI test under 30 s.

Format: `- [ ] FX-003-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-003/`.

## Phase 1: Setup

- [X] FX-003-T01 Audit: confirm no grading control exists (`grep -ri "lift\|saturation\|temperature"` over
  `Packages/*/Sources` and `Apps/projectM-iOS`), list the output passes (`Compositor.composite`,
  `encodeOutput`, `encodeCapture`, `SceneTransitionBus`) and the hosts that reach them (Camera, Photo, Video,
  Text), and record it in spec.md's audit. — Verified 2026-11-14: grep over Packages/*/Sources and Apps/projectM-iOS (only SHD-002's HSV node and SHD-001's material saturation); output passes and hosts listed in spec.md's audit.

## Phase 2: Foundational

- [X] FX-003-T02 Create `Packages/Compositor/Sources/Compositor/ColorGrade.swift` (plain Swift, Linux): the
  five fields with ranges "temperature −1…1 (0), lift −0.1…0.1 (0), gamma 0.5…2 (1), gain 0.5…2 (1),
  saturation 0…2 (1)", step hints, `neutral`, `clamped` ("NaN → neutral, out of range → nearest bound"),
  `isNeutral`, `ColorGradeCoefficients` (balance gains, lift scale/offset, exponent, gain, saturation, flags
  bit 0 temperature … bit 4 saturation) and `apply(_:)` (research D2 order, typed steps, flags 0 → input
  unchanged). — Verified 2026-11-14: ColorGrade.swift builds in the Linux shape and on the host; ColorGradeReferenceTests 8/8.
- [X] FX-003-T03 [P] Write `Packages/Compositor/Tests/CompositorTests/ColorGradeReferenceTests.swift` (CPU):
  neutral identity (bit for bit, including NaN/over-range), per-control identity at neutral while others are
  active, temperature keeps grey luminance and is identity at 0, saturation 0 → grey of equal luminance,
  luminance monotonicity under lift/gamma/gain over ≥ 10,000 sampled settings and inputs (FX-003-S3, under 2 s),
  hand-checked values, clamping. — Verified 2026-11-14: ColorGradeReferenceTests 8/8 in the Linux shape (0.03 s; logs-fx-003/reference-linux-shape.log), 10,000 ordering checks.
- [ ] FX-003-T04 Add `cmp_grade` and `cmp_display` (Swift string `displaySource`, which includes
  `toneMapSource`) and the `CMPGrade` block to `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`;
  `cmp_output` reads the block at fragment buffer 2 and returns `cmp_display(c, grade).rgb × gain`; a Swift
  `GradeBlock` (48 bytes) built from `ColorGradeCoefficients`.
- [ ] FX-003-T05 Extend `Packages/Compositor/Tests/CompositorTests/OutputPassRig.swift` with a grade argument
  (default neutral) bound at buffer 2.

## Phase 3: User Story 2 - Neutral is exactly "off" (P1, the acceptance)

**Goal**: neutral grading equals bypass. **Independent test**: reference image through the real output pass.

- [ ] FX-003-T06 [US2] `Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift`: the research D8
  reference image through `cmp_output` with the neutral block vs the FX-002 shader without grading (a bypass
  library compiled from the pre-grade `cmp_output` body): bit-identical for every in-range pixel and within
  one 8-bit step / 0.002 overall, in `bgra8Unorm_srgb` and `rgba16Float` (FX-003-S1).
- [ ] FX-003-T07 [US2] Add `colorGrade` to `Compositor` and `SceneTransitionBus`
  (`Packages/Compositor/Sources/Compositor/Compositor.swift`, `SceneTransitionBus.swift`): block built on set,
  bound in the screen, recording and capture output passes and the flash guard; whole-compositor test: a
  neutral `colorGrade` composites identically to a fresh compositor; setting it does not stop CMP-013 reuse.
- [ ] FX-003-T08 [US2] Run RenderGoldens unchanged (FX-003-S5; log `goldens.log`).

## Phase 4: User Story 1 - Grade the look (P1)

**Goal**: five controls in Settings change the composited visuals and persist. **Independent test**: GPU vs
reference per operator; setting tests; UI test.

- [ ] FX-003-T09 [P] [US1] In `ColorGradeOutputTests.swift`: each operator alone and all together at a few
  representative settings vs `ColorGrade.apply` then `ToneMap.map`, within one 8-bit step / 0.002 (FX-003-S2);
  record the worst error per operator.
- [ ] FX-003-T10 [US1] Create `Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift` and the
  target in `Packages/Compositor/Package.swift`: IDs `effect.colorGrade.temperature|lift|gamma|gain|saturation`,
  group `effect.colorGrade` "Color", ranges/defaults/steps from `ColorGrade`, `.continuousDefault`;
  `Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift` (validates in a registry,
  matches `ColorGrade`, IDs unique against `VisualParameterCatalog` and `ProceduralMaterialCatalog`).
- [ ] FX-003-T11 [US1] Register the catalog in the app registry
  (`Apps/projectM-iOS/Coordinators/SceneArchiveService.swift`) and the golden renderer
  (`Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift`).
- [ ] FX-003-T12 [US1] Create `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift` (five keys
  `settings.colorGrade.*`, "absent, non-number or NaN → neutral; out of range → clamped", `grade`,
  `resetToNeutral()`, `onChange`, readout texts) and `Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift`.
- [ ] FX-003-T13 [US1] Add the keys to `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`
  (`includedKeys`) and `scripts/run_device_tests.py` (`ALLOWED_KEYS`); run LibraryBackup tests and script tests.
- [ ] FX-003-T14 [US1] Wire the grade: `AppCoordinator` owns `ColorGradeSetting` and pushes `grade` to the Camera,
  Photo, Video and Text hosts (`colorGrade` on each host → its compositor) on creation and on change
  (`Apps/projectM-iOS/Coordinators/AppCoordinator.swift`, `Apps/projectM-iOS/Visuals/*VisualHost.swift`).
- [ ] FX-003-T15 [US1] Create `Apps/projectM-iOS/Views/ColorGradeSection.swift` (five sliders with
  `.accessibleParameter`, readouts, help naming the graded visuals, "Reset to neutral") and show it in
  `Apps/projectM-iOS/Views/SettingsView.swift`; check body length with `-warn-long-function-bodies=300
  -warn-long-expression-type-checking=150`.
- [ ] FX-003-T16 [US1] `Apps/projectM-iOS/UITests/ColorGradeUITests.swift`: open Settings, find Color, move the
  gain slider, check the readout, tap Reset to neutral, check the readout and the disabled button (FX-003-S6).

## Phase 5: User Story 3 - Grading can never defeat the flash limiter (P1)

- [ ] FX-003-T17 [US3] In `Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift`: samples through
  `cmp_display` with the grade block at compute buffer 3 (two-line change plus the bound block).
- [ ] FX-003-T18 [US3] In `ColorGradeOutputTests.swift`: frames alternating 0.02 ↔ 0.06 grey keep the guard's
  gain at 1 ungraded; with gain 2 and gamma 2 the same frames become a visible flash and the gain drops
  (FX-003-S4); the existing FX-002 limiter tests still pass.

## Phase 6: Polish & Cross-Cutting

- [ ] FX-003-T19 [P] GPU timing (FX-003-S7): output pass at 1920 × 1080, neutral vs all operators active, median
  of 30 after 5 warm-ups; record in research D9.
- [ ] FX-003-T20 ADR for the output pipeline order (grade → tone map → × gain; guard measures it) in
  `docs/adr/` (next free number) and `docs/adr/README.md`.
- [ ] FX-003-T21 Regressions: Compositor (host and Linux shape), VisualGenerators, RenderGoldens, SceneFormat,
  ImportFuzz, LibraryBackup; app unit tests and the Color UI test on an own iOS 27.2 simulator; the six repo
  checks (compliance, docs, motion policy, permission catalog, status events, script tests).
- [ ] FX-003-T22 {device} On D1: Photo visual graded (warm, gain 1.5, saturation 0 → grey), reset → identical;
  frame rate unchanged in the performance overlay (FX-003-S7).

## Analysis fixes (speckit-analyze, 2026-11-14)

- A1: T07 binds the grade block in the flash guard, so T17 lands in the same change (ordering fixed below).
- A2: FX-003-R11 "no per-frame allocation": T07 builds the block on set and binds it with `setFragmentBytes` /
  `setBytes` (copied into the command stream); checked in T07's review.
- A3: the ADR number in plan.md (0049) is provisional; T20 checks `docs/adr/` right before committing.
- Coverage: R1 T07/T14, R2 T04, R3 T03/T06, R4 T03, R5 T03, R6 T17/T18, R7 T10/T11, R8 T12/T13, R9 T15/T16,
  R10 T02/T09, R11 T07/T08/T19; S1 T06, S2 T09, S3 T03, S4 T18, S5 T08, S6 T16, S7 T19/T22. No gaps.

## Dependencies

T02 → T03, T04 → T05 → T06, T09, T18; T04 → T17 → T07 (T07 binds the guard's block, so the guard's shader change lands with it); T02 → T10 → T11; T12 → T13, T14, T15 → T16. US2 (the
acceptance) first, then US1, then US3; T21 after all; T22 last.

## Parallel examples

T03 with T04; T09 with T10; T12 with T17.

## Implementation strategy

MVP = Phase 2 + US2 (neutral bypass proven on the GPU), then US1 (controls and UI), then US3 (guard), then
polish.
