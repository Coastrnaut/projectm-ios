# Tasks: CMP-015 Layer Inspector

**Input**: Design documents from `specs/118-cmp-015-layer-inspector/` (spec, plan, research, data-model,
contracts/layer-inspector.md, quickstart). Tests are requested by the roadmap row (unit tests,
snapshots, GPU performance) and the brief. Budgets (owner rule 7): unit tests about 1-2 s (at most 10 s),
UI tests under 30 s each.

## Phase 1: Setup

- [ ] CMP-015-T01 Create a private simulator, run `xcodegen generate`, initialise preset submodules, count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` (baseline) — see quickstart.md

## Phase 2: Foundational (blocks all stories)

- [ ] CMP-015-T02 Add `layerComposites: [String: SceneComposite]?` to `SceneInputs`; capture writes the kind's composite (default when the key is missing) for app layers when non-nil and keeps the carried composite when nil; `SceneRestoredValues.layerComposites` reads the document's drawn-layer composites ("Values equal to `SceneComposite()` are never stored") in `Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift`
- [ ] CMP-015-T03 [P] Model: `LayerInspectorParameter`, `LayerInspectorHelp.entries` (one table), `LayerInspectorRow`, `LayerInspectorScene.rows(document:visual:inputs:)`, composite edit helpers and `SceneComposite → LayerCompositeSettings` mapping in `Apps/projectM-iOS/Coordinators/LayerInspectorModel.swift`
- [ ] CMP-015-T04 [P] `LayerInspectorCoordinator` (composites, transient solo/mute, selection, callbacks) in `Apps/projectM-iOS/Coordinators/LayerInspectorCoordinator.swift`
- [ ] CMP-015-T05 [P] `Compositor.applyLayerComposites(_:)` and `applySoloMute(soloed:muted:)` in `Apps/projectM-iOS/Visuals/Compositor+LayerComposites.swift`
- [ ] CMP-015-T06 Wiring: `sceneInputs` passes the composites; restore and Reopen apply them; hosts apply them when made and on change; history apply restores them; visual change clears solo/mute (`AppCoordinator.swift`, `AppCoordinator+SceneHistory.swift`, new `AppCoordinator+LayerInspector.swift`)
- [ ] CMP-015-T07 History labels and coalescing keys `layer.<kind>.<parameter>` in `Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift`

## Phase 3: User Story 1 - Inspect the layers (P1) 🎯 MVP

Independent test: seeded three-layer scene; each selection shows that layer's values.

- [ ] CMP-015-T08 [US1] DEBUG seed `-uitestLayerInspectorSeed` (contract L5) in `Apps/projectM-iOS/Debug/UITestLayerInspectorFixture.swift` and a DEBUG carry seed in `SceneAutosaveCoordinator.swift`
- [ ] CMP-015-T09 [US1] `LayerInspectorView` (rows top first, contract L1) and `LayerDetailView` read-outs in `Apps/projectM-iOS/Views/`; Settings "Layers" row (`SettingsView.swift`, `VisualizerView.swift`)
- [ ] CMP-015-T10 [P] [US1] Unit tests: rows for a three-layer document (order, positions, values, editability, read-only reasons, own MOD-001 values) in `Apps/projectM-iOS/Tests/LayerInspectorTests.swift`

## Phase 4: User Story 2 - Edit with undo (P1)

Independent test: edit opacity and transform of layer 2, Undo, values and pixels equal the prior ones.

- [ ] CMP-015-T11 [US2] Controls (sliders with drag-end coalescing, pickers, toggles, Reset Layer) in `Apps/projectM-iOS/Views/LayerDetailView.swift` and `LayerInspectorControls.swift`
- [ ] CMP-015-T12 [P] [US2] Unit tests: edit → history step; one drag = one step; Undo restores exact values; capture/restore round trip; nil composites keep carried composites; unknown blend/fit/mask survive in `Apps/projectM-iOS/Tests/LayerInspectorTests.swift`
- [ ] CMP-015-T13 [P] [US2] Render test: Photo host offscreen, layer 2 opacity and transform edit, Undo → pixel-equal frame; the photo picture is reused after a placement edit (CMP-013) in `Apps/projectM-iOS/Tests/LayerInspectorRenderTests.swift`

## Phase 5: User Story 3 - Help (P2)

- [ ] CMP-015-T14 [US3] "?" popovers and footers from `LayerInspectorHelp` in the detail view
- [ ] CMP-015-T15 [P] [US3] Table test: every `LayerInspectorParameter` has a title and help text in `Apps/projectM-iOS/Tests/LayerInspectorTests.swift`

## Phase 6: User Story 4 - Solo and mute (P2)

- [ ] CMP-015-T16 [US4] Solo/Mute buttons in rows, announcements through `AccessibilityAnnouncer` (kind `.layer`), `check_status_events.py` covers the view
- [ ] CMP-015-T17 [P] [US4] Unit tests: solo/mute leave the history and the captured document bytes unchanged; the compositor hides the right layers; a visual change clears them in `Apps/projectM-iOS/Tests/LayerInspectorTests.swift`

## Phase 7: Polish

- [ ] CMP-015-T18 UI test (selection of three layers, opacity drag = one step, Undo restores) in `Apps/projectM-iOS/UITests/LayerInspectorUITests.swift`
- [ ] CMP-015-T19 Type-check timings with the long-body warnings; regression runs (`projectM-iOSTests`, `SceneUndoUITests`, `PhotoLayerUITests`); scripts; PosterBoard count; report in `docs/test-reports/layer-inspector.md`; ADR if needed

## Dependencies

T01 → T02 → (T03, T04, T05 in parallel) → T06 → T07 → US1 (T08-T10) → US2 (T11-T13) → US3, US4 → T18 → T19.

## Parallel examples

- T03, T04, T05 touch different new files.
- T10, T12, T15, T17 are test-only and can be written while the views are built.

## Implementation strategy

MVP = Phases 1-3 (list and read-outs); then editing with undo (the acceptance), help, solo/mute, UI test and polish.
