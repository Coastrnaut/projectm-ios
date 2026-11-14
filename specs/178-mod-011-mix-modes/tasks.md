# Tasks: MOD-011 Modulation Mix Modes

**Input**: `specs/178-mod-011-mix-modes/` (spec, plan, research, data-model, contracts/mix-order.md)

Tests are requested by the spec (acceptance table, bit identity, determinism, scene round trip, app test,
Linux shape). Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min.

## Phase 1: Foundational (order)

- [X] MOD-011-T01 Add `ModulationMixOrder` (one step: mix, non-finite → running, clamp; integer finish) in
  `Packages/ParameterGraph/Sources/ParameterGraph/ModulationMixOrder.swift` with the contract O1 comment block — Verified 2026-11-14: `swift test --package-path Packages/ParameterGraph` ParameterGraphTests 137 + 45 tests, 0 failures, 0.45 s; ModulationMixOrderTests 6 pass
- [X] MOD-011-T02 Layers in `AudioFeatureModulator` (`maximumBindingsPerTarget`, `addLayer`, `bindings(for:)`,
  `layerCount(for:)`, `setEnvelope(_:for:layer:)`, `bind` replaces all layers, `unbind` removes all, fold in
  `value(for:manual:)`) and `AudioFeatureBindingError.tooManyLayers` in `AudioFeatureBinding.swift` — Verified 2026-11-14: `swift test --package-path Packages/ParameterGraph` ParameterGraphTests 137 + 45 tests, 0 failures, 0.45 s; ModulationMixOrderTests 6 pass (existing MOD-002 to MOD-014 tests unchanged)

## Phase 2: User Stories 1 and 2 — documented order, single bindings unchanged (P1)

- [X] MOD-011-T03 [US1] Acceptance table in
  `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMixOrderTests.swift`: manual + audio replace +
  LFO add + audio multiply in two list orders, intermediate clamps at both bounds, integer rounding once at
  the end, exact values (1e-12); limits and `bind`/`unbind` layer semantics — Verified 2026-11-14: `testDocumentedOrderTable` (9 rows), `testIntegerRoundsOnceAtTheEnd`, `testPureFoldMatchesTheContract`, `testLayerLimitsBindAndUnbind` pass
- [X] MOD-011-T04 [US2] Bit-identity grid (≥ 500 cases: modes × manual × signals × curves × ranges, continuous
  and integer) against the MOD-002 formula, and determinism (two fresh modulators, same frames → same bits),
  in the same file — Verified 2026-11-14: `testSingleBindingIsBitIdenticalToMOD002` (540 continuous bit patterns + 60 integer cases), `testDeterminism` (120 frames, 3 layers with an envelope) pass
- [X] MOD-011-T05 [US1] `GlowModulationOrder.resolve(base:modulator:clamp:)` in
  `Packages/VisualGenerators/Sources/VisualParameters/GlowModulationOrder.swift` (+ FlashSafety dependency) and
  `Packages/VisualGenerators/Tests/VisualGeneratorsTests/GlowModulationOrderTests.swift`: two layers on the glow
  intensity at Standard (exact) and Strict (ACC-012 scaling then cap applied last) — Verified 2026-11-14: GlowModulationOrderTests 3 pass; `swift test --package-path Packages/VisualGenerators` 160 tests, 0 failures, 40 s

## Phase 3: User Story 3 — scenes and app (P2)

- [X] MOD-011-T06 [US3] SceneFormat: restore layers (≤ 4, `addLayer`), fifth and later-layer expression →
  `duplicateBindingTarget`; `SceneBinding.list(_:expressions:)` used by `SceneLiveState`; update
  `SceneValidationTests` and `SceneModulationRestoreTests`; add a layered round-trip test — Verified 2026-11-14: `swift test --package-path Packages/SceneFormat` 160 tests, 0 failures, 3.7 s (SceneLayeredBindingTests 2 new; SceneValidationTests, SceneModulationRestoreTests migration case and SceneRepairTests fixture updated: a same-target binding is now a layer; binding edges deduplicated for the graph check)
- [X] MOD-011-T07 [US3] App: `NativeSpectrumHost` uses `GlowModulationOrder` and gains `addLayer`; scene
  restore adds layers in order (`AppCoordinator`); `SceneAutosaveCapture` uses `SceneBinding.list` — Verified 2026-11-14: build-for-testing on "MOD11 iPhone 17" (iOS 27.2) succeeded, no new type-check warnings; 54 app tests touching bindings (AudioFeatureBinding, Envelope, LFO, MIDI, shelf, scene autosave and repair, sensory safety) pass in 4 s
- [X] MOD-011-T08 [US3] Inspector: numbered layers and the order line in `ParameterInspectorModel.swift` — Verified 2026-11-14: ModulationMixOrderAppTests.testInspectorNumbersTheLayers; ParameterInspectorTests 14 pass unchanged
- [X] MOD-011-T09 [US3] App test `Apps/projectM-iOS/Tests/ModulationMixOrderAppTests.swift`: two bindings on the
  glow intensity combine as documented in a real `NativeSpectrumHost`; inspector reading numbered — Verified 2026-11-14: ModulationMixOrderAppTests 3 tests pass in 1.5 s on "MOD11 iPhone 17" (iOS 27.2 simulator; two and three layers, both orders, Standard/Reduced/Strict ACC-012 last)

## Phase 4: Polish

- [X] MOD-011-T10 ADR (order contract) in `docs/adr/`, scene contract note (SCN-001 `duplicateBindingTarget`
  message), spec status; repository checks; Linux shape (no Apple-only API in the changed package code) — Verified 2026-11-14: ADR-0057 written and indexed; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK (1 skipped); check_privacy_manifest and check_network_symbols OK on the Debug app; new package code imports only ParameterGraph, FlashSafety and VisualEffects (no Foundation, no stdio), and VisualParameters' new FlashSafety dependency is a package already built on Linux — Linux CI run itself pending

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1, R2 → T02, T03; R3, R4 → T01, T03, T04; R5, R6 → T05, T09; R7 → T06, T07; R8 → T08, T09;
R9 → T01, T10; S1 → T03; S2, S3 → T04; S4 → T05, T09; S5 → T06; S6 → T10. Fixed: the two new
`duplicateBindingTarget` messages were unspecified (added to contract O3); T10 also updates the SCN-001
scene-document contract table.
