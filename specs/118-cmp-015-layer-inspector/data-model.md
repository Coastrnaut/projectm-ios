# Data Model: CMP-015 Layer Inspector

## SceneInputs.layerComposites (scene input, saved, undoable)

`[String: SceneComposite]?` keyed by layer kind identifier (`photo`, `video`, `text`,
`spectrum.circular`). nil: capture keeps carried composites (legacy). Non-nil: authoritative; a
missing key is the default composite. Values equal to `SceneComposite()` are never stored.

## LayerInspectorParameter (enum, CaseIterable)

opacity, blendMode, positionX, positionY, scale, rotation, fitMode, fitAnchorX, fitAnchorY, maskShape,
maskSize, maskCornerRadius, maskFeather, maskInverted, group, ownParameters, solo, mute. Each has a
title and a help text in `LayerInspectorHelp.entries` (one table).

## LayerInspectorRow (value)

| Field | Meaning |
|---|---|
| `instance` | the document instance ID (row identity, `layerRow.<instance>`) |
| `kind` | kind identifier |
| `title` | display name ("Photo", "Spectrum", "Text", "Video", "Material (plasma)", …) |
| `position` | 1-based from the bottom |
| `composite` | the saved `SceneComposite` |
| `isEditable` / `readOnlyReason` | CMP-015-R3 |
| `groupName` | the group it belongs to, if any |
| `ownValues` | `[(title, value)]` of the app-held MOD-001 values for this kind |

## LayerInspectorCoordinator (main actor, Observable)

- `composites: [String: SceneComposite]` — the scene input; `set(_:for:)`, `update(kind:_:)`,
  `reset(kind:)`, `restore(_:)` (history apply and launch restore).
- `soloed`, `muted: Set<String>` — transient; `toggleSolo(kind:)`, `toggleMute(kind:)`, `clearSoloMute()`.
- `selectedInstance: UInt64?` — the inspector's selection.
- Callbacks `onCompositesChange`, `onSoloMuteChange`, `endCoalescing`, `announce`.

## State transitions

- Edit → `composites` changes → host apply (next frame) → history records (coalesced by key) →
  autosave debounced.
- Undo/Redo → `applySceneInputs` → `restore(layerComposites)` → host apply.
- Visual change → `clearSoloMute()`.
- Launch restore / Reopen → `restore(document composites)`; history restarts (Reopen) or starts.
