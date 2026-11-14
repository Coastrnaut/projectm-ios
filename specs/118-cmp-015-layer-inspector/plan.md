# Implementation Plan: CMP-015 Layer Inspector

**Branch**: `feature/cmp-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/118-cmp-015-layer-inspector/spec.md`

## Summary

A Settings → Layers screen lists the current scene's layers (the document the autosave would save)
top first, with Solo and Mute per drawn layer. Selecting a layer shows its composite (opacity, blend,
transform, fit, mask), group membership and its app-held MOD-001 values; drawn layers of the Photo,
Video and Text scenes are editable. Edits are a new scene input (`SceneInputs.layerComposites`, one
saved `SceneComposite` per drawn kind), so SCN-002 saves them and SCN-010 undoes them with
per-control coalescing; the app applies them to the shown host through `Compositor.apply` on a copy
of the applied stack (CMP-013 keeps cached pictures). Help text comes from one table keyed by
parameter. Research: [research.md](research.md); model: [data-model.md](data-model.md); contract:
[contracts/layer-inspector.md](contracts/layer-inspector.md); run guide: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), strict concurrency; CI also builds with Xcode 26.

**Primary Dependencies**: SwiftUI, Compositor, SceneFormat, ParameterGraph, VisualParameters (all in
repo). No new package or dependency.

**Storage**: The existing autosave document (SCN-001 layer `composite`); no new file or key.

**Testing**: XCTest app unit tests (`projectM-iOSTests`), XCUITest (`LayerInspectorUITests`), iOS 27.2
simulator; Metal offscreen frames for the pixel comparison.

**Target Platform**: iOS/iPadOS 26.5+ (app target).

**Project Type**: mobile app (app target only; no package change).

**Performance Goals**: an edit shows from the next frame; no layer re-render for placement edits
(CMP-013); a history record per edit costs one document encode (as today).

**Constraints**: owner rule 7 test budgets; SwiftUI bodies small (300 ms function / 150 ms expression
type-check warnings); public APIs only; announcements through `AccessibilityAnnouncer`; animation only
through `MotionPolicy` (none planned).

**Scale/Scope**: at most 8 layers per scene (CMP-002); 16 inspector parameters.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | SwiftUI and Metal public API only. Pass. |
| VI. Modular boundaries | App-target code only; packages unchanged (SceneFormat's `SceneComposite` and Compositor's public `appliedStack`/`apply` are reused). Pass. |
| VII. Real-time audio safety | No audio-path change. Pass. |
| X. Evidence-based quality | Unit, render and UI tests on the simulator; simulator results are never device evidence; GPU timing on devices not claimed. Pass. |
| Privacy | Nothing leaves the device; solo/mute never stored. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/118-cmp-015-layer-inspector/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/layer-inspector.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/
│   ├── LayerInspectorModel.swift          # NEW: parameters, help table, rows, composite edits, mapping
│   ├── LayerInspectorCoordinator.swift    # NEW: composites (scene input), solo/mute (transient)
│   ├── AppCoordinator+LayerInspector.swift # NEW: wiring, live apply, restore, rows
│   ├── SceneAutosaveCapture.swift          # SceneInputs.layerComposites; capture and restore
│   ├── SceneHistoryCoordinator.swift       # labels and coalescing keys for layer edits
│   ├── AppCoordinator+SceneHistory.swift   # applySceneInputs sets the composites
│   ├── AppCoordinator.swift                # sceneInputs, restore apply, host creation (small)
│   ├── SceneAutosaveCoordinator.swift      # DEBUG carry seed for the UI test
│   └── AccessibilityAnnouncer.swift        # kind .layer
├── Visuals/Compositor+LayerComposites.swift # NEW: apply composites and solo/mute by kind
├── Views/
│   ├── LayerInspectorView.swift            # NEW: the list, solo and mute
│   ├── LayerDetailView.swift               # NEW: sections per parameter group
│   ├── LayerInspectorControls.swift        # NEW: slider row, help button
│   ├── SettingsView.swift                  # "Layers" row (small)
│   └── VisualizerView.swift                # passes the inspector to Settings (one line)
├── Debug/UITestLayerInspectorFixture.swift # NEW: -uitestLayerInspectorSeed
├── Tests/LayerInspectorTests.swift         # NEW: model, help, history, solo/mute, autosave
├── Tests/LayerInspectorRenderTests.swift   # NEW: undo pixel comparison, CMP-013 reuse
└── UITests/LayerInspectorUITests.swift     # NEW
scripts/check_status_events.py              # the inspector view joins the checked files
```

**Structure Decision**: app target only; every pure piece (`LayerInspectorModel.swift`) is a plain
value type tested without UI.

## Complexity Tracking

None.
