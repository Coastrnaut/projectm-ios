# Research: CMP-015 Layer Inspector

## CMP-015-D1 Scope from the audit

- **Decision**: list the layers of `SceneAutosaveCapture.document(sceneInputs, carry:, liveBindings: nil)`
  (what the autosave would save), top first; editable only for photo, video, text and
  spectrum.circular while the recorded visual is Photo, Video or Text.
- **Rationale**: the audit found four compositor hosts with fixed two-layer stacks (Camera, Photo,
  Video, Text), native spectra drawn without the compositor, and no live scene with an editable
  layer. The captured document is the single truth for "the current scene"; its layers map 1:1 by
  kind to the shown host's stack. Camera is session only (CAM-001-R11): not part of a scene.
- **Alternatives**: `SceneLiveState.stack` (drops unknown kinds, so the list would hide saved
  layers); the host's applied stack (has no carried layers and no Camera/recorded distinction).

## CMP-015-D2 Edits as a scene input

- **Decision**: `SceneInputs.layerComposites: [String: SceneComposite]?`. nil (tests and old callers)
  keeps today's capture (a matched layer keeps its carried composite); non-nil is authoritative per
  drawn kind (a missing kind writes the default composite). The app always passes non-nil: the
  coordinator's dictionary, filled from the document's layers at launch restore and Reopen (default
  composites are not stored, so a reset removes the key).
- **Rationale**: SCN-010 snapshots `SceneInputs`, so undo, redo, coalescing and byte-equality
  suppression come for free; SCN-002 saves it with its existing debounce. `SceneComposite` keeps an
  unknown blend name, fit mode or mask shape verbatim (CMP-015-R9).
- **Alternatives**: `LayerCompositeSettings` (cannot hold unknown names); keying by instance ID
  (instances are renumbered by capture; kinds are unique per drawn stack).

## CMP-015-D3 Live apply

- **Decision**: `Compositor.applyLayerComposites(_:)` (app extension) copies `appliedStack`, sets each
  entry's settings from the kind's composite (default when absent) and calls `apply` with a factory
  that is never called (every ID is kept). Opacity changes are immediate (exact undo).
  `applySoloMute(soloed:muted:)` builds a `LayerSoloMute` from the stack's IDs by kind.
- **Rationale**: the only live path; CMP-013 keeps kept layers' pictures for placement changes.

## CMP-015-D4 History labels and coalescing

- **Decision**: `SceneHistoryEdit.describe` adds "Spectrum Opacity 40%"-style labels; one changed
  parameter on one kind gives key `layer.<kind>.<parameter>` for sliders and nil for pickers and
  toggles; several (Reset Layer) give "Reset <Layer>" with nil. Slider drags end coalescing on
  release, as Settings' glow sliders do.

## CMP-015-D5 Help table

- **Decision**: `LayerInspectorParameter` (a `CaseIterable` enum) and one `[parameter: help]` table
  (`LayerInspectorHelp.entries`); a "?" button opens a popover with the entry; section footers use the
  same entries. A test checks every case has non-empty text.

## CMP-015-D6 Accessibility

- **Decision**: each slider has a label, a spoken value and an adjustable action with a fixed step
  (the ACC-005 `.accessibleParameter` helper is not in this base; the same pattern is used and noted
  for ACC-005 to adopt); rows use `ViewThatFits` to stack at accessibility sizes; solo and mute are
  announced through `AccessibilityAnnouncer` (new kind `.layer`); no animation is added.

## CMP-015-D7 Pixel proof

- **Decision**: an app unit test renders a `PhotoVisualHost` offscreen (seeded PNG, fixed band values),
  edits opacity and transform of layer 2 (the spectrum) through the coordinator and a real
  `SceneHistoryCoordinator`, undoes twice and compares read-back pixels byte for byte with the frame
  before the edit.

## CMP-015-D8 Out of scope

- Show cues do not carry composites (ShowLook unchanged; a cue restarts the history as today).
- Groups are listed read-only; the autosave capture does not write groups (existing behaviour).
- Adding, removing, reordering layers.
