# Tasks: CMP-008 Gradient Masks

**Input**: Design documents from `specs/207-cmp-008-gradient-masks/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/gradient-masks.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute,
UI test under 30 s.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] CMP-008-T01 Baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; create the simulator "CMP8 iPhone 17" (iOS 27.2); record counts and PosterBoard report count in docs/test-reports/gradient-masks.md

## Phase 2: Foundational (blocks every story)

- [ ] CMP-008-T02 Add `LayerGradientStop` ("position 0…1, clamped; non-finite reads 0", "alpha 0…1, clamped; non-finite reads 1"), `LayerGradientKind` (`linear(start:end:)` "each coordinate clamped −10…10", `radial(center:radius:)` "radius clamped 0.01…20 (non-finite reads 0.5)"), `LayerGradientMask` ("2…8" stops, stable-sorted; `throws(LayerGradientMaskError)`: `tooFewStops`, `tooManyStops`, `zeroLength` for |end − start| < 1e-6), `alpha(at:)` (research D1), `linearDefault`/`radialDefault`, and `LayerGradientGeometry` (`parameter(x:y:)`, `alpha(x:y:)`; research D2) in typed `Double` steps outside any Metal guard (CMP-008-R1, R2, R3, R4, R12) in Packages/Compositor/Sources/Compositor/LayerGradientMask.swift
- [ ] CMP-008-T03 Add `gradientMask: LayerGradientMask?` (default nil, additive init parameter) to `LayerCompositeSettings` in Packages/Compositor/Sources/Compositor/LayerContract.swift
- [ ] CMP-008-T04 [P] CPU reference tests: each stop's alpha exactly at its position; clamping before the first and after the last stop; dense sweep (t step 1/1024) monotonic per segment for rising, falling, mixed and equal-position stop lists (0 violations); stable sort; refusals (1 stop, 9 stops, zero-length linear); clamping of values; linear projection (diagonal isolines perpendicular in pixels); radial stays round on 160 × 90 and 90 × 160 in Packages/Compositor/Tests/CompositorTests/LayerGradientReferenceTests.swift

## Phase 3: User Story 1 - Fade a layer with a gradient (P1) 🎯 MVP

**Goal**: a gradient fades a layer, monotonic between stops. **Independent test**: GPU read-back along the axis vs the reference.

- [ ] CMP-008-T05 [US1] Shaders: append `float4 grad; float4 axis; float2 stops[8];` to `CMPMask`, add `cmp_gradient_alpha` (same loop as `alpha(at:)`), make `cmp_mask_coverage` = shape coverage (1 for shape kind 0) × gradient alpha (1 for kind 0); `cmp_blend` applies coverage when either is set; `MaskBlock` grows to 400 bytes, built from optional shape and gradient geometries (research D3) in Packages/Compositor/Sources/Compositor/CompositorShaders.swift
- [ ] CMP-008-T06 [US1] Compositor: records keep `gradientMask` (init and every apply; a change clears the cached block); a layer with either mask takes the masked routes; unmasked layers unchanged (CMP-008-R6, R11) in Packages/Compositor/Sources/Compositor/Compositor.swift
- [ ] CMP-008-T07 [US1] GPU tests (CMP-008-S1): solid opaque layer, 160 × 96 output; linear gradient with stops rising, falling and flat: every pixel of the centre row sampled, per segment non-decreasing / non-increasing within 1/255, each sample within 1/255 of the reference, rows identical (alpha independent of y); radial gradient: the ray from the centre to the right edge, same checks, and equal alpha at equal distance; gradient × circle shape (outside still exactly 0); a CMP-005-transformed layer matches the reference at the inverse-mapped layer pixel; normal mode adds no pass (`maskedDraws` 1, `blendDraws` 0); screen blend; a change at apply shows next frame without re-creating the layer; a gradient with all stops at alpha 1 draws bit-equal to unmasked in Packages/Compositor/Tests/CompositorTests/LayerGradientCompositeTests.swift
- [ ] CMP-008-T08 [US1] Opt-in GPU bench (`CMP008_BENCH=1`): GPU start/end time of a full-screen gradient layer vs unmasked at 1920 × 1080, printed, never asserted (CMP-008-S5) in Packages/Compositor/Tests/CompositorTests/LayerGradientCompositeTests.swift
- [ ] CMP-008-T09 [US1] Goldens (CMP-008-S3): `gradient-mask-linear` and `gradient-mask-radial` through the real compositor at both QA-002 resolutions, recorded on the host and the "CMP8 iPhone 17" simulator into Packages/RenderGoldens/GeneratorGoldens/GradientMask/{macos,ios-simulator}/, test in Packages/RenderGoldens/Tests/RenderGoldensTests/GradientMaskGoldenTests.swift

## Phase 4: User Story 3 - Scenes keep the gradient (P1)

**Goal**: byte-identical round trips. **Independent test**: decode/encode and load/capture comparisons.

- [ ] CMP-008-T10 [US3] `SceneGradientMask` (`known`/`unknown(kind:object:)`, equality through the encoder) and `SceneComposite.gradientMask` in Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift; encode only when set, every field in full in SceneEncoding.swift; decode per contract G3 (closed object, `droppedField`, `valueClamped`, stop count checked before decoding stops, re-sort warning, zero-length drop, unknown kind verbatim) in SceneDecoding.swift; validation `unsupportedMaskShape` at `…composite.gradientMask.kind` in SceneValidation.swift; `preservedGradientMasks` in load and capture in SceneLiveState.swift (CMP-008-R7, R8, R9)
- [ ] CMP-008-T11 [US3] Tests: byte-identical decode → encode of linear, radial and gradient + shape scenes; load → capture → encode identical; unknown kind kept through load/capture, validation note, not drawn; clamping and re-sort warnings; < 2 / > 8 stops and zero-length dropped with `droppedField`; unknown keys dropped; scenes without the field unchanged (CMP-008-S4) in Packages/SceneFormat/Tests/SceneFormatTests/SceneGradientMaskTests.swift
- [ ] CMP-008-T12 [US3] ADR-0028: list `composite.gradientMask` in docs/adr/0028-scene-document-format.md

## Phase 5: User Story 2 - Edit the stops (P1)

**Goal**: the inspector edits kind, angle/radius and stops. **Independent test**: unit rules + one UI test.

- [ ] CMP-008-T13 [US2] `LayerGradientEdit`: kind (None/Linear/Radial with defaults), angle (−180…180°, keeps midpoint and length), radius (0.1…2), stop position/alpha, add ("≤ 8", middle of the widest gap, alpha from `alpha(at:)`), remove ("≥ 2"), texts; `LayerCompositeMapping.settings` passes the gradient; help entries; history labels and keys `layer.<kind>.gradient…` in Apps/projectM-iOS/Coordinators/LayerGradientEdit.swift, LayerInspectorModel.swift, LayerInspectorCoordinator.swift, SceneHistoryCoordinator.swift (CMP-008-R10)
- [ ] CMP-008-T14 [US2] `LayerGradientSection` (picker, angle/radius slider, stop rows with ACC-005 sliders and Remove, Add Stop; small bodies) and one line in LayerDetailView in Apps/projectM-iOS/Views/LayerGradientSection.swift, Apps/projectM-iOS/Views/LayerDetailView.swift
- [ ] CMP-008-T15 [P] [US2] Unit tests of the edit rules (defaults, add keeps the picture, limits, re-sort on move, angle round trip, mapping, history label/key) in Apps/projectM-iOS/Tests/LayerGradientEditTests.swift
- [ ] CMP-008-T16 [US2] UI test: choose Linear, Add Stop (3 stops), adjust stop 2 alpha, undo restores; under 30 s (CMP-008-S6) in Apps/projectM-iOS/UITests/LayerInspectorUITests.swift

## Phase 6: Polish

- [ ] CMP-008-T17 Linux shape builds and reference tests (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) for Compositor and SceneFormat; type-check budget flags on the app build; repo checks (compliance, docs, motion, permission catalog, status events, scripts); privacy manifest and network symbols on the Debug app
- [ ] CMP-008-T18 Test report docs/test-reports/gradient-masks.md (counts, durations, tables, PosterBoard counts, Mac GPU time as not device evidence); spec status
- [ ] CMP-008-T19 {device} GPU time of a full-screen gradient layer on D1 (Release automation build), recorded in docs/test-reports/gradient-masks.md (CMP-008-S5)

## Dependencies

T01 → T02 → T03 → (T04 ∥ T05) → T06 → T07, T08, T09; T10 → T11, T12 (after T02); T13 → T14 → T16 (after T06, T10); T15 after T13; T17, T18 last; T19 needs a device.

## Parallel examples

- T04 (CPU tests) beside T05 (shaders); T11 beside T13 once T10 is in.

## Implementation strategy

MVP = Phases 1-3 (a gradient drawn and proven monotonic). Then persistence (US3), then the editor (US2), then polish.
