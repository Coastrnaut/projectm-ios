# Tasks: MOD-011 Modulation Mix Modes

**Input**: `specs/178-mod-011-mix-modes/` (spec, plan, research, data-model, contracts/mix-order.md)

Tests are requested by the spec (acceptance table, bit identity, determinism, scene round trip, app test,
Linux shape). Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min.

## Phase 1: Foundational (order)

- [ ] MOD-011-T01 Add `ModulationMixOrder` (one step: mix, non-finite → running, clamp; integer finish) in
  `Packages/ParameterGraph/Sources/ParameterGraph/ModulationMixOrder.swift` with the contract O1 comment block
- [ ] MOD-011-T02 Layers in `AudioFeatureModulator` (`maximumBindingsPerTarget`, `addLayer`, `bindings(for:)`,
  `layerCount(for:)`, `setEnvelope(_:for:layer:)`, `bind` replaces all layers, `unbind` removes all, fold in
  `value(for:manual:)`) and `AudioFeatureBindingError.tooManyLayers` in `AudioFeatureBinding.swift`

## Phase 2: User Stories 1 and 2 — documented order, single bindings unchanged (P1)

- [ ] MOD-011-T03 [US1] Acceptance table in
  `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMixOrderTests.swift`: manual + audio replace +
  LFO add + audio multiply in two list orders, intermediate clamps at both bounds, integer rounding once at
  the end, exact values (1e-12); limits and `bind`/`unbind` layer semantics
- [ ] MOD-011-T04 [US2] Bit-identity grid (≥ 500 cases: modes × manual × signals × curves × ranges, continuous
  and integer) against the MOD-002 formula, and determinism (two fresh modulators, same frames → same bits),
  in the same file
- [ ] MOD-011-T05 [US1] `GlowModulationOrder.resolve(base:modulator:clamp:)` in
  `Packages/VisualGenerators/Sources/VisualParameters/GlowModulationOrder.swift` (+ FlashSafety dependency) and
  `Packages/VisualGenerators/Tests/VisualGeneratorsTests/GlowModulationOrderTests.swift`: two layers on the glow
  intensity at Standard (exact) and Strict (ACC-012 scaling then cap applied last)

## Phase 3: User Story 3 — scenes and app (P2)

- [ ] MOD-011-T06 [US3] SceneFormat: restore layers (≤ 4, `addLayer`), fifth and later-layer expression →
  `duplicateBindingTarget`; `SceneBinding.list(_:expressions:)` used by `SceneLiveState`; update
  `SceneValidationTests` and `SceneModulationRestoreTests`; add a layered round-trip test
- [ ] MOD-011-T07 [US3] App: `NativeSpectrumHost` uses `GlowModulationOrder` and gains `addLayer`; scene
  restore adds layers in order (`AppCoordinator`); `SceneAutosaveCapture` uses `SceneBinding.list`
- [ ] MOD-011-T08 [US3] Inspector: numbered layers and the order line in `ParameterInspectorModel.swift`
- [ ] MOD-011-T09 [US3] App test `Apps/projectM-iOS/Tests/ModulationMixOrderAppTests.swift`: two bindings on the
  glow intensity combine as documented in a real `NativeSpectrumHost`; inspector reading numbered

## Phase 4: Polish

- [ ] MOD-011-T10 ADR (order contract) in `docs/adr/`, scene contract note (SCN-001 `duplicateBindingTarget`
  message), spec status; repository checks; Linux shape (no Apple-only API in the changed package code)

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1, R2 → T02, T03; R3, R4 → T01, T03, T04; R5, R6 → T05, T09; R7 → T06, T07; R8 → T08, T09;
R9 → T01, T10; S1 → T03; S2, S3 → T04; S4 → T05, T09; S5 → T06; S6 → T10. Fixed: the two new
`duplicateBindingTarget` messages were unspecified (added to contract O3); T10 also updates the SCN-001
scene-document contract table.
