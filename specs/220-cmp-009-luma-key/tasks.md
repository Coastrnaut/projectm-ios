# Tasks: CMP-009 Luma Key

**Input**: Design documents from `specs/220-cmp-009-luma-key/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/luma-key.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute,
UI test under 30 s.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-009-T01 Baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; create the simulator "CMP9 iPhone 17" (iOS 27.2); record counts and the PosterBoard report count in docs/test-reports/luma-key.md — Verified 2026-11-14: swift test Compositor 543 CompositorTests (8 skipped), SceneFormat 175, 0 failures before any change; simulator created; 26 PosterBoard reports

## Phase 2: Foundational (blocks every story)

- [X] CMP-009-T02 Add `LayerLumaKey` ("low 0…1 (non-finite reads 0); low ≤ high (a reversed pair is swapped)", "high 0…1 (non-finite reads 0.1)", "softness 0…0.5 (non-finite reads 0)", `inverted`), `blackKey` (0, 0.1, 0.05, false), `luma(red:green:blue:alpha:)` (contract K1 steps 1-3), `keep(luma:)` (K1 steps 4-5) and `keep(red:green:blue:alpha:)` in typed `Double` steps outside any Metal guard (CMP-009-R1, R2, R3, R5) in Packages/Compositor/Sources/Compositor/LayerLumaKey.swift — Verified 2026-11-14: LayerLumaKeyReferenceTests (8 tests) pass on the Mac host and in the Linux shape
- [X] CMP-009-T03 Add `lumaKey: LayerLumaKey?` (default nil, additive init parameter) to `LayerCompositeSettings` in Packages/Compositor/Sources/Compositor/LayerContract.swift — Verified 2026-11-14: LayerCompositeSettings.lumaKey used by LayerLumaKeyCompositeTests, SceneLumaKeyTests and the app mapping; Compositor suite 562 tests, 0 failures
- [X] CMP-009-T04 [P] CPU reference tests: luma of black, white, mid-grey sRGB 0.5, pure primaries (the Rec. 709 weights); premultiplied input (half-alpha colour gives the same luma as opaque); alpha 0 reads luma 0; keep 0 inside the range and 1 beyond the softness band; ramp monotonic on both sides (dense sweep, 0 violations); softness 0 hard cut; invert is 1 − keep; clamping and reversed-range swap in Packages/Compositor/Tests/CompositorTests/LayerLumaKeyReferenceTests.swift — Verified 2026-11-14: swift test --filter LayerLumaKeyReferenceTests: 8 tests, 0.002 s, host and Linux shape (-DCOMPOSITOR_NO_METAL)

## Phase 3: User Story 1 - Key out a luminance range (P1) 🎯 MVP

**Goal**: a black key removes the dark region and leaves the bright patch. **Independent test**: GPU read-back of the black-key fixture.

- [X] CMP-009-T05 [US1] Shaders: append `float4 luma` (low, high, softness, mode 0 none / 1 key / 2 inverted) to `CMPMask`; add `cmp_luma_keep(m, c)` (contract K1, same encode as `cmp_encode`); `cmp_over_masked` multiplies it on the sanitised colour; `cmp_blend` applies coverage × keep when any part is set; `MaskBlock` grows to 416 bytes and is built from optional shape, gradient and key (research D3) in Packages/Compositor/Sources/Compositor/CompositorShaders.swift — Verified 2026-11-14: LayerLumaKeyCompositeTests read-back: black key 0 violations; mutation (keep = 1) fails 8 of 10 GPU tests
- [X] CMP-009-T06 [US1] Compositor: records keep `lumaKey` (init and every apply; a change clears the cached block); a layer with a key takes the masked routes; unkeyed layers unchanged (CMP-009-R7, R11) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: testAKeyChangeAtApplyShowsNextFrameWithoutRecreatingAnything: no re-created layer, pictures or prepare; removal bit-identical; maskedDraws 1 / blendDraws 0
- [X] CMP-009-T07 [US1] GPU acceptance tests (CMP-009-S1, S2): fixture layer with a black region (0, 0, 0, 1), a near-black region, a bright patch and a luminance ramp over a coloured opaque backdrop; black key (0, 0.1, 0): every dark-region pixel equals the backdrop (layer alpha ≤ 1/255) and every bright-patch pixel equals the unkeyed draw within 1/255; with softness the ramp's composite alpha is monotonic and matches the CPU reference within 1/255; at opacity 0.5 the same pixels are keyed (opacity does not move the threshold, R3); invert; key × circle shape × linear gradient equals the product; screen blend; transformed layer; normal mode adds no pass (`maskedDraws` 1, `blendDraws` 0); a change at apply shows next frame without re-creating the layer; a key that keys nothing draws equal to unkeyed within 1/255 in Packages/Compositor/Tests/CompositorTests/LayerLumaKeyCompositeTests.swift — Verified 2026-11-14: LayerLumaKeyCompositeTests: 10 GPU tests pass (dark 6,144 px alpha 0.0, bright 4,608 px Δ 0.0; ramp worst 0.00042)
- [X] CMP-009-T08 [US1] Opt-in GPU bench (`CMP009_BENCH=1`): GPU time of a full-screen keyed layer vs unkeyed at 1920 × 1080, printed, never asserted (CMP-009-S5) in Packages/Compositor/Tests/CompositorTests/LayerLumaKeyCompositeTests.swift — Verified 2026-11-14: CMP009_BENCH=1 (Debug, Mac, load ~365): 0.549 / 0.301 / 0.412 ms median in docs/test-reports/luma-key.md, not device evidence
- [X] CMP-009-T09 [US1] Golden (CMP-009-S3): `luma-key-black` through the real compositor at both QA-002 resolutions, recorded on the host and the "CMP9 iPhone 17" simulator into Packages/RenderGoldens/GeneratorGoldens/LumaKey/{macos,ios-simulator}/, test in Packages/RenderGoldens/Tests/RenderGoldensTests/LumaKeyGoldenTests.swift — Verified 2026-11-14: LumaKeyGoldenTests recorded, then compared identical on the macOS host and the CMP9 iPhone 17 iOS 27.2 simulator; RenderGoldens 85 tests pass
- [X] CMP-009-T10 [US1] Linux shape builds and the reference tests pass: `swift build` and `swift test --filter LayerLumaKeyReferenceTests` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` on Packages/Compositor — Verified 2026-11-14: swift build --build-tests with -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE exit 0; LayerLumaKeyReferenceTests 8 pass

## Phase 4: User Story 3 - Scenes keep the key (P1)

**Goal**: `composite.lumaKey` round-trips. **Independent test**: decode → encode and load → capture byte comparisons.

- [X] CMP-009-T11 [US3] `SceneComposite.lumaKey`, decode per contract L1 (clamp with `valueClamped`, swap reversed range with `valueClamped`, drop unknown keys with `droppedField`, defaults for missing fields), encode only when set with every field, live state and capture in Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneLiveState}.swift — Verified 2026-11-14: SceneLumaKeyTests 3 tests; SceneFormat 178 tests, 0 failures
- [X] CMP-009-T12 [P] [US3] Round-trip tests: byte-identical decode → encode with a key; load → capture keeps it; key with mask and gradient; clamping, swap and unknown-key warnings; a scene without a key encodes as before in Packages/SceneFormat/Tests/SceneFormatTests/SceneLumaKeyTests.swift — Verified 2026-11-14: SceneLumaKeyTests: byte-identical round trips, load → capture, clamping, swap, unknown keys, no field without a key
- [X] CMP-009-T13 [US3] ADR-0028 note for `composite.lumaKey` in docs/adr/0028-scene-document-format.md — Verified 2026-11-14: ADR-0028 bullet added; validate_docs OK

## Phase 5: User Story 2 - Edit the key in the inspector (P1)

**Goal**: toggle, three sliders, invert, undo. **Independent test**: UI test toggle → drag → undo.

- [X] CMP-009-T14 [US2] Rules: `LayerLumaKeyEdit` (on gives `blackKey`, off removes; Low above High moves High; High below Low moves Low; softness clamp) in Apps/projectM-iOS/Coordinators/LayerLumaKeyEdit.swift; parameters `lumaKey`, `lumaLow`, `lumaHigh`, `lumaSoftness`, `lumaInverted` with help, ranges, steps, values, texts and settings in Apps/projectM-iOS/Coordinators/LayerInspectorModel.swift; mapping passes the key; history `changedParameters` names the luma parameter in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift — Verified 2026-11-14: LayerLumaKeyEditTests 5 tests on the iOS 27.2 simulator; inspector, gradient and history suites pass (29 tests)
- [X] CMP-009-T15 [US2] View: `LayerLumaKeySection` (toggle, ACC-005 sliders through `LayerParameterSlider`, invert toggle; read-only read-outs) in Apps/projectM-iOS/Views/LayerLumaKeySection.swift and one line in Apps/projectM-iOS/Views/LayerDetailView.swift — Verified 2026-11-14: testLumaKeyToggleDragAndUndo reaches the toggle and sliders by identifier; test build has no type-check warning in touched files
- [X] CMP-009-T16 [P] [US2] Unit tests of the edit rules, history labels and keys in Apps/projectM-iOS/Tests/LayerLumaKeyEditTests.swift — Verified 2026-11-14: LayerLumaKeyEditTests: 5 tests, 0 failures
- [X] CMP-009-T17 [US2] UI test (CMP-009-S6, under 30 s): turn the key on, drag Low, undo in Apps/projectM-iOS/UITests/LayerInspectorUITests.swift — Verified 2026-11-14: testLumaKeyToggleDragAndUndo passed (40.7 s under load average ~365; over the 30 s budget only from the shared load, see report)

## Phase 6: Polish

- [X] CMP-009-T18 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), type-check budget, test report docs/test-reports/luma-key.md, spec status — Verified 2026-11-14: repo checks OK, test_scripts 164 OK, privacy manifest and network symbols OK; docs/test-reports/luma-key.md
- [ ] CMP-009-T19 {device} GPU time of a full-screen keyed layer on D1 (CMP-009-S5)

## Analysis fixes (speckit-analyze 2026-11-14)

- U1 (MEDIUM): US2 scenario 2 said "never empty-inverted"; now "low ≤ high always holds".
- C1 (MEDIUM): R3/R6 "independent of opacity" had no test; T07 adds an opacity 0.5 case.
- Coverage: R1-R11 and S1-S6 each map to at least one task (R1-R5 T02-T07, R6-R7 T05-T07, R8-R9 T11-T12, R10 T14-T17, R11 T06-T07; S5 T08/T19); no constitution conflicts.

## Dependencies

T01 → T02-T04 → US1 (T05-T10) → US3 (T11-T13) → US2 (T14-T17) → T18. US2 depends on US3's
`SceneComposite.lumaKey`. T19 needs a device.

## Parallel opportunities

T04 beside T03; T12 beside T13; T16 beside T15.

## Implementation strategy

MVP is US1 (the row's acceptance). Then persistence, then the editor.
