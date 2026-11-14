# Tasks: MOD-012 Modulation Matrix UI

**Input**: `specs/189-mod-012-modulation-matrix/` (spec, plan, research, data-model, contracts/modulation-matrix.md)

Tests are requested by the spec (acceptance, reorder, round trip, undo, UI). Budgets (owner rule 7): unit test
≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (evaluation and storage)

- [ ] MOD-012-T01 `AudioFeatureBinding.isEnabled`; fold skips disabled layers, none enabled → base exactly;
  `setEnabled(_:for:layer:)`, `moveLayer(of:from:to:)`, `replaceBindings(_:)` in `AudioFeatureModulator`;
  `ModulationRouteList` (pure edits and grouping) in ParameterGraph
- [ ] MOD-012-T02 [US1] Acceptance in `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMatrixTests.swift`:
  A/B/C, disable B (intensity == A-only exactly, radius and A's signal bit-identical), re-enable (two-layer fold),
  all off → base, signal keeps advancing; [US3] reorder changes the fold as documented, cross/out-of-range refused;
  list edits match the modulator; grouping order
- [ ] MOD-012-T03 [US5] SceneFormat `enabled` field (encode only when false, decode optional boolean, malformed
  otherwise) and `SceneBindingEnabledTests` (round trip, absent → enabled, restore keeps a disabled layer)

## Phase 2: App (User Stories 1-5)

- [ ] MOD-012-T04 `ModulationMatrixCoordinator`, `AppCoordinator+ModulationMatrix` (live list, in-place host
  edits, carried list, refresh points), `NativeSpectrumHost` edits, `SceneAutosaveCoordinator.replaceCarriedBindings`
- [ ] MOD-012-T05 [US5] `SceneInputs.bindings` (capture prefers it), history labels, undo/redo restore
- [ ] MOD-012-T06 [US2, US3, US4] Views: `ModulationMatrixView` (groups, switches, Edit mode drag, VoiceOver
  Move Up/Down, read-only triggers and macros, empty state), `ModulationRouteDetailView` (curve preview, envelope,
  10 Hz live values, Inspect), Settings row; inspector marks "(off)"
- [ ] MOD-012-T07 App tests `Apps/projectM-iOS/Tests/ModulationMatrixAppTests.swift`: host acceptance (glow
  intensity follows A only, radius binding untouched), coordinator edits are one undo step each and undo restores,
  capture writes `enabled: false`
- [ ] MOD-012-T08 [US1] DEBUG seed and probe, `ModulationMatrixUITests` (< 30 s): toggle one row, the probe
  changes for that destination only

## Phase 3: Polish

- [ ] MOD-012-T09 Spec status, repository checks, type-check budget, privacy manifest and network symbols on the
  Debug app, Linux shape of the changed packages
