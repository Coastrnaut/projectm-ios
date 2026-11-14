# Tasks: CMP-007 Shape Masks

**Input**: Design documents from `specs/104-cmp-007-shape-masks/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/shape-masks.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] CMP-007-T01 Run the baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; record counts in docs/test-reports/shape-masks.md

## Phase 2: Foundational (blocks every story)

- [ ] CMP-007-T02 Add `LayerMaskShape` (`ellipse`, `rectangle(cornerRadius:)` "clamped 0…0.5 (non-finite reads 0)", `polygon([LayerPoint])` "3…32 points … each coordinate clamped −10…10; non-zero area; even-odd fill"), `LayerMaskTransform` (`center` "clamped −10…10", `scale` "clamped 0.01…20", `rotation` "non-finite reads 0; −0 stored as 0"), `LayerMask` (feather "clamped 0…1", `inverted`; `throws(LayerMaskError)`: `tooFewPoints`, `tooManyPoints`, `zeroArea`, `nonFinitePoint`; `maximumPolygonPoints = 32`) and `LayerMaskGeometry` (`signedDistance(x:y:)`, `coverage(x:y:)`, `band`; research D1) in typed `Double` steps, outside any Metal guard (CMP-007-R1, R2, R3, R4, R5, R8, R13) in Packages/Compositor/Sources/Compositor/LayerMask.swift
- [ ] CMP-007-T03 Add `mask: LayerMask?` (default nil, additive init parameter) to `LayerCompositeSettings` in Packages/Compositor/Sources/Compositor/LayerContract.swift
- [ ] CMP-007-T04 [P] CPU reference tests: circle distance and coverage at known pixels; ellipse sign; rounded rectangle (corner region, radius limited to half the shorter side); convex triangle and concave L polygon (notch outside); self-intersecting star centre outside (even-odd); invert; feather monotonic and exactly 0 at d ≥ band/2 and exactly 1 at d ≤ −band/2; transform (centre, scale, rotation) moves the shape; circle stays round on 16:9 and 9:16; clamping; polygon refusals (2 points, 33 points, collinear) in Packages/Compositor/Tests/CompositorTests/LayerMaskReferenceTests.swift

## Phase 3: User Story 1 - Mask a layer with a shape (P1) 🎯 MVP

**Goal**: masked layers drawn with exact zeros outside. **Independent test**: GPU read-back per shape vs the CPU reference.

- [ ] CMP-007-T05 [US1] Shaders (additive): `CMPMask` (rows, shape, edge, `float2 points[32]`), `cmp_mask_coverage` (same steps as `LayerMaskGeometry`), fragment `cmp_over_masked` (identity read or transformed sample by `params.y`, sanitize, × opacity, × coverage at the layer pixel) in Packages/Compositor/Sources/Compositor/CompositorShaders.swift
- [ ] CMP-007-T06 [US1] Compositor: records keep `mask` (init and every apply), cached block per picture size, normal masked layers draw `cmp_over_masked` in the open pass (no extra pass), `maskedDraws` counter; unmasked layers keep their pipelines (CMP-007-R7, R12) in Packages/Compositor/Sources/Compositor/Compositor.swift
- [ ] CMP-007-T07 [US1] GPU tests: a solid opaque layer over transparent, masked by circle, rounded rectangle, convex polygon, concave polygon, inverted circle, feathered ellipse: count pixels with alpha ≠ 0 where the reference distance ≥ band/2 + 0.05 px (must be 0), inside pixels equal the unmasked layer, max |alpha − reference coverage| on edge pixels ≤ 0.01; print the table (CMP-007-S1, S2) in Packages/Compositor/Tests/CompositorTests/LayerMaskCompositeTests.swift

## Phase 4: User Story 2 - Masks work with every other layer setting (P1)

**Goal**: transform, fit, opacity and blend modes compose. **Independent test**: GPU read-back with each.

- [ ] CMP-007-T08 [US2] `cmp_blend` takes the mask block at `buffer(1)` and multiplies the source by coverage only when the mask kind is not 0; the compositor binds the block (or a disabled one) for every blend draw in Packages/Compositor/Sources/Compositor/CompositorShaders.swift and Compositor.swift
- [ ] CMP-007-T09 [US2] GPU tests: masked layer with a CMP-005 transform (shape follows the move; reference evaluated at the inverse-mapped layer pixel; 0 outside violations); masked photo in CMP-006 fit (mask cuts the layer rectangle, bars transparent); masked layer in `screen` over a backdrop (backdrop unchanged outside, inside equals the unmasked screen result); opacity 0.5 × coverage; a mask change at apply shows next frame with no new pictures; normal masked layer adds no pass (`blendDraws` 0, `maskedDraws` 1); unmasked render bit-identical to a compositor without the mask field set (CMP-007-S3, R6, R7, R12) in Packages/Compositor/Tests/CompositorTests/LayerMaskCompositeTests.swift
- [ ] CMP-007-T10 [US2] GPU performance: time a full-screen masked layer per shape vs unmasked on the Mac (GPU start/end over a few frames, printed, opt-in with `CMP007_BENCH=1`, no assertion), recorded in docs/test-reports/shape-masks.md as not device evidence (CMP-007-S5)

## Phase 5: User Story 3 - Scenes keep the mask and its transform (P1)

**Goal**: `composite.mask` saved and restored. **Independent test**: byte-identical round trips.

- [ ] CMP-007-T11 [US3] `SceneMask` (`known(LayerMask)` | `unknown(shape:object:)`, equality and hash through the encoder) and `SceneComposite.mask: SceneMask?`; decoder: `shape` required, known shapes closed (unknown keys `droppedField`), numbers clamped with `valueClamped`, polygon "< 3 or > 32 points or zero area drops the mask with `droppedField`", unknown shape kept verbatim; encoder writes every field of a known mask, only when set (CMP-007-R9, R11, R8) in Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift, SceneDecoding.swift, SceneEncoding.swift
- [ ] CMP-007-T12 [US3] Validation warning `unsupportedMaskShape` (repair report: values adjusted, a note); `liveState` maps known masks to `LayerCompositeSettings.mask`, unknown ones to nil kept in `SceneLiveState.preservedMasks`; `init(capturing:)` writes the live mask, or the preserved one while the live mask is nil (CMP-007-R10) in Packages/SceneFormat/Sources/SceneFormat/SceneIssue.swift, SceneValidation.swift, SceneRepair.swift, SceneLiveState.swift
- [ ] CMP-007-T13 [US3] Tests: each shape with a rotated, scaled, off-centre transform decodes → encodes byte-identically and survives decode → live → capture → encode byte-identically; unknown shape warned, repair note, unmasked live, written back verbatim; clamping warnings; unusable polygons dropped with `droppedField`; scene without mask unchanged (CMP-007-S4) in Packages/SceneFormat/Tests/SceneFormatTests/SceneMaskTests.swift

## Phase 6: Polish & cross-cutting

- [ ] CMP-007-T14 Linux shape: `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerMaskReferenceTests`, and SceneFormat with the same flags; check `.github/workflows/ios-ci.yml` runs them
- [ ] CMP-007-T15 Regression: Compositor, SceneFormat (incl. QA-004 meta-test), RenderGoldens (no golden re-recorded), ImportFuzz, ShowControl, SceneArchive; app unit tests on a dedicated "CMP7 iPhone 17" iOS 27.2 simulator (`-only-testing:projectM-iOSTests`), deleted afterwards
- [ ] CMP-007-T16 Docs: SCN-001 contract and ADR-0028 list `composite.mask`; docs/test-reports/shape-masks.md with the read-back and GPU time tables; spec status Implemented
- [ ] CMP-007-T17 Checks: `python3 scripts/check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`

## Dependencies

- T01 → T02 → T03; T04 after T02.
- US1 (T05-T07) after T03; US2 (T08-T10) after T06; US3 (T11-T13) after T02 (independent of US1/US2).
- Polish after all stories.

## Parallel examples

- T04 (CPU tests) alongside T05 (shaders) once T02 exists.
- US3 (SceneFormat) in parallel with US1/US2 (Compositor).

## Implementation strategy

MVP = Phase 2 + US1 (masks drawn with exact zeros). Then US2 (composition), then US3
(persistence: the acceptance criterion's second half), then polish. Commit after each phase.
