# Tasks: CMP-013 Render Caching

**Input**: Design documents from `specs/113-cmp-013-render-caching/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/render-caching.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-013-T01 Run the baseline before any change: `swift test --package-path Packages/Compositor` on the Mac; record the count and duration in docs/test-reports/render-caching.md — Verified 2026-11-14: swift test --package-path Packages/Compositor at a93c29db: 335 tests (5 skipped, 0 failures, 8.5 s); docs/test-reports/render-caching.md

## Phase 2: Foundational (blocks every story)

- [X] CMP-013-T02 Add the plain-Swift model outside any Metal guard: `LayerRenderDependencies` (`time`, `audio`, `modulation`, `externalInput`, `contentGeneration`, `parameterGeneration`; `isCacheable` = no flag set; `.dynamic`), `LayerRenderCacheKey` (generations, `LayerPictureDescriptor`, content scale, Reduce flashing, epoch; failable init returning nil for undeclared or non-cacheable), `LayerRenderCacheEntry` (`canReuse(_:hasGoodPicture:)`, `drop()`, `rendered(_:)`), `LayerDrawInput` (`isUnchanged(from:)`), and the `LayerRenderCaching` protocol with a default `renderReused(frame:)` (CMP-013-R1-R3, R12) in Packages/Compositor/Sources/Compositor/LayerRenderCache.swift — Verified 2026-11-14: RenderCacheModelTests (5) on the host and in the Linux shape; swift build no warnings
- [X] CMP-013-T03 [P] CPU tests: cacheability per flag; key equality and inequality per input (content, parameters, size, content scale, Reduce flashing, epoch); undeclared → nil; entry transitions (no reuse without a good picture, drop, store only a non-nil key); the draw-input rule; Linux shape (CMP-013-R1-R4, R12) in Packages/Compositor/Tests/CompositorTests/RenderCacheModelTests.swift — Verified 2026-11-14: swift test --filter RenderCacheModelTests: 5 tests, 0.002 s, host and Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE)
- [X] CMP-013-T04 `TexturePool`: a purge count incremented by `purge()`, returned by `tick()` (`@discardableResult`) and readable as `purgeCount` (CMP-013-R7, memory pressure) in Packages/Compositor/Sources/Compositor/TexturePool.swift — Verified 2026-11-14: testAPoolPurgeRendersOnce (purge → epoch moves, exactly one render); TexturePoolSwitchTests unchanged

## Phase 3: User Story 1 - A static photo is drawn once (P1) 🎯 MVP

**Goal**: one photo render over ten frames; a fit or content change renders exactly once; placement changes render nothing.

- [X] CMP-013-T05 [US1] Compositor level 1: per record the adopter (cast once at creation), `cache` entry and `reusedThisFrame`; in the frame loop build the key, reuse when the entry matches and `slots.lastGoodIndex` exists (not when DEBUG `failingRender` names the layer), call `renderReused(frame:)`, else drop, render and store the key on success; drop on every other path, on `allocatePictures` and `prepareLayer`; `isRenderCachingEnabled` (default true), `renderCacheEpoch`, `invalidateRenderCache()`, `renderCacheHits`, `wasReused(layer:)`; epoch bump on size allocation, a pool purge seen at `tick`, an observed GPU error, a visual fault, `resetRenderHealth()` and any `false` return after the frame tick (CMP-013-R4, R5, R7, R8, R10, R13) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: RenderCacheCompositeTests (18) pass; Compositor suite 359 tests, 0 failures
- [X] CMP-013-T06 [US1] `ImageLayerSource` adopts `LayerRenderCaching`: one slot pull shared by the dependency read and `render` (texture plus its load generation), `contentGeneration` = held load generation, `parameterGeneration` bumped when `fit` changes, `renderReused` counts `framesShown`, new `renderCount` (CMP-013-R11) in Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift — Verified 2026-11-14: testAStaticPhotoRendersOnceOverTenFramesAndAFitChangeRendersItExactlyOnce (renderCount 1, framesShown 10); ImageLayerTests unchanged
- [X] CMP-013-T07 [US1] GPU tests: the acceptance with the real photo layer (1 render over 10 frames, 10 frames shown; fit change → exactly 1 more; a new photo loaded → 1 render and the old picture never shown); opacity, transform, blend and mask changes → 0 renders and the read-back shows the change (CMP-013-S1, R5) in Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift — Verified 2026-11-14: testAStaticPhotoRendersOnce… (1 render over 10 frames; fit → exactly 1 more; new photo → transparent while loading, then exactly 1 render), testPlacementChangesDoNotRenderTheLayerButShowInTheFrame (opacity, transform, blend, mask: 0 renders, frame bytes change)

## Phase 4: User Story 2 - Caching never changes what is shown (P1)

- [X] CMP-013-T08 [US2] Compositor level 2: `LayerRecord.drawn` and `GroupRecord.drawnOpacity`; the stack drawing moved into `encodeStack(onto:size:commandBuffer:)`; reuse when caching is on, the composite is valid, every layer's `LayerDrawInput` (picture drawn or −1 when not visible, shown opacity, reused) and every group's shown opacity are unchanged; the composite marked invalid on a changed `apply`, `setSoloMute`, an epoch bump and a failed frame, valid after a successful frame; `compositeReused`, `compositeReuses`; flash guard, output, capture and recording unchanged (CMP-013-R6, R13) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: testAnAllStaticStackReusesTheCompositeAndCapturesTheSameFrame (2 reuses in 3 frames, bytes and REC-001 capture identical); full Compositor suite green
- [X] CMP-013-T09 [US2] GPU tests: the bit-identity sequence (two compositors, caching on and off, the same factory and script of at least 20 frames: content change, fit, opacity fade, transform, blend, mask, group opacity, solo/mute, size change, Reduce flashing, purge; every output frame read back and compared byte for byte); an all-static stack reuses the composite and stays byte-identical; capture of a reused frame equals the uncached capture (CMP-013-R9, S3) in Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift — Verified 2026-11-14: testOutputWithCachingIsBitIdenticalToWithoutOverAScriptedSequence: 44 frames, every output frame byte-identical (raw rgba16Float), 20 composites reused, base renders 6 vs 44, photo 7 vs 44

## Phase 5: User Story 3 - Every invalidation shows a fresh picture (P1)

- [X] CMP-013-T10 [US3] GPU tests, one per trigger of the spec's invalidation table: content, parameter, size, Reduce flashing, content scale, pool purge, `resetRenderHealth`, explicit `invalidateRenderCache`, caching switched off and on, a failed render (one-picture layer), a held fault, an observed GPU error (DEBUG `faultInjection.gpuFault`), a frame that returns false, apply/solo-mute/group (composite only, no layer render), a hidden static layer stays cached and un-hiding draws it at once (edge case); the colour space and format are fixed by the picture contract today, so their trigger is covered by the key's descriptor equality in T03; each counts renders and checks the read-back (CMP-013-R7, S2) in Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift — Verified 2026-11-14: 13 trigger tests in RenderCacheCompositeTests (content, parameter, size, Reduce flashing and content scale, purge, health reset and explicit invalidation, caching off/on, failed render, held fault with retry at tick 30, observed GPU error, half-way failed frame, stack/group/solo-mute composite only, hidden static layer); key descriptor equality in RenderCacheModelTests
- [X] CMP-013-T11 [P] [US3] `TextLayerSource` adopts `LayerRenderCaching` (pull shared with `render`, `contentGeneration` = upload generation, `renderReused` counts `framesShown`, `renderCount`), with tests: 1 render over 10 frames, a new message → exactly one more render after it is rasterized (CMP-013-R11) in Packages/Compositor/Sources/TextLayer/TextLayerSource.swift and Packages/Compositor/Tests/TextLayerTests/TextLayerCacheTests.swift — Verified 2026-11-14: TextLayerCacheTests: 1 render over 10 frames, new message → exactly 1 more, empty message dropped at once; TextLayerSourceTests unchanged

## Phase 6: User Story 4 - Dynamic layers are never cached (P1)

- [X] CMP-013-T12 [US4] GPU tests with caching on: a spectrum layer, layers declaring time, audio, modulation and external input, and an undeclared layer each render 10 of 10 frames; a stack containing one dynamic layer never reuses the composite (CMP-013-R2, S4) in Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift — Verified 2026-11-14: testDynamicAndUndeclaredLayersRenderEveryFrame: time, audio, modulation, external input, undeclared and the linear spectrum each 10 of 10; composite never reused

## Phase 7: User Story 5 - GPU time (P2)

- [X] CMP-013-T13 [US5] Opt-in bench `CMP013_BENCH=1`: 6 static layers (normal and one blend mode) at 1920 × 1080, 120 frames caching off vs on, GPU start/end per frame, median and p95 printed, not asserted; recorded in docs/test-reports/render-caching.md as not device evidence (CMP-013-S5) in Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift — Verified 2026-11-14: CMP013_BENCH=1 swift test -c release -Xswiftc -DDEBUG --filter RenderCacheBench: caching off median 0.538 ms (p95 0.688), on median 0.052 ms (p95 0.062); Mac, not device evidence

## Phase 8: Polish & Cross-Cutting

- [ ] CMP-013-T14 ADR for the caching contract (next free number at commit time) in docs/adr/ and its row in docs/adr/README.md; Package.swift and Compositor.swift header notes
- [ ] CMP-013-T15 Regression: Compositor full suite (host and Linux shape), RenderGoldens (goldens unchanged), SceneFormat, ImportFuzz, ShowControl, SceneArchive, VisualGenerators, app unit tests and the photo and text UI tests on a dedicated iOS 27.2 simulator (created and deleted; PosterBoard reports counted); repository checks (compliance, docs, motion policy, permission catalog, status events, script tests); report docs/test-reports/render-caching.md; spec status Implemented

## Dependencies

T01 → T02 → (T03, T04) → T05 → T06 → T07 → T08 → T09 → T10 → T11, T12, T13 → T14 → T15. US1 is the MVP;
US2-US4 build on the compositor change of US1; T03 and T11 can run in parallel with neighbours.

## Implementation strategy

Model first (Linux-testable), then level 1 with the acceptance, then level 2 with the bit-identity
proof, then the invalidation table, dynamic layers and the bench. One commit per complete change.
