# Research: SHOW-001 Manual Cue List

Decisions are numbered SHOW-001-D1… (never a bare two-digit research ID, which the docs validator
reserves for feature 001).

## SHOW-001-D1 — Where the model lives

- **Decision**: new package `Packages/ShowControl` with two targets: `ShowControl` (pure model,
  Foundation only) and `ShowStorage` (folder store, depends on SceneFormat).
- **Rationale**: the later rows (SHOW-002 timed advance, SHOW-003 beat advance, SHOW-005 hold/skip,
  OSC-012 cue sync) all drive the same list; a dependency-free model is reusable by OSC and testable on
  Linux without the compositor. `PerformanceControl` has no scene dependency and should not get one.
- **Alternatives**: `PerformanceControl` (mixes OSC/tempo with documents); app-only code (no Linux
  tests, harder for OSC-012).

## SHOW-001-D2 — How cues refer to scenes

- **Decision**: by SCN-001 scene ID (canonical uppercase UUID text). Each scene used by the show is
  stored as canonical SCN-001 bytes in `Scenes/<sceneID>.scene.json` next to `show.json`. Adding the
  current look stores a snapshot with a new scene ID. Several cues may share a scene ID. Unreferenced
  scene files are deleted after the show file that dropped them is saved.
- **Rationale**: keeps the show file small (rewritten on every step for the position), lets the
  future library (SCN-004 to SCN-006) take over the scene files by the same IDs, and the stored
  document's own `id` equals the file name, so "preserves scene IDs" is checkable byte for byte.
- **Alternatives**: embed scenes in the show file (large rewrites per step, duplicates); reference the
  live current scene of SCN-002 (mutates after the cue is made).
- **What the scene library changes**: the store will resolve a scene ID in the library first and the
  show folder second; a migration moves folder scenes into the library without changing IDs.

## SHOW-001-D3 — Position model and end behaviour

- **Decision**: `position` is `.standby` or `.cue(UUID)`. Next: standby → first, n → n + 1, last →
  no move (`atEnd`). Previous: n → n − 1, first or standby → no move (`atStart`). Empty → `empty`.
  Go to: any existing cue (`moved`, also when it is the active one: re-apply). Deleting the active cue
  moves the position to the cue before it (standby if first) without applying. Moves keep the
  position's cue ID.
- **Rationale**: a cue ID survives reorder, which a bare index does not; stop at the ends is the safe
  live default (Clarifications). Deterministic by construction: the model is a value type whose
  operations read only the cue array and the position.
- **Alternatives**: index cursor (breaks on reorder); wrap (rejected in Clarifications).

## SHOW-001-D4 — Document encoding and versioning

- **Decision**: JSON via `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`, fields
  `format` ("projectm-ios.show"), `version` (1), `id`, `name`, `cues` [{`id`, `scene`, `label`}],
  `position` (null or the cue ID). Decoding checks size (≤ 1 MiB) before parsing, then format, version
  (> 1 refused as newer), limits, UUID texts, label rules, duplicate cue IDs.
- **Rationale**: the show is a simple, closed structure; Codable is enough and deterministic with
  sorted keys. SCN-001's own codec is for scenes (unknown-field preservation, canonical numbers); a
  show has no numbers but the version.
- **Alternatives**: SCN-001's `SceneJSON` reader/writer (more code for no gain here); property lists.

## SHOW-001-D5 — Applying a cue in the app

- **Decision**: SCN-002's restore path is not on `autonomous/integration` yet, so a minimal path:
  `ShowSceneSnapshot.capture` builds a document from the look (layers per visual as the hosts build
  them: Circular `[spectrum.circular]`, Linear `[spectrum.linear]`, Photo `[photo, spectrum.circular]`,
  Video `[video, spectrum.circular]`, Text `[spectrum.circular, text]`, projectM `[]`; the seven MOD-001
  values the app holds: bar count, orientation, spacing, glow on, intensity, radius, threshold; the
  text spec as an embedded text asset; photo/video as store IDs). `ShowSceneSnapshot.look(of:)` maps a
  validated document back (visual from the layer kinds, values through a scratch MOD-001 store for
  clamping, text spec). The coordinator sets `AppSettings`/`texts.spec` and calls
  `visualSettingsChanged()` and `glowSettingsChanged()`: the same path as Settings, which never touches
  the audio source.
- **Follow-up**: unify with SCN-002's `SceneAutosaveCapture` once integrated (same layer mapping and
  parameter set; one capture/restore for both). Recorded in the ADR.
- **Camera**: a captured look records the visual chosen before Camera; a document with a camera layer
  maps to the remaining layers (Circular when a spectrum is left, else projectM) with a notice.
- **Unknown kinds** (materials, graphs, unknown): not drawn by the app's hosts today; the look is
  built from the known layers and a notice says part of the scene is not shown.

## SHOW-001-D6 — Blackout

- **Decision**: nothing extra. The OUT-010 cover sits above any visual in the output slot, so a visual
  switch while blacked out stays black; restore fades in whatever the slot then holds (the active
  cue). A coordinator test checks `isOutputBlack` after a step during blackout.

## SHOW-001-D7 — Keyboard

- **Decision**: four zero-size buttons in the visualizer (outside the auto-hiding controls) with
  `.keyboardShortcut(.rightArrow/.pageDown/.leftArrow/.pageUp, modifiers: [])`, present when the show
  has cues; hidden from accessibility (the visible row carries VoiceOver). Presentation clickers send
  Page Down/Up or arrows. B stays SHOW-014's.
- **Alternatives**: Space (activates the focused button under Full Keyboard Access); `UIKeyCommand`
  subclassing (more code).

## SHOW-001-D8 — Determinism proof

- **Decision**: a table-driven test of 18 steps over five cues and five scenes, run twice from fresh
  states, compares position and scene ID at each step; a seeded (SplitMix64, fixed seed) property test
  of 1,000 operations checks invariants and replay equality; codec round trip compares cue IDs, scene
  IDs and bytes.
