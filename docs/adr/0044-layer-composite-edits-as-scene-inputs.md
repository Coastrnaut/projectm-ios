# ADR-0044: Layer Composite Edits Are Scene Inputs, Applied by Kind to the Shown Compositor

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CMP-015 (`specs/118-cmp-015-layer-inspector`)
- **Constitution**: VI (modular boundaries: app target only, no package change), X (evidence-based
  quality); accessibility (ACC-001, ACC-005); privacy (nothing stored beyond the scene document)
- **Builds on**: SCN-001 (scene format, ADR-0028), SCN-002 (autosave), SCN-010 (undo history), CMP-002 to
  CMP-007 (stack and composites), CMP-004 (ADR-0037, blend modes), CMP-012 (solo and mute), CMP-013
  (ADR-0040, render caching)
- **Number**: 0044. 0043 is left to FILE-008 (running in parallel); 0015, 0016, 0025, 0026 and 0031 stay
  unused.

## Context

The roadmap asks to "expose per-layer controls with undo and contextual help", accepted when "selecting
different layers shows correct parameters and undo restores prior value". The audit (spec Baseline) found
four compositor hosts with fixed two-layer stacks (Camera, Photo, Video, Text), native spectra drawn
without the compositor, and no live scene with any editable layer composite: the autosave wrote back a
restored layer's composite but no host ever applied it. SCN-010 undoes only `SceneInputs`; CMP-004 left
blend modes without a picker.

## Decision

1. **Scope.** The inspector shows the document the autosave would save now, top first. Only photo,
   video, text and the circular spectrum of the Photo, Video and Text scenes are editable (drawn by a
   compositor). Carried layers (materials, generator graphs, unknown kinds) and the single layer of the
   Circular and Linear Spectrum scenes are read-only with the reason. Camera is session only and keeps
   its default stack.
2. **Edits are a scene input.** `SceneInputs.layerComposites: [String: SceneComposite]?`, keyed by layer
   kind (at most one drawn layer per kind per scene). nil keeps today's capture (a matched layer keeps
   its carried composite); non-nil, which the app always passes, is authoritative (a missing kind writes
   the default composite). Launch restore and Reopen fill it from the document; default composites are
   never stored. `SceneComposite` keeps unknown blend, fit and mask names verbatim. This amends SCN-010's
   list of undoable inputs (layer composites join it) and SCN-002's capture (the inspector's composite
   replaces a carried one for drawn kinds).
3. **Undo.** SCN-010 records the inputs as before. A slider's key is `layer.<kind>.<parameter>` (one drag,
   one step; each VoiceOver swipe through ACC-005's `.accessibleParameter` is its own step); pickers,
   toggles and Reset Layer are one step each. Undo applies the composites through the same path, so the
   rendered frame is byte-identical to the frame before the edit (test-proven on the simulator).
4. **Live apply.** `Compositor.applyLayerComposites` (app extension) copies the applied stack, sets each
   entry's settings from its kind and applies it; every ID is kept, so no layer is re-created and CMP-013
   keeps cached pictures for placement changes. Opacity changes are immediate.
5. **Blend picker.** The six CMP-004 modes get a picker in the inspector (ADR-0037 had no UI to put one
   in); an unknown saved name shows as "Other (name)" until a known mode is chosen.
6. **Solo and mute** stay CMP-012's transient overlay, by kind, for the shown visual; cleared when the
   visual changes; never in the inputs, the document or the history.
7. **Show cues** keep capturing only their look (no composites); a follow-up can add them.

## Consequences

- Composites edited on one of Photo, Video or Text share the circular spectrum's composite with the
  others, as the autosave already matched carried layers by kind.
- Groups are listed read-only; the autosave capture still does not write groups (existing behaviour,
  noted for a later row).
- Adding, removing and reordering layers need hosts that build arbitrary stacks (a later row).
