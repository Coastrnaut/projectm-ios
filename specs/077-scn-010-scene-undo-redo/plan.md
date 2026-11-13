# Implementation Plan: SCN-010 Scene Undo and Redo

**Branch**: `feature/scn-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/077-scn-010-scene-undo-redo/spec.md`

## Summary

Two layers:

1. **SceneFormat** (pure, Linux): `SceneHistory<Value>`, a bounded snapshot history. Each state is
   `SceneHistoryState<Value>` = canonical SCN-001 bytes plus a caller value (the app's
   `SceneInputs`; the tests use the `SceneDocument` itself). `record(_:label:coalescingKey:)`
   suppresses no-ops by byte equality, coalesces consecutive records with the same non-nil key until
   `endCoalescing()`, clears redo on a new step and enforces 50 steps / 4 MB (oldest undo first,
   then farthest redo). `undo()` / `redo()` return the state to apply; `reset(to:)` restarts.
2. **App**: `SceneHistoryCoordinator` (@MainActor, @Observable) observes `AppCoordinator.sceneInputs`
   like SCN-002 does, captures each change as a document with `SceneAutosaveCapture.document` over a
   carry snapshot, names the step (`SceneHistoryEdit.describe`: "Bars 16", "Glow Intensity 75%",
   key for sliders and typing), and applies undo/redo through `AppCoordinator.applySceneInputs`
   (the Settings/cue path: setters, text coordinator, visual switch, `visualSettingsChanged()`,
   `glowSettingsChanged()`). Cue application, Reopen, Start fresh and photo/video replacement call
   `restart()`. Settings gets Undo/Redo toolbar buttons with ⌘Z / ⇧⌘Z; the visualizer gets hidden
   ⌘Z / ⇧⌘Z key commands; slider drag ends and Settings closing end coalescing.

ADR-0028 is amended (history compares by canonical bytes; snapshots; in memory only). No new ADR: no
default is overridden.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: SceneFormat (existing codec), app: SwiftUI, Observation. No new package.

**Storage**: none. The history is in memory only; SCN-002 keeps committing the current scene.

**Testing**: XCTest. `swift test --package-path Packages/SceneFormat --filter SceneHistory` on the
host and the Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE`); `xcodebuild test` of `projectM-iOSTests` (new
`SceneHistoryCoordinatorTests`), the new `SceneUndoUITests`, and `SceneAutosaveUITests`,
`NativeVisualUITests`, `ShowCueUITests` on an own iOS 27.2 simulator. Budgets (owner rule 7): unit
≤ 10 s (target 1-2 s), suite < 1 min, UI test < 30 s, property test ≤ 1 s.

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI; app iOS 26+

**Project Type**: mobile app + SwiftPM packages

**Performance Goals**: one capture and encode per observed change (a few KB, well under 1 ms on the
main actor); undo/redo apply is a handful of setter calls.

**Constraints**: no networking; deterministic model (no clock); no main-actor mutation in
setUp/tearDown; no wall-clock assertions; the audio source is never touched.

**Scale/Scope**: ≤ 50 steps, ≤ 4 MB.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI, Observation, Foundation. No private API, no system undo manager hooks. |
| II-V Capture | Not affected: undo never touches the audio source (R7); no capture claim. |
| VI Modular boundaries | Pass: the history model lives in SceneFormat (pure, Linux); app wiring in the app target. |
| VII Real-time audio safety | Pass: nothing on audio threads; main-actor work only on user edits. |
| VIII Upstream fidelity | Not affected (no engine change). |
| IX Pinned dependencies | Pass: no new dependency. |
| X Evidence-based quality | Pass: unit, property and UI tests; simulator only, no device claim. |
| Privacy | Pass: nothing stored, nothing sent. Compliance script runs. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/077-scn-010-scene-undo-redo/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/scene-history.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/SceneFormat/Sources/SceneFormat/SceneHistory.swift          # new: the model
Packages/SceneFormat/Tests/SceneFormatTests/SceneHistoryTests.swift  # new: acceptance, bounds, property
Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift         # new: observe, record, undo/redo, labels
Apps/projectM-iOS/Coordinators/AppCoordinator+SceneHistory.swift     # new: wiring, apply path
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                  # small: property, start, restart hooks
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift             # one line: restart after a cue
Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift        # one accessor: carry snapshot
Apps/projectM-iOS/Views/SettingsView.swift                           # toolbar buttons, slider end
Apps/projectM-iOS/Views/VisualizerView.swift                         # pass history; hidden key commands
Apps/projectM-iOS/Tests/SceneHistoryCoordinatorTests.swift           # new
Apps/projectM-iOS/UITests/SceneUndoUITests.swift                     # new
docs/adr/0028-scene-document-format.md                               # amendment
```

**Structure Decision**: existing package and app layout; no new package or target (XcodeGen picks up
new files by folder).

## Complexity Tracking

None.
