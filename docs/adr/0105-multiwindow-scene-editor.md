# ADR-0105: Multiple Windows Edit Saved Scenes; One Window Performs

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: UIX-008 (`specs/294-uix-008-multiwindow-document-editing`)
- **Constitution**: I (public APIs only), VI (modular boundaries), VII (real-time safety)
- **Amends**: ADR-0023 (OUT-001): "multiple windows stay off" no longer holds; the external display role
  configuration is unchanged

## Context

The roadmap row UIX-008 asks to "allow multiple scene documents where iPadOS supports it", with the acceptance
"Two scenes edit independently and save to separate files". The app had one SwiftUI window group over one
`AppCoordinator`, which owns the only audio capture (`CaptureManager`) and the only ANGLE renderer.
`UIApplicationSupportsMultipleScenes` was false. Saved scenes are SHOW-001's files, one per scene ID, written
whole and atomically by `ShowStore`.

## Decision

1. **Multiple scenes on.** `UIApplicationSupportsMultipleScenes` is true. The scene manifest still configures
   only the non-interactive external display role (OUT-001); SwiftUI keeps the application role. On iOS 27 the
   external display accessory stays on the main window's content only.
2. **Editor windows.** A second window group, `WindowGroup(for: SceneEditorWindowID.self)`, opens one saved scene
   per window ("Open in New Window" in Scene Folders, offered only when `supportsMultipleWindows` is true). Each
   window has its own `SceneDocumentEditor`: a working copy, its own SCN-010 history, a dirty flag. It edits the
   name and layer opacities only.
3. **No second engine.** Editor windows show the stored SCN-006 preview picture at most. They never create a
   renderer, capture, camera or output, and saving never applies a scene to the live output. `EngineInstanceLedger`
   lets tests count coordinators and renderers.
4. **One editor per scene.** `SceneEditorWindowRouter` gives a scene's editor only to the window that opened it;
   `openWindow(value:)` brings an existing window forward.
5. **Saving.** One path, `ShowCoordinator.saveEditedScene`: refused while the scene lock is on or when the scene
   is no longer stored; a conflict, with nothing written, when the file changed after the editor read it (Replace
   or Reload); else `ShowStore.saveScene` (whole, atomic, SCN-013 originals kept), then the name cache and SCN-006
   preview update. The library index (`show.json`) is unchanged.
6. **One performing main window.** With multiple scenes on, the system can create a second main window.
   `PerformanceWindowGate` lets the first main window perform; others show a notice and take over when it closes.
   Only the performer forwards its own scene phase to `AppCoordinator.sceneBecame`, in place of the app's
   aggregate phase.
7. **Restoration.** The system restores editor windows from the scene ID; they reload the file and unsaved edits
   are lost. DEBUG UI-test runs (`-uitestResetNotice`) close restored editor windows so every test starts on the
   main window.

## Consequences

- On iPhone nothing changes: the action is hidden.
- On iPad without Stage Manager, a new window takes the screen; the user returns through the app switcher.
- Two windows side by side, and the external display with editor windows open, are device checks on D2 and D3
  with Stage Manager (UIX-008-T16).
- Richer editing (layers, modulation) stays in the main window, where the live engine is.
