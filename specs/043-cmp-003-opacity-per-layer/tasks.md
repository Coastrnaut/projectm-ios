# Tasks: CMP-003 Opacity per Layer

**Input**: Design documents from `specs/043-cmp-003-opacity-per-layer/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/layer-opacity.md,
quickstart.md

**Tests**: Requested by the roadmap row (unit + snapshots + GPU performance) and the owner's rule 7
budgets: a unit test about 1-2 s and at most 10 s, the package suite under 1 minute, GPU tests at
64 × 64.

**Format**: `[ID] [P?] [Story] Description`. No `{device}` task: the device frame cost is
CMP-002-T15 (spec CMP-003-S6).

## Phase 1: Setup

- [ ] CMP-003-T01 Baseline: run `swift test --package-path Packages/Compositor` on the worktree before any code change and record the pass counts (no file change)

## Phase 2: Foundational (blocks every story)

- [ ] CMP-003-T02 [P] `LayerOpacityCurve` (`.linear`, `.easeInOut` = smoothstep `t²(3 − 2t)`), `LayerOpacityError` (`nonFiniteTarget`, `nonFiniteDuration`, `negativeDuration`), `LayerOpacityTransition` (`duration` "seconds, finite, >= 0", `curve`; throwing init; `.immediate`) and `LayerOpacityAnimator` (`init(opacity:)` clamped, non-finite → 1; `value`, `target`, `isAnimating`; `setOpacity(_:duration:curve:)` throws, finite target clamped to 0…1, new segment starts at `value`, duration 0 immediate; `setOpacity(_:transition:)`; `advance(by:)` adds `max(dt, 0)`, non-finite → 0, exact target from `elapsed ≥ duration`, value clamped to the segment) in `Packages/Compositor/Sources/Compositor/LayerOpacity.swift` (CPU, outside the Metal guard)
- [ ] CMP-003-T03 [P] `LayerCompositeSettings.isSupportedByCompositor` (normal blend and identity transform; any opacity) in `Packages/Compositor/Sources/Compositor/LayerContract.swift`; `isSupportedByCMP001` unchanged

## Phase 3: User Story 1 - Opacity 0 hides a layer, 1 leaves it unchanged (P1) MVP

**Goal**: the roadmap acceptance (CMP-003-R1 to R4, R11; S1, S2).
**Independent test**: `LayerOpacityCompositeTests` acceptance tests at 64 × 64.

- [ ] CMP-003-T04 [US1] `cmp_over` multiplies its sanitized premultiplied colour by `constant float &opacity [[buffer(0)]]` in `Packages/Compositor/Sources/Compositor/CompositorShaders.swift`; in `Packages/Compositor/Sources/Compositor/Compositor.swift` each record gets `opacity: LayerOpacityAnimator` (from the entry's or the layer's settings), `init` and `apply` refuse only `!isSupportedByCompositor`, `composite` advances every record's animator by `frame.frameDuration`, skips the draw at value 0 and passes the value with `setFragmentBytes`; `apply(_:opacityTransition:makeLayer:)` (default `.immediate`) retargets kept layers whose entry opacity changed
- [ ] CMP-003-T05 [US1] Acceptance tests: [blue, red] with red at opacity 0 equals the [blue] output exactly (bitwise read-back); red at opacity 1 equals the output of a compositor at the CMP-002 path (same stack, default settings) bitwise, also for a half-alpha layer; 0.5 red over blue reads (0.5, 0, 0.5, 1) within 1/255; `init(device:layers:)` honours a layer's opacity; a non-identity transform is still refused (CMP-003-R11) in `Packages/Compositor/Tests/CompositorTests/LayerOpacityCompositeTests.swift`; update the old refusal cases (opacity 0.5 → a transform) in `ContractTests.swift`, `LayerStackApplyTests.swift` and `TwoLayerCompositeTests.swift`

## Phase 4: User Story 2 - Opacity changes animate smoothly over time (P1)

**Goal**: fades (CMP-003-R5 to R7, R10; S3).
**Independent test**: `LayerOpacityAnimatorTests` (CPU, Linux shape too) and one GPU fade test.

- [ ] CMP-003-T06 [P] [US2] Animator tests with fixed frame-duration sequences: linear endpoints exact and monotonic over 60 frames of 1/60 s for a 1 s fade; ease-in-out endpoints exact, monotonic, below linear in the first half and above in the second; retarget mid-fade starts at the shown value (no jump); duration 0 immediate; non-finite target and negative or non-finite duration refused with no change; finite out-of-range target clamped; `advance` with a negative or non-finite duration does not move; a stall's clamped 0.1 s steps (CMP-001-R3) make progress at most 0.1 s per frame in `Packages/Compositor/Tests/CompositorTests/LayerOpacityAnimatorTests.swift` (no Metal)
- [ ] CMP-003-T07 [US2] GPU fade test: apply red over blue at opacity 0, then opacity 1 with a 0.5 s linear transition; frames at 1/60 s read the expected intermediate mix within 1/255 at frame 15 and exactly red from frame 30 on, in `Packages/Compositor/Tests/CompositorTests/LayerOpacityCompositeTests.swift`

## Phase 5: User Story 3 - Opacity edits are cheap and safe (P1)

**Goal**: reuse, no allocation, flash safety (CMP-003-R8, R9; S4, S5).
**Independent test**: the remaining `LayerOpacityCompositeTests`.

- [ ] CMP-003-T08 [US3] Tests: an opacity-only apply calls no factory and prepares nothing (`layerPreparations`, factory calls); 60 frames of a fade at a steady size create no pictures (`pictureAllocations`); a layer at opacity 0 keeps rendering (its render count grows) and reappears at once when set to 1; an equal stack does not restart a fade; a 30 Hz 0↔1 opacity strobe (white over black, opacity flipped every 2 frames at 60 fps, 2 s, Reduce flashing on) stays within 4 transitions per 1 s window in every area and a rise per frame ≤ 0.25/60 + 1e-3 (FlashAnalysis) in `Packages/Compositor/Tests/CompositorTests/LayerOpacityCompositeTests.swift`

## Phase 6: Polish & Cross-Cutting

- [ ] CMP-003-T09 [P] ADR-0013 "Amendment: CMP-003 opacity per layer" in `docs/adr/0013-compositor-layer-protocol.md`; update header comments in `Compositor.swift`, `LayerStack.swift` and `LayerContract.swift` (opacity now supported)
- [ ] CMP-003-T10 Linux shape: `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` runs `LayerOpacityAnimatorTests`
- [ ] CMP-003-T11 Simulator package run: `xcodebuild test -scheme Compositor` from `Packages/Compositor` on a fresh iOS 27.2 simulator (deleted afterwards); PosterBoard reports counted before and after
- [ ] CMP-003-T12 `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py` OK; spec status updated

## Dependencies

- T01 → T02, T03 → T04 → T05; T06 needs T02 only; T07, T08 need T04.
- T09 any time after T04; T10 after T06; T11 after T08; T12 last.

## Parallel opportunities

- T02 and T03 (different files); T06 alongside T04; T09 alongside T07/T08.

## Implementation strategy

MVP = Phases 2-3 (opacity in the composite and the acceptance tests). Then fades and their tests,
the reuse and flash-safety tests, polish.
