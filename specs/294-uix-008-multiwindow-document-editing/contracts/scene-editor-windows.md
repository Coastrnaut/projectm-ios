# Contract: Scene editor windows (UIX-008)

- **W1** Open: Scene Folders' "Open in New Window" (identifier `sceneFolderOpenWindow`) calls
  `openWindow(value: SceneEditorWindowID(sceneID:))`; offered only when the environment supports multiple windows.
- **W2** One editor per scene: the router hands a scene's editor only to the window that first took it; any other
  window shows "This scene is open in another window."
- **W3** The editor window shows the stored preview (SCN-006) or a placeholder, a Name field
  (`sceneEditorName`), one opacity slider per layer (`sceneEditorOpacity.<n>`, ACC-005 spec, percent),
  Undo/Redo (`sceneEditorUndo`, `sceneEditorRedo`, ⌘Z/⇧⌘Z), Save (`sceneEditorSave`, ⌘S) and an "Unsaved changes"
  marker (`sceneEditorDirty`).
- **W4** Save: lock refused (SCN-015 message), missing refused ("This scene is no longer stored."), conflict →
  alert "Scene changed elsewhere" with Replace / Reload; otherwise the file is written whole and atomically, the
  library's name updated, its preview invalidated. Never applies to the live output.
- **W5** Main windows: exactly one performs; others show "projectM is open in another window."
- **W6** DEBUG probe (`-uitestSceneEditorProbe`): a hidden element `sceneEditorFileProbe` whose value is the stored
  file's `name` and layer opacities, re-read after each save.
