# Tasks: CMP-004 Blend Mode Library

**Input**: Design documents from `specs/099-cmp-004-blend-mode-library/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/blend-modes.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-004-T01 Run the baseline checks before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` pass on the Mac (record counts in docs/test-reports/blend-modes.md) — Verified 2026-11-14: swift test Compositor 215 tests, SceneFormat 86 tests, 0 failures (before any change)

## Phase 2: Foundational (blocks every story)

- [X] CMP-004-T02 Make `LayerBlendMode` a `String`, `CaseIterable` enum with raw values "normal", "add", "screen", "multiply", "overlay", "difference"; `isSupportedByCompositor` true for every mode; doc comments (CMP-004-R1) in Packages/Compositor/Sources/Compositor/LayerContract.swift, LayerStack.swift comment — Verified 2026-11-14: ContractTests and LayerBlendReferenceTests.testModeNamesAreStable pass; swift build of SceneFormat
- [X] CMP-004-T03 [P] Add the CPU reference `LayerBlend` (sRGB `encode`/`decode`, `function(_:backdrop:source:)`, `composite(_:backdrop:source:opacity:)`) in typed steps, outside any Metal guard (CMP-004-R2-R5, R10) in Packages/Compositor/Sources/Compositor/LayerBlend.swift — Verified 2026-11-14: LayerBlendReferenceTests (8 tests) pass on the Mac and in the Linux shape
- [X] CMP-004-T04 [P] CPU tests: hand-checked values (multiply(0.5, 0.5) = 0.25, screen(0.5, 0.5) = 0.75, overlay threshold at 0.5, difference symmetric, add saturates, normal = Cs), transfer round trip, alpha cases (transparent backdrop = normal, αs = 0 = backdrop, opacity scaling), a 5-level grid against inline formulas (CMP-004-S3) in Packages/Compositor/Tests/CompositorTests/LayerBlendReferenceTests.swift — Verified 2026-11-14: swift test --filter LayerBlendReference: 8 tests, 0 failures, 0.001 s
- [X] CMP-004-T05 Update ContractTests for every mode being supported and `isSupportedByCMP001` false for non-normal in Packages/Compositor/Tests/CompositorTests/ContractTests.swift — Verified 2026-11-14: swift test --filter ContractTests: 3 tests pass

## Phase 3: User Story 1 - Layers combine with the six standard modes (P1) 🎯 MVP

**Goal**: the compositor draws each mode per the contract. **Independent test**: GPU grid read-back vs the CPU reference.

- [X] CMP-004-T06 [US1] Add `cmp_blend` (backdrop texture(1), identity read or transformed bilinear sample, sanitize, × opacity, contract steps 1-5) and a non-blending pipeline in Packages/Compositor/Sources/Compositor/CompositorShaders.swift — Verified 2026-11-14: LayerBlendCompositeTests grid test: worst 4.88e-4 linear, 0.59/255 encoded; a mutated overlay branch fails it
- [X] CMP-004-T07 [US1] Compositor: per-record `blendMode`, lazily pooled second composite, ping-pong per non-normal layer, swap, `blendDraws`, recycle on size change and deinit (CMP-004-R6) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: LayerBlendCompositeTests (9 GPU tests) pass on the Mac host and the iOS 27.2 simulator; full Compositor suite 233 tests pass
- [X] CMP-004-T08 [US1] GPU tests: a pattern layer (half floats blitted from a buffer) gives a backdrop × source grid (5 encoded levels × 4 alpha pairs, per-channel variation); each mode's composite within 1e-3 of the reference and a `bgra8Unorm_srgb` output within 1/255; acceptance values on 50 % grey; mode over transparent = normal; NaN and negative source pixels read as 0 like normal (CMP-004-S1, S2, S3) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift — Verified 2026-11-14: testEveryModeMatchesTheReferenceOnTheGrid, testFiftyPercentGreysGiveTheHandCheckedValues, testAModeOverTransparentIsExactlyNormal pass (Mac, iOS 27.2 simulator)

## Phase 4: User Story 2 - Modes with opacity, transforms, fades and the stack (P1)

**Goal**: modes compose with CMP-002/003/005. **Independent test**: opacity, transform and apply cases on the GPU.

- [X] CMP-004-T09 [US2] GPU tests: opacity 0 bit-identical to the stack without the layer and 0.5 matches the reference for every mode; a transformed mode layer matches a transformed normal layer outside the overlap and the reference inside; a mode change at `apply` shows next frame without a new layer or preparation; two mode layers in a row; normal-only stack allocates no second composite; a REC-001 frame capture with a mode layer equals the output, and a Reduce-flashing frame with mode layers encodes (flash guard on the finished composite) (CMP-004-S4, R5, R6) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift — Verified 2026-11-14: opacity, transform, apply, chain, allocation, capture/Reduce-flashing tests pass (Mac, iOS 27.2 simulator)
- [X] CMP-004-T10 [US2] Full Compositor suite unchanged (normal stacks bit-identical): `swift test --package-path Packages/Compositor`; RenderGoldens unchanged: `swift test --package-path Packages/RenderGoldens` — Verified 2026-11-14: Compositor 233 tests (215 existing unchanged + 18 new, 1 bench skipped), 13.7 s; RenderGoldens 39 tests pass, no golden re-recorded

## Phase 5: User Story 3 - Scenes keep and show modes (P2)

**Goal**: the scene format draws known names and keeps unknown ones. **Independent test**: validation and round trips.

- [X] CMP-004-T11 [US3] Validation warns only for names `LayerBlendMode(rawValue:)` rejects; `liveState` maps names and fills `preservedBlendModes`; capture writes `rawValue` or the preserved string while the live mode is `.normal` (CMP-004-R7, R8) in Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift and SceneLiveState.swift — Verified 2026-11-14: SceneBlendModeTests pass; SceneFormat 89 tests, 0 failures, 7.9 s (QA-004 meta-test included)
- [X] CMP-004-T12 [US3] Tests: each known name gives no warning and reaches the live stack; capture writes it; "softLight" is warned, listed by `SceneRepairReport` as a note, drawn as normal and written back after load → capture; decode → encode keeps it; "Screen" (wrong case) is unknown too; existing tests' example unsupported mode becomes "softLight" (CMP-004-S5) in Packages/SceneFormat/Tests/SceneFormatTests/SceneBlendModeTests.swift, SceneValidationTests.swift — Verified 2026-11-14: SceneBlendModeTests (3 tests) and the updated SceneValidationTests pass
- [X] CMP-004-T13 [US3] ImportFuzz still passes: `swift test --package-path Packages/ImportFuzz` — Verified 2026-11-14: ImportFuzz 15 tests pass; also ShowControl 31, SceneArchive 27

## Phase 6: Polish & cross-cutting

- [X] CMP-004-T14 [P] GPU timing bench (skipped unless `CMP004_BENCH=1`): 1920 × 1080, two layers, each mode, median GPU time; run in Release on the Mac and record in docs/test-reports/blend-modes.md as not device evidence (CMP-004-S6) in Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift — Verified 2026-11-14: CMP004_BENCH=1 Release run, three runs recorded in docs/test-reports/blend-modes.md (medians 0.12-0.31 ms, noise-dominated)
- [X] CMP-004-T15 [P] ADR-0037 (blend functions in sRGB-encoded space, coverage linear, add = clamped separable) in docs/adr/0037-blend-mode-colour-space.md and docs/adr/README.md; ADR-0028 consequence and specs/059-scn-001-versioned-scene-format/contracts/scene-document.md list the drawn names — Verified 2026-11-14: validate_docs.py OK (883 files)
- [X] CMP-004-T16 Linux shape: `swift build`/`swift test --filter LayerBlendReference` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` in Packages/Compositor; SceneFormat builds the same way — Verified 2026-11-14: Compositor --filter 'LayerBlendReference|ContractTests' 11 tests and SceneFormat --filter 'SceneBlendMode|SceneValidation|SceneForward' 11 tests pass with -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE
- [X] CMP-004-T17 iOS simulator run of `CompositorTests/LayerBlendCompositeTests` on a dedicated simulator (deleted afterwards) — Verified 2026-11-14: xcodebuild test on a new iOS 27.2 iPhone 17 simulator: 21 tests (1 bench skipped), TEST SUCCEEDED, 35 s; simulator deleted; no new PosterBoard reports
- [X] CMP-004-T18 Repo checks pass: check_compliance.py, validate_docs.py, check_motion_policy.py, check_permission_catalog.py, test_scripts.py; spec status set to Implemented; CMP-004-R9 (no UI) recorded in the report — Verified 2026-11-14: check_compliance OK, validate_docs OK, check_motion_policy OK, check_permission_catalog OK, test_scripts 147 tests OK

## Dependencies

- T02 → T03-T05 → T06-T08 (US1) → T09-T10 (US2). T11-T13 (US3) need only T02. T14 needs T07; T15-T18 last.

## Parallel opportunities

- T03 and T04 (new files) together; T11-T12 (SceneFormat) in parallel with US1/US2; T14 and T15.

## Implementation strategy

MVP = Phases 1-3 (the acceptance). Then US2 (stack interactions), US3 (scenes), polish.
