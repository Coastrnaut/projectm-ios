# Research: SCN-010 Scene Undo and Redo

## SCN-010-D1: Snapshots, not diffs or commands

- **Decision**: store whole states: the canonical SCN-001 bytes plus the app value that produces them.
- **Rationale**: ADR-0028 makes semantic equality canonical byte equality, so a snapshot is both the
  thing compared and the thing restored. App scene documents are 1-3 KB (no embedded media; a Text
  spec is under 1 KB), so 50 steps cost well under 1 MB. A snapshot cannot drift.
- **Alternatives**: structural diffs (more code; savings irrelevant at this size); command objects
  with inverses (every future editor needs an inverse; inverse bugs corrupt the scene).

## SCN-010-D2: The value restored is the app's `SceneInputs`, the bytes are the document

- **Decision**: `SceneHistory<Value>` is generic; the app's value is SCN-002's `SceneInputs`, applied
  through the Settings path. The bytes come from `SceneAutosaveCapture.document(inputs, carry:)`
  over a carry snapshot taken when the history (re)starts.
- **Rationale**: applying `SceneInputs` is exactly what Settings and cues do (no lossy document →
  settings mapping); the bytes still cover the ordered layer stack and all parameters, so the
  acceptance compares the full document. A fixed carry keeps bytes a pure function of the inputs
  (autosave refreshes its carry's bindings at commits, which must not look like edits).
- **Alternatives**: decoding the document on undo (`ShowSceneSnapshot.apply`): loses values that do
  not reach the document (the text spec while another visual is shown) and needs a registry.

## SCN-010-D3: Coalescing by key with explicit boundaries

- **Decision**: a record with a non-nil key equal to the open key replaces the current state and the
  top step's label instead of pushing; if the merged state equals the top step's "before" state the
  step is dropped (a drag back to its start is no edit) and the key closes. Boundaries:
  `endCoalescing()` (slider drag end, Settings closing), an undo or redo, a different key, a nil key.
- **Keys**: `glow.intensity`, `glow.radius`, `glow.threshold`, `text.message`, `text.size`,
  `text.outline`. Pickers and toggles (visual, bars, orientation, spacing, glow on/off, text font,
  weight, colors, alignment, position, box) have no key.
- **Rationale**: deterministic, no clock (constraint), matches user intent for drags and typing.

## SCN-010-D4: Bounds

- **Decision**: ≤ 50 undo steps and ≤ 4 MB of stored bytes (current + undo + redo); evict the oldest
  undo steps, then the farthest redo steps; a current state larger than the budget leaves both lists
  empty.
- **Rationale**: 50 is the common app default; 4 MB is a hard ceiling for imported content later
  (embedded text and graph documents) while today's states are tiny.

## SCN-010-D5: Non-edits restart the history

- **Decision**: launch restore, Reopen/Start fresh (PERF-010), a cue application (SHOW-001) and a
  photo or video replacement that changes the scene call `restart()`: current = the new scene, both
  lists empty. Choosing Camera is no change (Camera records the visual before it, CAM-001-R11).
- **Rationale**: conservative; undo never jumps across a cue or brings back a deleted photo.

## SCN-010-D6: Applying a state

- **Decision**: `AppCoordinator.applySceneInputs(_:)` sets bars, orientation, spacing, glow values
  and the text spec, then the visual only if the recorded visual differs (so an undo that does not
  change the visual leaves Camera running), then `visualSettingsChanged()` and
  `glowSettingsChanged()`. Photo and video IDs are never applied (the store is not undoable).
- **Observation**: the change is observed asynchronously; the inputs now produce the bytes the
  history already holds, so the record is a no-op (D1 no-op suppression); no flag is needed.
- **Autosave**: SCN-002 observes the same change and commits it under its rules (a visual change at
  once, others debounced).

## SCN-010-D7: UI

- **Decision**: Undo and Redo buttons (`arrow.uturn.backward` / `.forward`) in Settings' leading
  navigation bar, identifiers `sceneUndo` / `sceneRedo`, labels "Undo <step>" / "Redo <step>",
  disabled when unavailable, ⌘Z / ⇧⌘Z. The visualizer has hidden ⌘Z / ⇧⌘Z key buttons (like
  SHOW-001's cue keys). No shake to undo (the system undo manager is not used).
- **Label text**: "Visual Circular Spectrum", "Bars 16", "Orientation Horizontal", "Spacing Wide",
  "Glow On"/"Glow Off", "Glow Intensity 75%", "Glow Radius 2.0%", "Glow Threshold 50%",
  "Text Message", "Text Size 40%", "Text Outline 5%", "Text" (other text style), "Scene" (several
  controls at once).
