# Tasks: CMP-010 Color Key

**Input**: Design documents from `specs/230-cmp-010-color-key/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/color-key.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute,
UI test under 30 s.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] CMP-010-T01 Baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; create the simulator "CMP10 iPhone 17" (iOS 27.2); record counts and the PosterBoard report count in docs/test-reports/color-key.md — Verified 2026-11-14: swift test Compositor 569 CompositorTests (9 skipped), SceneFormat 178, 0 failures before any change; simulator "CMP10 iPhone 17" created; 26 PosterBoard reports

## Phase 2: Foundational (blocks every story)

- [X] CMP-010-T02 Add `LayerColorKey` ("red, green, blue: the key colour as displayed sRGB, each 0…1 (non-finite reads green's default 0, 1, 0)", "tolerance 0…1 (non-finite reads 0.2)", "feather 0…0.5 (non-finite reads 0.1)", −0 stored as 0), `greenKey` (0, 1, 0, 0.2, 0.1), `chroma(red:green:blue:alpha:)` (contract C1 steps 1-3), `keyChroma`, `distance(red:green:blue:alpha:)` (C1 step 5), `keep(distance:)` (C1 steps 6-7) and `keep(red:green:blue:alpha:)` in typed `Double` steps outside any Metal guard (CMP-010-R1, R2, R3, R5) in Packages/Compositor/Sources/Compositor/LayerColorKey.swift — Verified 2026-11-14: LayerColorKeyReferenceTests (5 tests) pass on the Mac host and in the Linux shape
- [X] CMP-010-T03 Add `colorKey: LayerColorKey?` (default nil, additive init parameter) to `LayerCompositeSettings` in Packages/Compositor/Sources/Compositor/LayerContract.swift — Verified 2026-11-14: LayerCompositeSettings.colorKey used by LayerColorKeyCompositeTests and ColorKeyGoldenTests; Compositor suite 584 tests (10 skipped), 0 failures
- [X] CMP-010-T04 [P] CPU reference tests: chroma of white/black/grey is (0, 0); pure primaries' Cb/Cr; premultiplied input (half alpha gives the same chroma as opaque); alpha 0 reads (0, 0); keep 0 within tolerance, 1 beyond tolerance + feather; ramp monotonic (dense sweep, 0 violations); feather 0 hard cut; fixture colours (red, blue, white, skin, dark green) keep 1 under `greenKey`; clamping and non-finite defaults in Packages/Compositor/Tests/CompositorTests/LayerColorKeyReferenceTests.swift — Verified 2026-11-14: swift test --filter LayerColorKeyReferenceTests: 5 tests, 0.003 s, host and Linux shape (-DCOMPOSITOR_NO_METAL)

## Phase 3: User Story 1 - Key out a colour (P1) 🎯 MVP

**Goal**: a green key removes the green patch and leaves unrelated colours. **Independent test**: GPU read-back of the green-key fixture.

- [X] CMP-010-T05 [US1] Shaders: append `float4 chroma` (key Cb, key Cr, tolerance, 1 + feather; w 0 = none) to `CMPMask`; add `cmp_color_keep(m, c)` (contract C1, reusing `cmp_key_encode`); `cmp_over_masked` multiplies it with the luma keep; `cmp_blend` applies it when set; `MaskBlock` grows to 432 bytes and is built from optional shape, gradient, luma key and colour key (research D3) in Packages/Compositor/Sources/Compositor/CompositorShaders.swift — Verified 2026-11-14: LayerColorKeyCompositeTests read-back: green key 0 violations; mutation (keep = 1) fails 8 of 9 GPU tests
- [X] CMP-010-T06 [US1] Compositor: records keep `colorKey` (init and every apply; a change clears the cached block); a layer with a colour key takes the masked routes; unkeyed layers unchanged (CMP-010-R7, R11) in Packages/Compositor/Sources/Compositor/Compositor.swift — Verified 2026-11-14: testAKeyChangeAtApplyShowsNextFrameWithoutRecreatingAnything: no re-created layer, pictures or prepare; a colour change alone shows next frame; removal bit-identical; maskedDraws 1 / blendDraws 0
- [X] CMP-010-T07 [US1] GPU acceptance tests (CMP-010-S1, S2): fixture layer with a green patch (sRGB 0, 1, 0), red, blue, white, skin (0.87, 0.67, 0.55) and dark green (0, 0.3, 0) patches and a green→grey ramp over a coloured opaque backdrop; `greenKey`: every green-patch pixel equals the backdrop (layer alpha ≤ 1/255) and every other patch pixel equals the unkeyed draw within 1/255; with feather the ramp's composite alpha is monotonic and matches the CPU reference within 1/255; opacity 0.5 keys the same pixels; colour key × luma key × circle shape × linear gradient equals the product; screen blend; transformed layer; normal mode adds no pass (`maskedDraws` 1, `blendDraws` 0); a change at apply shows next frame without re-creating the layer; a key that keys nothing draws equal to unkeyed within 1/255 in Packages/Compositor/Tests/CompositorTests/LayerColorKeyCompositeTests.swift — Verified 2026-11-14: LayerColorKeyCompositeTests: 9 GPU tests pass (green 3,072 px worst alpha 0.0; red/blue/white/skin/dark green 7,680 px worst Δ 0.0; ramp worst 0.00047)
- [ ] CMP-010-T08 [US1] Opt-in GPU bench (`CMP010_BENCH=1`): GPU time of a full-screen colour-keyed layer vs unkeyed at 1920 × 1080, printed, never asserted (CMP-010-S5) in Packages/Compositor/Tests/CompositorTests/LayerColorKeyCompositeTests.swift
- [X] CMP-010-T09 [US1] Golden (CMP-010-S3): `color-key-green` through the real compositor at both QA-002 resolutions, recorded on the host and the "CMP10 iPhone 17" simulator into Packages/RenderGoldens/GeneratorGoldens/ColorKey/{macos,ios-simulator}/, test in Packages/RenderGoldens/Tests/RenderGoldensTests/ColorKeyGoldenTests.swift — Verified 2026-11-14: ColorKeyGoldenTests recorded, then compared identical (0 pixels changed) on the macOS host and the CMP10 iPhone 17 iOS 27.2 simulator; same pixel hashes; RenderGoldens 87 tests pass
- [X] CMP-010-T10 [US1] Linux shape builds and the reference tests pass: `swift build --build-tests` and `swift test --filter LayerColorKeyReferenceTests` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` on Packages/Compositor; mutation check (keep forced to 1 in the shader) fails the GPU acceptance tests — Verified 2026-11-14: swift test with -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE builds all targets and LayerColorKeyReferenceTests 5 pass; mutation check: 8 of 9 GPU tests fail with the shader keep forced to 1, restored

## Phase 4: User Story 3 - Scenes keep the key (P1)

**Goal**: `composite.colorKey` round-trips. **Independent test**: decode → encode and load → capture byte comparisons.

- [X] CMP-010-T11 [US3] `SceneComposite.colorKey`, decode per contract C3 (clamp with `valueClamped`, drop unknown keys with `droppedField`, `greenKey` defaults for missing fields), encode only when set with every field, live state and capture in Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneLiveState}.swift — Verified 2026-11-14: SceneColorKeyTests 3 tests; SceneFormat 181 tests, 0 failures (QA-004 meta-test included)
- [X] CMP-010-T12 [P] [US3] Round-trip tests: byte-identical decode → encode with a key; load → capture keeps it; key with luma key and mask; clamping and unknown-key warnings; a scene without a key encodes as before in Packages/SceneFormat/Tests/SceneFormatTests/SceneColorKeyTests.swift — Verified 2026-11-14: SceneColorKeyTests: byte-identical round trips (alone and with luma key and circle), load → capture, clamping, unknown keys, defaults, malformed refused, no field without a key
- [X] CMP-010-T13 [US3] ADR-0028 note for `composite.colorKey` in docs/adr/0028-scene-document-format.md — Verified 2026-11-14: ADR-0028 bullet added; validate_docs OK

## Phase 5: User Story 2 - Edit the key in the inspector (P1)

**Goal**: toggle, colour picker, two sliders, undo. **Independent test**: UI test toggle → picker present → drag → undo.

- [ ] CMP-010-T14 [US2] Rules: `LayerColorKeyEdit` (on gives `greenKey` or keeps the current key, off removes; colour setting clamps and rounds to 1/1000; tolerance and feather clamp; `#RRGGBB` text) in Apps/projectM-iOS/Coordinators/LayerColorKeyEdit.swift; parameters `colorKey`, `colorKeyColor`, `colorTolerance`, `colorFeather` with help, ranges, steps, values, texts and settings in Apps/projectM-iOS/Coordinators/LayerInspectorModel.swift; mapping passes the key; `setColorKeyColor` in Apps/projectM-iOS/Coordinators/LayerInspectorCoordinator.swift; history `changedParameters` names the colour-key parameter, the colour change keyed `layer.<kind>.colorKeyColor` in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift
- [ ] CMP-010-T15 [US2] View: `LayerColorKeySection` (toggle, `ColorPicker` "Key Color" without opacity, ACC-005 sliders through `LayerParameterSlider`; read-only read-outs) in Apps/projectM-iOS/Views/LayerColorKeySection.swift and one line in Apps/projectM-iOS/Views/LayerDetailView.swift
- [ ] CMP-010-T16 [P] [US2] Unit tests of the edit rules (on/off, a colour with alpha 0.3 is stored opaque, an extended-sRGB component above 1 or below 0 is clamped, rounding to 1/1000), history labels and keys in Apps/projectM-iOS/Tests/LayerColorKeyEditTests.swift
- [ ] CMP-010-T17 [US2] UI test (CMP-010-S6, under 30 s): turn the key on, find the "Key Color" picker, drag Tolerance, undo in Apps/projectM-iOS/UITests/LayerInspectorUITests.swift

## Phase 6: Polish

- [ ] CMP-010-T18 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the built app, type-check budget, test report docs/test-reports/color-key.md, spec status
- [ ] CMP-010-T19 {device} GPU time of a full-screen colour-keyed layer on D1 (CMP-010-S5)

## Analysis fixes (speckit-analyze 2026-11-14)

- C1 (MEDIUM): US2 scenario 2 (opacity of the picked colour ignored) and research D4 (wide-gamut picks clamped) had no test; T16 now covers both.
- I1 (LOW): CMP-010-R6 "every blend mode" is covered by one non-normal mode (screen) through the shared `cmp_blend` path, as in CMP-009; accepted.
- Coverage: R1-R11 and S1-S6 each map to at least one task (R1-R5 T02-T07, R6-R7 T05-T07, R8-R9 T11-T12, R10 T14-T17, R11 T06-T07; S5 T08/T19); no constitution conflicts; 0 critical issues.

## Dependencies

T01 → T02-T04 → US1 (T05-T10) → US3 (T11-T13) → US2 (T14-T17) → T18. US2 depends on US3's
`SceneComposite.colorKey`. T19 needs a device.

## Parallel opportunities

T04 beside T03; T12 beside T13; T16 beside T15.

## Implementation strategy

MVP is US1 (the row's acceptance). Then persistence, then the editor.
