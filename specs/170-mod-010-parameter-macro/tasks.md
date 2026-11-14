# Tasks: MOD-010 Parameter Macro

**Input**: `specs/170-mod-010-parameter-macro/` (spec, plan, research, data-model, contracts/parameter-macro.md)

Tests are requested by the spec (acceptance, invert, clamp, unknown target, round trip, undo, UI test,
Linux shape). Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

No setup: existing packages and app target.

## Phase 2: Foundational (model)

- [X] MOD-010-T01 Add `MacroTarget`, `ParameterMacro`, `MacroProblem`, `MacroAssignment`, `MacroSkip`,
  `MacroEvaluation` in `Packages/ParameterGraph/Sources/ParameterGraph/ParameterMacro.swift` per contract M1,
  M2 ("first 8 used", "minimum ≤ maximum", boolean and color refused, duplicates skipped; pure, no Foundation) — Verified 2026-11-14: ParameterMacroTests (7) pass on the host; ParameterGraph suite 131 + 45 tests pass in 2 s

## Phase 3: User Story 1 — one control moves several parameters (P1)

**Independent test**: three-target macro at 0, 0.25, 0.5, 1 equals each target's curve and range.

- [X] MOD-010-T02 [US1] Acceptance and rule tests in
  `Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterMacroTests.swift`: three targets (continuous
  easeIn, continuous log inverted, enum) at 0, 0.25, 0.5, 1 (1e-9; exact ends); invert; clamp to the registry
  range; integer step rounding; unknown, unsupported, invalid curve/range, duplicate and beyond-limit skips
  with the other targets applied; non-finite macro value reads 0 — Verified 2026-11-14: `swift test --filter ParameterMacroTests` 7 tests, 0 failures, 0.002 s

## Phase 4: User Story 2 — saved with the scene, one undo step (P1)

**Independent test**: scene round trip keeps macros; issues reported; one undo step.

- [X] MOD-010-T03 [US2] `Packages/SceneFormat/Sources/SceneFormat/SceneMacros.swift` (entry, `read(_:registry:)`,
  `settingValue`, limits 8 / 64) and edits to `SceneDocument`, `SceneDecoding`, `SceneEncoding`, `SceneIssue`
  (`invalidMacro`, `unknownMacroTarget`), `SceneRepair`, `SceneValidation`, `SceneLiveState`; add the file to
  `SceneSourceSafetyTests` — Verified 2026-11-14: SceneFormat suite 158 tests, 0 failures, 2.5 s (source safety included)
- [X] MOD-010-T04 [US2] `Packages/SceneFormat/Tests/SceneFormatTests/SceneMacroTests.swift`: the acceptance
  macro on the real visual catalog round-trips verbatim and gives identical values at 0, 0.25, 0.5, 1; a scene
  without macros encodes unchanged; issues at their paths with the entry kept — Verified 2026-11-14: SceneMacroTests 5 tests pass on the host (real visual catalog)
- [X] MOD-010-T05 [US2] App: `Apps/projectM-iOS/Coordinators/MacroCoordinator.swift` (entries, live macros,
  `setValue(_:at:)` through `ParameterInspectorTargets`, skip report, `restore`); `SceneInputs.macros`,
  carry, restored values in `SceneAutosaveCapture.swift`; history label/key in `SceneHistoryCoordinator.swift`;
  wiring in `AppCoordinator.swift` (property, `sceneInputs`, launch restore, reopen) and
  `AppCoordinator+SceneHistory.swift` (`applySceneInputs`) — Verified 2026-11-14: app build-for-testing on the MOD10 simulator (iOS 27.2), no type-check warnings in touched files; T06 tests below
- [X] MOD-010-T06 [US2] `Apps/projectM-iOS/Tests/ParameterMacroAppTests.swift`: settings follow the acceptance
  macro at 0, 0.25, 0.5, 1; a target without an app control is skipped and reported; capture → restore round
  trip; one undo step restores macro and targets — Verified 2026-11-14: ParameterMacroAppTests 4/4 pass, with SceneHistoryCoordinatorTests, SceneAutosaveCaptureTests, SceneAutosaveMigrationMatrixTests (14 tests, 0.11 s)

## Phase 5: User Story 3 — macro control in the app (P2)

- [X] MOD-010-T07 [US3] `Apps/projectM-iOS/Views/MacrosSection.swift` (slider `macro.<index>` with
  `.accessibleParameter`, read-only rows `macroTarget.<index>.<id>`), one line in `Views/SettingsView.swift`
  `mediaSections`, `.id("macros")`; DEBUG seed `Apps/projectM-iOS/Debug/UITestMacroFixture.swift`
  (`-uitestSeedMacro`) — Verified 2026-11-14: rendered in Settings (accessibility tree: slider `macro.0`, three target rows) and driven by T08
- [X] MOD-010-T08 [US3] `Apps/projectM-iOS/UITests/ParameterMacroUITests.swift`: move the slider, target labels
  change (< 30 s) — Verified 2026-11-14: ParameterMacroUITests passed twice, 22.2 s and 18.3 s

## Phase 6: Polish

- [X] MOD-010-T09 Scene-document contract `macros` section
  (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`); repository checks
  (compliance, docs, motion, permissions, status events, script tests, privacy manifest, network symbols);
  type-check budget; Linux shape (`ParameterMacro.swift` and `SceneMacros.swift` import no Foundation
  or Apple-only API; MOD-010-R11); spec status — Verified 2026-11-14: contract section added; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 tests OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; no type-check warnings in touched files; SceneSourceSafetyTests pass (no Foundation in SceneMacros.swift); neighbouring app suites 34 tests pass

## Dependencies

T01 → T02; T01 → T03 → T04; T03 → T05 → T06; T05 → T07 → T08; all → T09.
Parallel: T02 with T03; T04 with T05.

## Implementation strategy

MVP = T01-T02 (the model meets the acceptance), then persistence and app.
