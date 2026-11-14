# Research: MOD-012 Modulation Matrix UI

## MOD-012-D1: Where the enabled flag lives

- **Decision**: a stored `isEnabled` on `AudioFeatureBinding` (default true, last init parameter), so scene
  restore, capture, the host and the inspector carry it without a side table.
- **Rationale**: the binding is already the unit that moves between scene, carry and modulator.
- **Alternatives**: a per-slot flag inside the modulator only (lost on every capture/restore); removing the
  binding and keeping it aside (changes the layer count and the order).

## MOD-012-D2: Fold semantics of a disabled layer

- **Decision**: skipped (the step is not applied). Its signal keeps advancing. No enabled layer → the base
  exactly, without the integer snap (identical to unbound). `isBound` stays true while any layer exists.
- **Rationale**: "affects only its destination route": skipping is the only rule that makes the remaining layers
  bit-identical to the fold without it. Advancing keeps the envelope continuous when re-enabled.
- **Alternatives**: treating a disabled layer as an identity step per mode (same result, more code); freezing its
  signal (a jump on re-enable).

## MOD-012-D3: Reorder rules

- **Decision**: within one destination only; `moveLayer(of:from:to:)` permutes the target's slots among the
  positions they already occupy in the global list, so other targets' positions never change. Out-of-range
  indices throw `unknownTarget` and nothing changes. Edit mode drag and VoiceOver Move Up/Down.
- **Alternatives**: global reorder (meaningless across destinations; changes the scene list for nothing).

## MOD-012-D4: Storage

- **Decision**: optional `enabled` boolean on each `$.bindings` entry, written only when false; absent → true;
  a non-boolean value is malformed. No version bump (AGENT_RULES: new scene fields are optional). An older
  version keeps the field in `extra` and applies the binding.

## MOD-012-D5: Source of truth and undo in the app

- **Decision**: the live list is the host's modulator while a native visual exists, else the autosave carry.
  `ModulationMatrixCoordinator.routes` mirrors it (observable) and joins `SceneInputs.bindings`, so SCN-002 and
  SCN-010 see every edit. An edit applies in place on the host (signals kept), also replaces the carried list (so a
  visual change before the next commit loses nothing), then refreshes the mirror. Undo/redo call `restore(list)`,
  which replaces the list (replaced layers restart at signal 0). The mirror is refreshed after launch restore, host
  creation, Reopen and Start fresh. Capture prefers `inputs.bindings` over the live and carried lists.
- **Labels**: "Turn Off <source> → <destination>", "Turn On …", "Reorder <destination>", else "Modulation".

## MOD-012-D6: Scope

- **Decision**: no create or delete. A route editor needs pickers for six fields with validation messages and is
  a feature of its own; the roadmap row asks for list, enable, reorder and inspect. The empty state says routes
  come with scenes.

## MOD-012-D7: Testing without audio

- **Decision**: package acceptance with injected features and frame times; app test with a real host; the DEBUG
  seed uses constant output ranges (start = end) so the per-destination probe is independent of audio and time:
  A kick → intensity replace 0.6, B LFO 1 → intensity multiply 0.5, C band 3 → radius replace 0.04. Probe:
  intensity 0.3000 → 0.6000 when B is off; radius 0.0400 throughout.
