# Tasks: CMP-012 Solo and Mute

**Input**: Design documents from `specs/112-cmp-012-solo-and-mute/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/solo-and-mute.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-012-T01 Run the baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; record counts in docs/test-reports/solo-and-mute.md — Verified 2026-11-14: swift test Compositor 318 tests (4 skipped, 0 failures, 11.0 s), SceneFormat 110 tests (0 failures, 2.2 s) at 35179456; docs/test-reports/solo-and-mute.md

## Phase 2: Foundational (blocks every story)

- [X] CMP-012-T02 Add `LayerSoloMute` (four sets; `setSolo`/`setMute` for layers and groups, `clear`, `isEmpty`, queries, `isSoloActive(in:)` counting only IDs present in the stack, `lets(_:in:)` = not muted, group not muted, and (no solo active, or layer or group soloed), `hiddenLayers(in:)`, `visibleLayers(in:)` adding saved opacity > 0 and group enabled with opacity > 0, `pruned(to:)`; no `Codable`) outside any Metal guard (CMP-012-R1, R3, R4, R5) in Packages/Compositor/Sources/Compositor/LayerSoloMute.swift; header note in Packages/Compositor/Sources/Compositor/LayerStack.swift — Verified 2026-11-14: LayerSoloMuteTests (8 tests) pass on the Mac host and in the Linux shape; no warnings
- [X] CMP-012-T03 [P] CPU tests: empty overlay lets everything; single solo; union of solos; mute; mute wins over solo and a muted solo keeps solo active; group solo, child solo inside a group, group mute, disabled group stays hidden under solo (`visibleLayers`); stale layer and group IDs ignored and pruned; a solo on a layer at saved opacity 0 keeps solo active and leaves `visibleLayers` empty (edge case); setting the overlay never changes the stack's equality or entries; Linux shape (CMP-012-R2-R5) in Packages/Compositor/Tests/CompositorTests/LayerSoloMuteTests.swift — Verified 2026-11-14: swift test --filter LayerSoloMuteTests: 8 tests, 0.002 s, host and Linux shape

## Phase 3: User Story 1 - Solo a layer, scene untouched (P1) 🎯 MVP

**Goal**: only the soloed layer drawn; documents and saved flags unchanged; exact restore.

- [ ] CMP-012-T04 [US1] Compositor: `LayerRecord.overlayHidden`; `soloMute`, `setSoloMute(_:)`, resolution at the end of `apply` and in `setSoloMute` (records without a stack ID never hidden); `isVisible` also requires `!overlayHidden`; `isHiddenBySoloMute(layer:)`, `soloMuteHiddenLayers` counted per frame (CMP-012-R6, R9, R10, R11, R12) in Packages/Compositor/Sources/Compositor/Compositor.swift
- [ ] CMP-012-T05 [US1] GPU tests: three opaque boxes, solo the middle → read-back shows only it (CMP-012-S1); stack entries, settings and group enabled flags equal before, during and after; two solos → both in stack order; clear → bit-identical to the frame before; flash gain 1 throughout; `isHiddenBySoloMute(layer:)` and `soloMuteHiddenLayers` report the hidden layers (CMP-012-R12) in Packages/Compositor/Tests/CompositorTests/LayerSoloMuteCompositeTests.swift
- [ ] CMP-012-T06 [P] [US1] Document tests: a scene document with layers and a disabled group, its stack restored, an overlay soloing and muting; encoded bytes, saved opacities and `enabled` flags identical before, during and after; live-state capture unchanged; `SceneHistory.record` of the state during the solo is suppressed (no undo step) (CMP-012-R2, R8, S5) in Packages/SceneFormat/Tests/SceneFormatTests/SceneSoloMuteTests.swift

## Phase 4: User Story 2 - Mute, and mute with solo (P1)

- [ ] CMP-012-T07 [US2] GPU tests: mute the top layer = the stack without it (bit for bit); solo plus mute of the same layer → transparent, others hidden; muted layer keeps `.rendered` outcome every frame; un-mute → bit-identical to before; an opacity fade started before a mute keeps advancing while muted and shows its current value on un-mute, and the overlay change itself has no fade (CMP-012-R11); `layerPreparations` and `pictureAllocations` unchanged across mute, solo and clear (CMP-012-R6, R7, R10, S3, S4) in Packages/Compositor/Tests/CompositorTests/LayerSoloMuteCompositeTests.swift

## Phase 5: User Story 3 - Groups (P2)

- [ ] CMP-012-T08 [US3] GPU tests: group solo shows only its members; solo of one child of a moved group at opacity 0.5 matches the CPU reference (isolated, ≤ 0.01) and an opacity-1 group with a soloed normal child is flattened while its hidden screen child is ignored (`isolatedGroupDraws` 0); group mute hides members which keep rendering; disabled group stays hidden under a child solo (CMP-012-R5, R9, S2) in Packages/Compositor/Tests/CompositorTests/LayerSoloMuteCompositeTests.swift
- [ ] CMP-012-T09 [US3] GPU performance: 8 layers at 1920 × 1080, none vs 4 muted, GPU start/end, opt-in `CMP012_BENCH=1`, printed, not asserted; recorded as not device evidence (CMP-012-S6) in Packages/Compositor/Tests/CompositorTests/LayerSoloMuteCompositeTests.swift and docs/test-reports/solo-and-mute.md

## Phase 6: Polish & Cross-Cutting

- [ ] CMP-012-T10 Regression: Compositor and SceneFormat full suites (host and Linux shape), RenderGoldens, ImportFuzz, ShowControl, SceneArchive, app unit tests on a dedicated iOS 27.2 simulator (created and deleted); repository checks (compliance, docs, motion policy, permission catalog, status events, script tests); report docs/test-reports/solo-and-mute.md; spec status Implemented

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T07 → T08 → T09; T06 needs only T02; T10 last.

## Parallel opportunities

T03 and T06 (different packages and files) beside T04-T05.

## Implementation strategy

MVP = T01-T05 (the acceptance). Then T06-T08 for the rest of the behaviour, T09 bench, T10 regression.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: every requirement CMP-012-R1…R12 and criterion S1…S6 maps to at least one task (R1, R3-R5:
T02-T03, T08; R2, R8: T03, T06; R6, R7, R10: T07; R9: T04, T08 and the RenderGoldens regression in
T10; R11, R12: T04, T05, T07; S1: T05; S2: T07-T08; S3-S4: T05, T07; S5: T06; S6: T09). Three
findings applied: R11 (fades continue, no overlay fade) and R12 (diagnostics) had no asserting test,
now in T07 and T05; the spec's edge case "solo on an empty layer" had none, now in T03. R8's show
cues and archives store scene documents (SHOW and FILE rows), so T06's document-bytes test covers
them; no separate test. No constitution conflicts; no duplicate or ambiguous requirements left.
