# Implementation Plan: UIX-008 Multiwindow Document Editing

**Branch**: `feature/uix-008` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Turn on iPadOS multiple windows (`UIApplicationSupportsMultipleScenes` true; the OUT-001 external display role
stays as configured) and add a second SwiftUI scene, `WindowGroup(for: SceneEditorWindowID.self)`, whose windows
each edit one saved scene (research UIX-008-D1, D2). Scene Folders offers "Open in New Window" only when
`supportsMultipleWindows` is true (D6). Each window gets a `SceneDocumentEditor` (main actor, observable): the
document read from the SHOW-001 store, the bytes it was read from, its own SCN-010 `SceneHistory<SceneDocument>`
and a dirty flag; edits are the name (SCN-003 rules) and each layer's opacity (D3). `SceneEditorWindowRouter`
holds at most one editor per scene ID (D4; `openWindow(value:)` already brings an open window with the same value
forward). Save goes through `ShowCoordinator.saveEditedScene` (new, `ShowCoordinator+SceneEditing.swift`): lock
check, conflict check against the loaded bytes, `ShowStore.saveScene` (whole, atomic), then the name cache and
SCN-006 preview invalidation; it never applies (D5). The main window group's content is wrapped in
`PerformanceWindowGate`: the first main window claims the performance role through `PerformanceWindowClaim`; any
other shows a notice (D7). The scene phase forwarded to `AppCoordinator.sceneBecame` becomes the performing
window's own phase (D8). No editor creates an engine or capture; `EngineInstanceLedger` counts `AppCoordinator`
and renderer creations so a test can prove it (D9). ADR-0105 records the window architecture.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2)
**Primary Dependencies**: SwiftUI scenes (`WindowGroup(for:)`, `openWindow`, `supportsMultipleWindows`), SceneFormat
(`SceneDocument`, `SceneHistory`), ShowControl/ShowStorage (`ShowStore`)
**Storage**: the existing SHOW-001 scene files `Show/Scenes/<SCENE-ID>.scene.json`; no new UserDefaults keys
(window restoration is the system's, keyed by the scene ID value)
**Testing**: XCTest app tests `SceneDocumentEditorTests` (two editors, undo independence, separate files, index,
lock, conflict, missing scene), `SceneEditorWindowRouterTests` (one editor per scene, performance claim, instance
counts); UI test `SceneEditorWindowUITests` on the "UIX8 iPad Pro" iOS 27.2 simulator; regression: OUT-001 external
display UI tests, Scene Folders UI test
**Target Platform**: iPadOS (multiple windows); iPhone unchanged (action hidden)
**Project Type**: iOS app
**Performance Goals**: no engine, capture, renderer or timer in an editor window; a save is one file write
**Constraints**: small edits to `ProjectMApp.swift`, `AppCoordinator.swift` (two counter lines), `SceneFoldersView.swift`
(one action), `project.yml` (one plist value); Xcode 26 type-check budget
**Scale/Scope**: 6 new source files, 3 new test files, ADR-0105

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI scene APIs and UIKit's documented multiple-scenes key | Pass |
| VI Modular boundaries | Editing model in the app over SceneFormat's pure history and ShowStorage's store; no engine reference | Pass |
| VII Real-time safety | Editor windows touch no audio or render path | Pass |
| VIII Upstream fidelity | projectM untouched | Pass |
| X Evidence | App tests and a simulator UI test; Stage Manager on D2/D3 is `{device}` | Pass |
| Privacy | Files stay in the app container; nothing new stored or sent | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

```text
specs/294-uix-008-multiwindow-document-editing/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/scene-editor-windows.md
└── checklists/requirements.md

Apps/projectM-iOS/ProjectMApp.swift                                   (second WindowGroup, gate, per-window phase)
Apps/projectM-iOS/Coordinators/SceneDocumentEditor.swift              (new: per-window model)
Apps/projectM-iOS/Coordinators/SceneEditorWindowRouter.swift          (new: routing, performance claim, ledger)
Apps/projectM-iOS/Coordinators/ShowCoordinator+SceneEditing.swift     (new: load, stored bytes, saveEditedScene)
Apps/projectM-iOS/Views/SceneEditorWindowView.swift                   (new: the editor window)
Apps/projectM-iOS/Views/PerformanceWindowGate.swift                   (new: the main window's gate)
Apps/projectM-iOS/Views/SceneFoldersView.swift                        (Open in New Window)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                   (ledger counts, router property)
Apps/projectM-iOS/Tests/SceneDocumentEditorTests.swift, SceneEditorWindowRouterTests.swift (new)
Apps/projectM-iOS/UITests/SceneEditorWindowUITests.swift              (new)
project.yml                                                           (UIApplicationSupportsMultipleScenes true)
docs/adr/0105-multiwindow-scene-editor.md                             (new)
```

**Structure Decision**: app-level model files beside the SHOW-001 coordinator; the pure history already lives in
SceneFormat, so no package changes are needed.

## Complexity Tracking

None.
