# Research: SCN-003 Scene Duplicate and Rename

No NEEDS CLARIFICATION remained after `/speckit-clarify`. Decisions:

## SCN-003-D1: Where the operations live

- **Decision**: `SceneDocument.duplicated(newID:name:)`, `renamed(to:)`, `normalizedName(_:)` and
  `copyName(_:)` in SceneFormat; show-level actions in ShowStorage (`ShowStore`) and the app's
  `ShowCoordinator`.
- **Rationale**: the library rows (SCN-004 to SCN-006) need the same rules without the show; the
  package builds and tests on Linux.
- **Alternatives**: app-only code (not reusable, not Linux-tested).

## SCN-003-D2: What "kept exactly" means

- **Decision**: the copy's canonical bytes, with `id` and `name` set back to the original's, equal the
  original's canonical bytes (`encoded()`); a rename likewise. Implemented by copying the value and
  setting only the two fields, so unknown content (`extra` at every level) is carried untouched.
- **Rationale**: byte equality is the strongest check SCN-001 offers (C3 semantic equality is equality
  of the canonical JSON) and catches any accidental change.
- **Alternatives**: comparing live states only (misses unknown content).

## SCN-003-D3: Name rule

- **Decision**: trim white space and newlines at both ends; then 1…120 characters (grapheme clusters)
  and no Unicode control scalars (category Cc). One function `isValidName(_:)` is used by both the
  validator and the editing API. The trimmed text is stored.
- **Rationale**: matches the SCN-001 clarification (the validator trims to measure and rejects
  control characters); storing the trimmed text avoids invisible differences.

## SCN-003-D4: IDs

- **Decision**: `duplicated` requires a canonical uppercase UUID different from the original's
  (`SceneEditError.invalidSceneID`, `.sameSceneID`). Callers pass `UUID().uuidString`; tests pass
  fixed IDs. `ShowStore.duplicateScene` also refuses an ID that already has a file
  (`.sceneIDTaken`), so a duplicate never overwrites another scene.
- **Rationale**: deterministic tests; no collision can silently replace a scene.

## SCN-003-D5: Media references

- **Decision**: share by store ID; `ShowStore.referencedMediaIDs()` reads every stored scene and
  returns the photo and video store IDs (`StoredMediaReferences`). No count is stored.
- **Rationale**: the app holds one photo and one video; scenes already refer to them by ID; a computed
  set cannot drift. Removing a scene file (SHOW-001's unreferenced-scene cleanup) never deletes media.
  FILE-010 must not delete media (caches only); FILE-011 must consult this set (recorded in ADR-0033).

## SCN-003-D6: Show placement

- **Decision**: `ShowCueList.insert(sceneID:label:after:cueID:)` inserts right after the source cue;
  the position (a cue ID) is unaffected. Label "<label> copy" via `copyLabel(_:)`, shortened to 80.
- **Alternatives**: append at the end (copy far from its source).

## SCN-003-D7: Showing scene names in the editor

- **Decision**: `ShowCoordinator` keeps `sceneNames: [String: String]` (scene ID → name) filled at
  launch from the stored scenes and updated by add, duplicate and rename. A row shows "Scene: <name>"
  and VoiceOver appends ", scene <name>" only when the name differs from the label, so SHOW-001's
  existing row values are unchanged.
