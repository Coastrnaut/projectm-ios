# Tasks: MOD-012 Modulation Matrix UI

**Input**: `specs/189-mod-012-modulation-matrix/` (spec, plan, research, data-model, contracts/modulation-matrix.md)

Tests are requested by the spec (acceptance, reorder, round trip, undo, UI). Budgets (owner rule 7): unit test
≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (evaluation and storage)

- [X] MOD-012-T01 `AudioFeatureBinding.isEnabled`; fold skips disabled layers, none enabled → base exactly;
  `setEnabled(_:for:layer:)`, `moveLayer(of:from:to:)`, `replaceBindings(_:)` in `AudioFeatureModulator`;
  `ModulationRouteList` (pure edits and grouping) in ParameterGraph — Verified 2026-11-14: `swift test --package-path Packages/ParameterGraph` 145 + 46 tests, 0 failures, 0.14 s (existing MOD-002 to MOD-014 tests unchanged)
- [X] MOD-012-T02 [US1] Acceptance in `Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMatrixTests.swift`:
  A/B/C, disable B (intensity == A-only exactly, radius and A's signal bit-identical), re-enable (two-layer fold),
  all off → base, signal keeps advancing; [US3] reorder changes the fold as documented, cross/out-of-range refused;
  list edits match the modulator; grouping order — Verified 2026-11-14: ModulationMatrixTests 6 pass in 0.003 s (`testDisablingOneRowAffectsOnlyItsDestinationRoute` asserts bit patterns of intensity vs an A-only modulator, radius and A's signal)
- [X] MOD-012-T03 [US5] SceneFormat `enabled` field (encode only when false, decode optional boolean, malformed
  otherwise) and `SceneBindingEnabledTests` (round trip, absent → enabled, restore keeps a disabled layer) — Verified 2026-11-14: `swift test --package-path Packages/SceneFormat` 167 tests, 0 failures, 2.5 s (SceneBindingEnabledTests 2 new; capture byte-identical, malformed path `$.bindings[0].enabled`)

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

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1, R2 → T06; R3, R4 → T01, T02; R5 → T03; R6 → T01, T02, T06; R7 → T06; R8 → T05, T07; R9 → T01;
R10 → T06; S1 → T02; S2 → T02; S3 → T03; S4 → T07; S5 → T08; S6 → T09. Fixed: the inspector's "(off)" marking
had no requirement (added to MOD-012-R7); the undo restore restarting replaced layers' signals is stated in the
spec's Edge Cases and contract M2, so T07 asserts the list, not the signals.
