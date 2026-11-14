# Tasks: CMP-011 Layer Groups

**Input**: Design documents from `specs/109-cmp-011-layer-groups/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/layer-groups.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-011-T01 Run the baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; record counts in docs/test-reports/layer-groups.md — Verified 2026-11-14: swift test Compositor 296 tests (3 skipped), SceneFormat 101 tests at b75c685f; docs/test-reports/layer-groups.md

## Phase 2: Foundational (blocks every story)

- [X] CMP-011-T02 Add `LayerGroupID`, `LayerGroupSettings` (opacity clamped 0…1, non-finite reads 1), `LayerGroup` and `LayerGroupComposition` (`matrix(group:local:aspect:)` = `G(a) · L(a)` in typed steps; `needsIsolation(opacity:modes:)`) outside any Metal guard (CMP-011-R1, R5, R7) in Packages/Compositor/Sources/Compositor/LayerGroup.swift — Verified 2026-11-14: LayerGroupStackTests (12 tests) pass on the Mac host and in the Linux shape
- [X] CMP-011-T03 Amend `LayerStack`: `LayerStackEntry.group` (default nil), `groups`, group ID counter, `init(restoring:groups:)` with the new refusals, membership upkeep in `add`/`duplicate`/`move`/`remove` (research CMP-011-D2), equality with groups, `entries` `internal(set)`; new `LayerStackError` cases (CMP-011-R2, R4) in Packages/Compositor/Sources/Compositor/LayerStack.swift — Verified 2026-11-14: LayerGroupStackTests membership and restore tests; Compositor suite 318 tests, 0 failures
- [X] CMP-011-T04 `LayerStack` extension: `makeGroup`, `ungroup`, `setGroupSettings`, `moveGroup`, `group(_:)`, `members(of:)` (CMP-011-R3) in Packages/Compositor/Sources/Compositor/LayerGroup.swift — Verified 2026-11-14: LayerGroupStackTests testMakeGroupAndUngroup…, testRefusals…, testMoveGroup…
- [X] CMP-011-T05 [P] CPU tests: each operation and refusal leaves the stack unchanged on error; membership rule cases (insert inside a run joins, move out leaves, move to a run edge stays, duplicate joins, remove last removes the group, moveGroup refuses a split); restore refusals; ungroup keeps local settings; composed matrix vs hand-computed values (translation, scale about an anchor, rotation on 16:9) and identity group = local matrix bit for bit; isolation rule; Linux shape in Packages/Compositor/Tests/CompositorTests/LayerGroupStackTests.swift — Verified 2026-11-14: swift test --filter LayerGroupStackTests: 12 tests, 0.002 s, host and Linux shape (176 Compositor tests there)

## Phase 3: User Story 1 - Move a group and all its layers move together (P1) 🎯 MVP

**Goal**: composed placement drawn; local transforms unchanged. **Independent test**: GPU read-back of two coloured boxes.

- [X] CMP-011-T06 [US1] Compositor: group records (opacity animator, transform, enabled) rebuilt at `apply` (kept groups keep their animator); records carry their group; per-layer placement = own transform when the group is absent or identity, else the composed matrix through the existing inverse-matrix rows; draw loop refactored into one per-layer helper (identity, transformed, masked, blend ping-pong) (CMP-011-R5, R8, R9) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: LayerGroupCompositeTests; Compositor suite 318 tests 0 failures, RenderGoldens 39 unchanged
- [X] CMP-011-T07 [US1] GPU tests: a red and a green box layer in a group, group moved, scaled and rotated; each box's measured centre within 1 px of the prediction; `stack.entry(id).settings.transform` unchanged; ungrouped layers and identity groups bit-identical to the same stack without groups; print the pixel table (CMP-011-S1) in Packages/Compositor/Tests/CompositorTests/LayerGroupCompositeTests.swift — Verified 2026-11-14: testMovingScalingAndRotatingAGroup…: 10 centroids, max error 0.223 px; testAnIdentityGroup…: bit-identical

## Phase 4: User Story 2 - Fade or hide a group as one (P1)

**Goal**: isolated group opacity, enable state. **Independent test**: read-back vs CPU reference.

- [X] CMP-011-T08 [US2] Compositor: runs walked per frame; disabled or opacity-0 groups draw nothing (children still render); flattenable groups drawn directly; others into pooled offscreen group pictures (own blend partner), then `cmp_over` × group opacity; `isolatedGroupDraws`, `shownGroupOpacity(of:)`; offscreen pictures returned at size change and deinit (CMP-011-R6, R7, R8, R13) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: testGroupOpacityFadesTheGroupAsOnePicture, testADisabledGroup…, testAFlattenedGroup…, testGroupOpacityFadesWithATransition…
- [X] CMP-011-T09 [US2] GPU tests: two overlapping opaque boxes in a group at opacity 0.5 over a blue backdrop vs CPU reference (overlap shows no lower box; ≤ 0.01); per-child multiplication would differ (asserted different); disabled group leaves only the backdrop; flattened group (opacity 1) = ungrouped within half-float tolerance and `isolatedGroupDraws` 0; group opacity fade with a transition reaches the target; no picture allocated after the first isolated frame (CMP-011-S2, R9, R13) in Packages/Compositor/Tests/CompositorTests/LayerGroupCompositeTests.swift — Verified 2026-11-14: opacity 0.5 max error 0.0 vs CPU reference; disabled exact; flattened bit-identical, 0 isolated draws; fade monotonic; 0 pool misses at a steady size

## Phase 5: User Story 3 - Layer settings keep working inside groups (P2)

- [X] CMP-011-T10 [US3] GPU tests: masked child in a moved group (mask follows; outside exactly 0); screen child inside a group over a backdrop layer below the group (isolated: blends with the group's layers only; matches the CPU reference); fitted photo in a moved group; `isolatedGroupDraws` 1 for the screen case at opacity 1 (CMP-011-S3, R10) in Packages/Compositor/Tests/CompositorTests/LayerGroupCompositeTests.swift — Verified 2026-11-14: testAMaskedChildMovesWithItsGroup (0 outside violations), testAScreenChildBlendsWithinItsIsolatedGroup (5.6e-17), testAFittedPhotoMovesWithItsGroupUnchanged (bit-identical)
- [X] CMP-011-T11 [US3] GPU performance: a 4-child group at 1920 × 1080, flattened (opacity 1) vs isolated (opacity 0.5) vs ungrouped, GPU start/end, opt-in `CMP011_BENCH=1`, printed, not asserted; recorded in docs/test-reports/layer-groups.md as not device evidence (CMP-011-S5) — Verified 2026-11-14: CMP011_BENCH=1 release run: ungrouped 0.301, flattened 0.301, isolated 0.360 ms median per 1080p frame (Mac, not device evidence); docs/test-reports/layer-groups.md

## Phase 6: User Story 4 - Scenes keep groups, and damaged groups are reported (P1)

- [X] CMP-011-T12 [US4] `SceneGroup`, `SceneGroupChild`, `SceneDocument.groups`; decode of top-level `groups` (count limits before typed decoding: `tooMany`; defaults; clamping with `valueClamped`; unknown fields kept), encode only when non-empty (CMP-011-R11) in Packages/SceneFormat/Sources/SceneFormat/SceneGroup.swift, SceneDocument.swift, SceneDecoding.swift, SceneEncoding.swift — Verified 2026-11-14: SceneGroupTests round-trip and defaults tests; SceneFormat 110 tests pass, host and Linux shape
- [X] CMP-011-T13 [US4] Validation `invalidGroup` (a layer belongs to the first group that lists it); SCN-012 classification (damaged file, problem) and repair `repairGroups`; `liveState` builds stack groups and `preservedGroups`; capture writes live then preserved groups (CMP-011-R12) in Packages/SceneFormat/Sources/SceneFormat/SceneIssue.swift, SceneValidation.swift, SceneRepair.swift, SceneLiveState.swift — Verified 2026-11-14: SceneGroupTests degenerate, repair and live-state tests
- [X] CMP-011-T14 [US4] Scene tests: decode → encode byte-identical with a moved group; load → capture → encode byte-identical; scene without groups unchanged; local transforms unchanged after save and load; each degenerate structure (missing child, repeated child, layer in two groups, gap, empty, repeated ID, ID 0, nested child object) gives `invalidGroup`, opens, is drawn ungrouped and re-saved verbatim; `repairGroups` result and idempotence; 9 groups → `tooMany`; QA-004 meta-test passes (CMP-011-S4) in Packages/SceneFormat/Tests/SceneFormatTests/SceneGroupTests.swift — Verified 2026-11-14: swift test --filter SceneGroupTests: 9 tests, 0.06 s; QA-004 meta-test passes in the SceneFormat suite (110 tests)

## Phase 7: Polish & Cross-Cutting

- [X] CMP-011-T15 [P] ADR-0039 (isolated groups, flattened when exact); amend ADR-0028 and specs/059-scn-001-versioned-scene-format/contracts/scene-document.md (top-level `groups`, `invalidGroup`) and the SCN-012 repair table (`repairGroups`) in docs/adr/ and specs/ — Verified 2026-11-14: validate_docs OK (968 files); docs/adr/0039-layer-group-isolation.md, ADR-0028, SCN-001 contract and SCN-012 data model amended
- [X] CMP-011-T16 Regression: Compositor and SceneFormat full suites (host and Linux shape), RenderGoldens, ImportFuzz, ShowControl, SceneArchive, app unit tests on a dedicated iOS 27.2 simulator; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests); report docs/test-reports/layer-groups.md — Verified 2026-11-14: Compositor 318 (host) and 176 (Linux shape), SceneFormat 110 (host and Linux shape), RenderGoldens 39, ImportFuzz 15, ShowControl 31, SceneArchive 27, app unit tests 487 on iOS 27.2, all 0 failures; repository checks OK, script tests 153 OK

## Dependencies

T01 → T02 → T03 → T04 → T05; T06 → T07; T08 → T09 → T10 → T11; T12 → T13 → T14; T15 and T16 last.
US4 (T12-T14) depends only on T02-T04 and can run beside US1-US3.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: every requirement CMP-011-R1…R13 and criterion S1…S5 maps to at least one task (R1-R4:
T02-T05; R5, R8, R9: T06-T07, T09; R6, R7, R13: T08-T09; R10: T10; R11-R12: T12-T14; S5: T11). One
finding applied: the group's anchor (pivot) was unstated in the spec; CMP-011-R5 now says it is in
output fractions (research CMP-011-D3). No constitution conflicts; no duplicate or ambiguous
requirements left.
