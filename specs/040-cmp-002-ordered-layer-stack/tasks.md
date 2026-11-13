# Tasks: CMP-002 Ordered Layer Stack

**Input**: Design documents from `specs/040-cmp-002-ordered-layer-stack/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/layer-stack.md,
quickstart.md

**Tests**: Requested by the roadmap row (unit + snapshots + GPU performance) and the owner's rule 7
budgets: a unit test about 1-2 s and at most 10 s, the package suite under 1 minute, GPU tests at
64 × 64.

**Format**: `[ID] [P?] [Story] Description`. `{device}` = needs D1-D3 and a person; left open by
this row.

## Phase 1: Setup

- [ ] CMP-002-T01 Baseline: run `swift test --package-path Packages/Compositor` on the worktree before any change and record the pass count (no file change)

## Phase 2: Foundational (blocks every story)

- [ ] CMP-002-T02 [P] `LayerInstanceID` (UInt64 ≥ 1, Hashable, Comparable), `LayerKind` (identifier, `maximumInstances: Int?`), `LayerDescriptor` (kind, `parameters: [String: Double]`), `LayerStackEntry` (id, descriptor, settings), `LayerStackError` (`unknownLayer`, `indexOutOfRange(index:validRange:)`, `stackFull(limit:)`, `kindLimitReached`) and `LayerStack` ("index 0 bottom"; `maximumLayerCount` = 8; `add(_:settings:at:)` at 0…count, default top; `remove`; `duplicate` at index + 1 with a new ID; `move(_:to:)` at 0…count − 1; IDs from a counter starting at 1, never reused; equality on entries only; every refusal leaves the stack unchanged) in `Packages/Compositor/Sources/Compositor/LayerStack.swift` (CPU, outside the Metal guard)
- [ ] CMP-002-T03 [P] Kinds next to their layers: `LayerKind.camera` (`camera`, maximumInstances 1) in `Packages/Compositor/Sources/CameraLayer/CameraLayerKind.swift`; `LayerKind.circularSpectrum` (`spectrum.circular`) and `.linearSpectrum` (`spectrum.linear`) in `Packages/Compositor/Sources/SpectrumLayers/SpectrumLayerKinds.swift` (CPU, outside the Metal guard)
- [ ] CMP-002-T04 Move the compositor's parallel per-layer arrays into one internal record per layer (id, layer, slots, pictures, outcome, prepare error, shown picture) with no behaviour change in `Packages/Compositor/Sources/Compositor/Compositor.swift`; every existing CompositorTests test still passes

## Phase 3: User Story 2 - Add, remove and duplicate layers (P1)

**Goal**: the stack's operations and refusals (CMP-002-R1 to R6, R12).
**Independent test**: `LayerStackTests` on the host and in the Linux shape.

- [ ] CMP-002-T05 [P] [US2] Stack tests: add at top, 0 and middle (order and distinct IDs); index out of range (−1, count + 1) refused; 8-layer limit for add and duplicate; duplicate placement, new ID, equal descriptor and settings; second camera (add and duplicate) refused with `kindLimitReached(.camera)`; remove unknown refused; remove then add never reuses an ID; move to every index, to its own index (no-op) and out of range; every refusal leaves the stack equal to before; equality ignores the ID counter in `Packages/Compositor/Tests/CompositorTests/LayerStackTests.swift` (no Metal)

## Phase 4: User Story 1 - Reorder changes what is on top (P1) MVP

**Goal**: the roadmap acceptance (CMP-002-S1) through a stack applied to the compositor.
**Independent test**: `LayerStackApplyTests.testReorderingRedAndBlueChangesTopmostColor`.

- [ ] CMP-002-T06 [US1] `Compositor.init(device:)`, `LayerFactory`, `apply(_:makeLayer:)` per the contract (equal stack no-op; identity settings only → `unsupportedCompositeSettings(index:)`; reuse records by ID at their new index; factory only for new IDs → `layerCreationFailed(index:_:)` on throw; `duplicateLayer(index:)` for a shared object; atomic; new layers' pictures created and prepared now when a size is known; removed records released; flash history kept), `appliedStack`, `layerID(at:)`, `layerPreparations` in `Packages/Compositor/Sources/Compositor/Compositor.swift`
- [ ] CMP-002-T07 [US1] Acceptance snapshot test at 64 × 64: stack [red, blue] opaque, overlapping full-frame → every pixel blue within 1/255; `move(red, to: 1)`, apply → every pixel red within 1/255; neither layer prepared again in `Packages/Compositor/Tests/CompositorTests/LayerStackApplyTests.swift`

## Phase 5: User Story 3 - Edits apply between frames without stalls (P1)

**Goal**: reuse, preparation only of new layers, release, steady frames (CMP-002-R7 to R11, R14).
**Independent test**: the remaining `LayerStackApplyTests`.

- [ ] CMP-002-T08 [US3] Apply tests: adding a third layer creates and prepares exactly one (factory call and `layerPreparations` counts); applying an equal stack calls nothing; a removed layer is released (weak reference nil); a stack applied before the first frame is prepared with that frame's size; a factory throw, a shared object and non-identity settings each leave the previous stack applied and drawing; a failed prepare shows only that layer unavailable; 60 frames after edits create no pictures (`pictureAllocations` unchanged); the flash guard's gain history survives an apply; a reordered `.lastGoodFrame` layer keeps its last good picture; an applied empty stack composites to transparent (a size change after an apply re-prepares every layer: covered by CMP-001's resize tests) in `Packages/Compositor/Tests/CompositorTests/LayerStackApplyTests.swift`

## Phase 6: User Story 4 - The Camera visual is unchanged (P2)

**Goal**: the app's one stack goes through `LayerStack` (CMP-002-R13).
**Independent test**: `projectM-iOSTests`, `CameraUITests`, `CameraPrivacyStatusUITests`.

- [ ] CMP-002-T09 [US4] `CameraVisualHost.make` builds `LayerStack` [camera (`.camera`), circular spectrum (`.circularSpectrum`)] and applies it with a factory returning the host's camera and spectrum layers; header notes updated (editor: CMP-015 and the editing UI rows) in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`
- [ ] CMP-002-T10 [US4] Run the app tests on an iOS 27.2 simulator: `projectM-iOSTests`, `projectM-iOSUITests/CameraUITests`, `projectM-iOSUITests/CameraPrivacyStatusUITests` (known worktree failure: `PresetTests.testBundledIncludedScopeMatchesRelease1_0`, empty preset submodules); count PosterBoard reports before and after

## Phase 7: Polish & Cross-Cutting

- [ ] CMP-002-T11 [P] ADR-0013 "Amendment: CMP-002 ordered layer stack" (value stack, ID reuse rule, apply semantics, camera limit, 8 layers) in `docs/adr/0013-compositor-layer-protocol.md`; header comments of `Compositor.swift` and `Packages/Compositor/Package.swift` (comment only) mention the stack
- [ ] CMP-002-T12 Linux shape: `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` runs `LayerStackTests`
- [ ] CMP-002-T13 Simulator package run: `xcodebuild test -scheme Compositor` from `Packages/Compositor` on the iOS 27.2 simulator
- [ ] CMP-002-T14 `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py` OK; spec status updated
- [ ] CMP-002-T15 {device} Per-layer frame cost of a 4-layer stack (projectM or a material, camera, two spectra) on D1, D2 and D3: GPU time per frame with 1 to 4 layers, recorded in `docs/test-reports/performance.md` (CMP-002-S6, R15)

## Dependencies

- T01 → T02, T03, T04 → T05 (needs T02, T03) and T06 (needs T02, T04) → T07, T08 → T09 → T10.
- T11 any time after T06; T12 after T05; T13 after T08; T14 last; T15 after merge, on devices.

## Parallel opportunities

- T02 and T03 (different files); T05 alongside T06; T11 alongside T09.

## Implementation strategy

MVP = Phases 2-4 (stack model, apply, the acceptance test). Then US3's semantics tests, the app
wiring, polish. T15 stays open for the device stage.
