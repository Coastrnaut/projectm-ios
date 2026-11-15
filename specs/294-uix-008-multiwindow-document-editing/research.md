# Research: UIX-008 Multiwindow Document Editing

## UIX-008-D1: Enable multiple scenes, keep the external display role

- **Decision**: Set `UIApplicationSupportsMultipleScenes` to true and keep the manifest's only configuration, the
  non-interactive external display role (OUT-001, ADR-0023). SwiftUI keeps the application role for both window
  groups.
- **Rationale**: `WindowGroup(for:)` windows need the key; the external display configuration is per role and
  independent of it. On iOS 27 the external display is a scene accessory attached to the main window's content
  only, so editor windows never add an accessory.
- **Alternatives**: a UIKit scene delegate per role (rejected: OUT-001 found SwiftUI's window empty with an
  application-role delegate).

## UIX-008-D2: A value-based window group for editors

- **Decision**: `WindowGroup("Scene", for: SceneEditorWindowID.self)`; `SceneEditorWindowID` is a `Codable`,
  `Hashable` wrapper of the scene ID. Opened with `openWindow(value:)`.
- **Rationale**: SwiftUI restores the window from the value and brings an existing window with an equal value
  forward instead of opening a second (UIX-008-R6).
- **Alternatives**: a document-based app (`DocumentGroup`; rejected: the library is the app's private store, not
  Files documents).

## UIX-008-D3: Editable fields

- **Decision**: name (SCN-003 `renamed(to:)` rules) and per-layer opacity, clamped to 0…1. Each is a coalescing
  key in the editor's own `SceneHistory` (`name`, `opacity.<instance>`).
- **Rationale**: neither edit can make a valid scene invalid, so no SCN-012 repair step is needed at save; richer
  editing is bound to the live engine and stays in the main window.

## UIX-008-D4: One editor per scene

- **Decision**: `SceneEditorWindowRouter.editor(for:window:)` returns the existing editor to the window that owns
  it, and nil (a "open in another window" notice) to any other window token; `release(window:)` on disappear
  frees it. `request(sceneID)` reports `.focusExisting` or `.openNew` for the action.
- **Rationale**: two models for one file would be two writers; SwiftUI usually prevents the duplicate window,
  and the router guarantees it (restoration, races).

## UIX-008-D5: Saving

- **Decision**: `ShowCoordinator.saveEditedScene(_:expectedBytes:replacing:)`: refuse when SCN-015 is locked;
  refuse when the scene is no longer in the library; when not replacing, compare the file's bytes with
  `expectedBytes` and report `.conflict` without writing; write with `ShowStore.saveScene` (whole, atomic, SCN-013
  original kept); update `sceneNames`; report `sceneFilesChanged` (SCN-006). Never applies.
- **Rationale**: one writer path, the existing atomic writer; the index (`show.json`) does not change.

## UIX-008-D6: Offering the action

- **Decision**: `@Environment(\.supportsMultipleWindows)` gates "Open in New Window" in the context menu, the
  leading swipe actions and the accessibility actions; false on iPhone.

## UIX-008-D7: One performance window

- **Decision**: `PerformanceWindowClaim` (main actor, observable) holds the performing window's token; each main
  window instance claims on appear when free and releases on disappear; others show a notice and claim when the
  owner leaves.
- **Rationale**: with multiple scenes on, the system can create a second main window (app switcher, menu). Two
  `RootView`s over one coordinator would mean two visual slots and sheets.

## UIX-008-D8: Scene phase

- **Decision**: forward the performing window's own `scenePhase` to `sceneBecame(active:)` instead of the app's
  aggregate phase.
- **Rationale**: with one window both are equal; with editor windows the aggregate stays active while the
  performance window is in the background.

## UIX-008-D9: Proving no second engine

- **Decision**: `EngineInstanceLedger` (main actor counters) incremented where `AppCoordinator` is initialized
  (which creates the one `CaptureManager`) and where the renderer is created. Tests compare counts before and after
  creating routers, editors and saves.
