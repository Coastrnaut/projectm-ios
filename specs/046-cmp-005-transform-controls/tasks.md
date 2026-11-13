# Tasks: CMP-005 Transform Controls

**Input**: Design documents from `specs/046-cmp-005-transform-controls/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/layer-transform.md,
quickstart.md

**Tests**: Requested by the roadmap row (unit + snapshots + GPU performance) and the owner's rule 7
budgets: a unit test about 1-2 s and at most 10 s, the package suite under 1 minute, GPU tests at
64 × 64.

**Format**: `[ID] [P?] [Story] Description`. No `{device}` task: the device frame cost is
CMP-002-T15 (spec CMP-005-S6).

## Phase 1: Setup

- [X] CMP-005-T01 Baseline: run `swift test --package-path Packages/Compositor` on the worktree before any code change and record the pass counts (no file change) — Verified 2026-11-13: `swift test --package-path Packages/Compositor` at `95c5f22` (before code): CompositorTests 95/95, ProceduralMaterialsTests 31/31, GeneratorGraphTests 46 (1 skipped)

## Phase 2: Foundational (blocks every story)

- [X] CMP-005-T02 `LayerPoint` (Codable `{x, y}`), `LayerTransformError` (`nonFiniteTranslation`, `nonFiniteScale`, `nonFiniteRotation`, `nonFiniteAnchor`), `LayerTransformMatrix` (`m00…m12`, last row (0, 0, 1); `identity`, `rows` 3 × 3, `apply(_:)`, `*`, `inverse` nil for a zero or non-finite determinant) and `LayerTransform` (`translation` "−10…10 per component", `scale` "0.05…20 per component", `rotation` "any finite", `anchor` "−10…10 per component", default (0.5, 0.5); throwing init refuses non-finite and clamps; `uniformScale` convenience; `identity`; `isIdentity` = move 0, scale 1, rotation 0; `matrix(aspect:)` per research CMP-005-D1 element by element, non-positive or non-finite aspect reads 1; `matrix(outputWidth:outputHeight:)`) in `Packages/Compositor/Sources/Compositor/LayerTransform.swift` (CPU, outside the Metal guard); remove the placeholder `LayerTransform` from `Packages/Compositor/Sources/Compositor/LayerContract.swift` — Verified 2026-11-13: LayerTransformTests 10/10 on the host (matrix, validation, inverse, composition)
- [X] CMP-005-T03 `LayerCompositeSettings.isSupportedByCMP001` uses `transform.isIdentity`; `isSupportedByCompositor` = `blendMode == .normal` (any opacity, any transform; the `unsupportedCompositeSettings` refusal path stays for CMP-004, untestable until a second blend mode exists, CMP-005-R11) in `Packages/Compositor/Sources/Compositor/LayerContract.swift`; doc comments in `LayerContract.swift`, `LayerStack.swift` and `Compositor.swift` updated — Verified 2026-11-13: ContractTests.testOnlyIdentityCompositeSettingsAreSupported (identity with another anchor is CMP-001-supported; a moved transform is compositor-supported) on the host

## Phase 3: User Story 1 - A saved transform reloads to the same matrix (P1) MVP

**Goal**: the roadmap acceptance (CMP-005-R1 to R5, R10; S1, S2).
**Independent test**: `LayerTransformTests` (CPU, host and Linux shape).

- [X] CMP-005-T04 [US1] `Codable` for `LayerTransform`: keys `version` (1, required; another value → `DecodingError.dataCorrupted`), `translation`, `scale`, `rotation`, `anchor`; encode writes every key; decode defaults missing keys to identity values, refuses non-finite, clamps out-of-range, in `Packages/Compositor/Sources/Compositor/LayerTransform.swift` — Verified 2026-11-13: LayerTransformTests.testSavedFormHasTheDocumentedFieldsAndVersion, testDecodingDefaultsClampsAndRefusesOtherVersions on the host
- [X] CMP-005-T05 [P] [US1] Tests in `Packages/Compositor/Tests/CompositorTests/LayerTransformTests.swift` (no Metal): the acceptance — test transform (move (0.125, −0.25), scale (1.5, 0.75), rotation 0.3, anchor (0.2, 0.8)) → matrix for aspect 2; JSON encode → decode → equal transform and matrix bit for bit (`bitPattern` of all 9 elements); 1,000 seeded pseudo-random transforms and edge values (−0, 0.05, 20, 0.1, π/7) round-trip bit for bit; saved keys and version; unknown version refused; missing keys default; out-of-range JSON clamped; non-finite inputs refused per field; clamping; identity for any anchor is exactly the identity matrix; `M·anchor == anchor + translation` within 1e-12; composition order (scale then rotate then move equals the product of the separate matrices); quarter turn on 64 × 32 preserves pixel lengths (16 px horizontal → 16 px vertical); positive angle turns +x to +y; `inverse` round trip; `*` composition — Verified 2026-11-13: `swift test --package-path Packages/Compositor --filter LayerTransformTests`: 10/10 in 0.02 s, including the acceptance testSavingAndReloadingReproducesTheTestMatrix and 1,003 bit-exact round trips; the tests caught a clamp bug (scale 0 stored as 0) that was fixed before ticking

## Phase 4: User Story 2 - Layers are moved, scaled and rotated on screen (P1)

**Goal**: drawing (CMP-005-R6, R7, R9, R11; S3, S4).
**Independent test**: `LayerTransformCompositeTests` at 64 × 64.

- [X] CMP-005-T06 [US2] `cmp_over_transformed` in `Packages/Compositor/Sources/Compositor/CompositorShaders.swift` (inverse pixel matrix rows and opacity in one `constant` struct; `constexpr sampler(filter::linear, address::clamp_to_zero)`; sanitize and × opacity as `cmp_over`); in `Packages/Compositor/Sources/Compositor/Compositor.swift` a second pipeline built at init, `transform` per `LayerRecord` (from the entry or the layer's settings), `apply` copies kept entries' transforms, `composite` draws identity layers through `cmp_over` unchanged and the others through the new pipeline with `P = D·M⁻¹·D⁻¹`; diagnostics `transformedDraws` and `shownTransform(ofLayer:)` — Verified 2026-11-13: LayerTransformCompositeTests 6/6 on the host GPU (0.36 s); a mutation (sampling through the forward matrix instead of the inverse) made 2 of them fail with 9 assertion failures; full package: CompositorTests 111/111, ProceduralMaterialsTests 31/31, GeneratorGraphTests 46 (1 skipped)
- [X] CMP-005-T07 [US2] GPU tests in `Packages/Compositor/Tests/CompositorTests/LayerTransformCompositeTests.swift`: half-scale red about anchor (0, 0) moved by (0.5, 0.5) → bottom-right quarter red, rest transparent outside a 1 px edge band; a quadrant pattern layer (red top-left, green top-right) turned +π/2 about the centre → red top-right, green bottom-right, left half transparent; identity with a non-centre anchor is bit-identical to default settings and draws through the plain path (`transformedDraws == 0`); opacity 0.5 applies to a transformed layer; the composite flash guard limits a transformed layer (after black frames with Reduce flashing on, a white transformed layer's first frame is held below gain 1; CMP-005-R9); layers given to `init(device:layers:)` honour their transform; and update the old refusal cases in `ContractTests.swift`, `LayerStackApplyTests.swift` and `TwoLayerCompositeTests.swift` (transforms are now accepted) — Verified 2026-11-13: testMovedQuarterSizeSquareLandsInTheCorner, testQuarterTurnMovesTheAsymmetricPatternClockwise, testIdentityWithAnyAnchorIsBitIdenticalAndTakesThePlainPath (raw rgba16Float bits), testOpacityAndDirectLayersApplyToTransformedLayers, testTransformedLayersAreLimitedByTheFlashGuard on the host GPU; updated cases in ContractTests, LayerStackApplyTests, TwoLayerCompositeTests (testDuplicateLayersAreRejectedAndTransformsAccepted) pass

## Phase 5: User Story 3 - Transforms are safe and cheap (P1)

**Goal**: reuse and no allocation (CMP-005-R4, R8; S5).
**Independent test**: the remaining `LayerTransformCompositeTests`.

- [X] CMP-005-T08 [US3] Tests in `Packages/Compositor/Tests/CompositorTests/LayerTransformCompositeTests.swift`: a transform-only apply calls no factory and prepares nothing; the next frame shows the new transform; 30 transformed frames at a steady size create no pictures (`pictureAllocations`); a transform moving the picture fully off the output leaves only the layers below — Verified 2026-11-13: testTransformEditsReuseLayersAndAllocateNothing (0 factory calls and 0 preparations for transform-only applies, 0 pictures over 30 transformed frames, off-screen move shows only the layer below) on the host GPU

## Phase 6: Polish & Cross-Cutting

- [X] CMP-005-T09 [P] ADR-0013 "Amendment: CMP-005 transform controls" in `docs/adr/0013-compositor-layer-protocol.md` (and the ADR index if it lists amendments) — Verified 2026-11-13: ADR-0013 "Amendment: CMP-005 transform controls" and the ADR index row; `python3 scripts/validate_docs.py` OK (431 files)
- [X] CMP-005-T10 Linux shape: `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` runs `LayerTransformTests` — Verified 2026-11-13: Linux shape: CompositorTests 55/55 (LayerTransformTests 10/10), ProceduralMaterialsTests 19/19, GeneratorGraphTests 32/32
- [ ] CMP-005-T11 Simulator package run: `xcodebuild test -scheme Compositor` from `Packages/Compositor` on a fresh iOS 27.2 simulator (deleted afterwards); PosterBoard reports counted before and after
- [ ] CMP-005-T12 `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py` OK; spec status updated

## Dependencies

- T01 → T02, T03 → T04 → T05; T06 needs T02, T03; T07 and T08 need T06.
- T09 any time after T06; T10 after T05; T11 after T08; T12 last.

## Parallel opportunities

- T05 alongside T06 (different files); T09 alongside T07/T08.

## Implementation strategy

MVP = Phases 2-3 (the transform model, its saved form and the acceptance test, all CPU). Then the
GPU drawing and its tests, the reuse tests, polish.
