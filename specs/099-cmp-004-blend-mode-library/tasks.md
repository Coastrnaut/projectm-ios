# Tasks: CMP-004 Blend Mode Library

**Input**: Design documents from `specs/099-cmp-004-blend-mode-library/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/blend-modes.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] CMP-004-T01 Run the baseline checks before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` pass on the Mac (record counts in docs/test-reports/blend-modes.md)

## Phase 2: Foundational (blocks every story)

- [ ] CMP-004-T02 Make `LayerBlendMode` a `String`, `CaseIterable` enum with raw values "normal", "add", "screen", "multiply", "overlay", "difference"; `isSupportedByCompositor` true for every mode; doc comments (CMP-004-R1) in Packages/Compositor/Sources/Compositor/LayerContract.swift, LayerStack.swift comment
- [ ] CMP-004-T03 [P] Add the CPU reference `LayerBlend` (sRGB `encode`/`decode`, `function(_:backdrop:source:)`, `composite(_:backdrop:source:opacity:)`) in typed steps, outside any Metal guard (CMP-004-R2-R5, R10) in Packages/Compositor/Sources/Compositor/LayerBlend.swift
- [ ] CMP-004-T04 [P] CPU tests: hand-checked values (multiply(0.5, 0.5) = 0.25, screen(0.5, 0.5) = 0.75, overlay threshold at 0.5, difference symmetric, add saturates, normal = Cs), transfer round trip, alpha cases (transparent backdrop = normal, αs = 0 = backdrop, opacity scaling), a 5-level grid against inline formulas (CMP-004-S3) in Packages/Compositor/Tests/CompositorTests/LayerBlendReferenceTests.swift
- [ ] CMP-004-T05 Update ContractTests for every mode being supported and `isSupportedByCMP001` false for non-normal in Packages/Compositor/Tests/CompositorTests/ContractTests.swift

## Phase 3: User Story 1 - Layers combine with the six standard modes (P1) 🎯 MVP

**Goal**: the compositor draws each mode per the contract. **Independent test**: GPU grid read-back vs the CPU reference.

- [ ] CMP-004-T06 [US1] Add `cmp_blend` (backdrop texture(1), identity read or transformed bilinear sample, sanitize, × opacity, contract steps 1-5) and a non-blending pipeline in Packages/Compositor/Sources/Compositor/CompositorShaders.swift
- [ ] CMP-004-T07 [US1] Compositor: per-record `blendMode`, lazily pooled second composite, ping-pong per non-normal layer, swap, `blendDraws`, recycle on size change and deinit (CMP-004-R6) in Packages/Compositor/Sources/Compositor/Compositor.swift
- [ ] CMP-004-T08 [US1] GPU tests: a pattern layer (half floats blitted from a buffer) gives a backdrop × source grid (5 encoded levels × 4 alpha pairs, per-channel variation); each mode's composite within 1e-3 of the reference and a `bgra8Unorm_srgb` output within 1/255; acceptance values on 50 % grey; mode over transparent = normal (CMP-004-S1, S2, S3) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift

## Phase 4: User Story 2 - Modes with opacity, transforms, fades and the stack (P1)

**Goal**: modes compose with CMP-002/003/005. **Independent test**: opacity, transform and apply cases on the GPU.

- [ ] CMP-004-T09 [US2] GPU tests: opacity 0 bit-identical to the stack without the layer and 0.5 matches the reference for every mode; a transformed mode layer matches a transformed normal layer outside the overlap and the reference inside; a mode change at `apply` shows next frame without a new layer or preparation; two mode layers in a row; normal-only stack allocates no second composite (CMP-004-S4, R5, R6) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift
- [ ] CMP-004-T10 [US2] Full Compositor suite unchanged (normal stacks bit-identical): `swift test --package-path Packages/Compositor`; RenderGoldens unchanged: `swift test --package-path Packages/RenderGoldens`

## Phase 5: User Story 3 - Scenes keep and show modes (P2)

**Goal**: the scene format draws known names and keeps unknown ones. **Independent test**: validation and round trips.

- [ ] CMP-004-T11 [US3] Validation warns only for names `LayerBlendMode(rawValue:)` rejects; `liveState` maps names and fills `preservedBlendModes`; capture writes `rawValue` or the preserved string while the live mode is `.normal` (CMP-004-R7, R8) in Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift and SceneLiveState.swift
- [ ] CMP-004-T12 [US3] Tests: each known name gives no warning and reaches the live stack; capture writes it; "softLight" is warned, listed by `SceneRepairReport` as a note, drawn as normal and written back after load → capture; decode → encode keeps it; existing tests' example unsupported mode becomes "softLight" (CMP-004-S5) in Packages/SceneFormat/Tests/SceneFormatTests/SceneBlendModeTests.swift, SceneValidationTests.swift
- [ ] CMP-004-T13 [US3] ImportFuzz still passes: `swift test --package-path Packages/ImportFuzz`

## Phase 6: Polish & cross-cutting

- [ ] CMP-004-T14 [P] GPU timing bench (skipped unless `CMP004_BENCH=1`): 1920 × 1080, two layers, each mode, median GPU time; run in Release on the Mac and record in docs/test-reports/blend-modes.md as not device evidence (CMP-004-S6) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift
- [ ] CMP-004-T15 [P] ADR-0037 (blend functions in sRGB-encoded space, coverage linear, add = clamped separable) in docs/adr/0037-blend-mode-colour-space.md and docs/adr/README.md; ADR-0028 consequence and specs/059-scn-001-versioned-scene-format/contracts/scene-document.md list the drawn names
- [ ] CMP-004-T16 Linux shape: `swift build`/`swift test --filter LayerBlendReference` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` in Packages/Compositor; SceneFormat builds the same way
- [ ] CMP-004-T17 iOS simulator run of `CompositorTests/LayerBlendCompositeTests` on a dedicated simulator (deleted afterwards)
- [ ] CMP-004-T18 Repo checks pass: check_compliance.py, validate_docs.py, check_motion_policy.py, check_permission_catalog.py, test_scripts.py; spec status set to Implemented

## Dependencies

- T02 → T03-T05 → T06-T08 (US1) → T09-T10 (US2). T11-T13 (US3) need only T02. T14 needs T07; T15-T18 last.

## Parallel opportunities

- T03 and T04 (new files) together; T11-T12 (SceneFormat) in parallel with US1/US2; T14 and T15.

## Implementation strategy

MVP = Phases 1-3 (the acceptance). Then US2 (stack interactions), US3 (scenes), polish.
