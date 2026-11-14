# Contract: Import conflict resolver (FILE-004)

## C1. Preset planner

`PresetArchiveImportPlanner.plan(archive:library:context:policy:overrides:)` — pure. FILE-003's
classification order is unchanged. For a conflict the effective choice is `overrides[incomingID] ??
policy`:
- `skip` → no action.
- `keepBoth` → FILE-003 (derived id when taken, copy name when taken).
- `replace` → target: ID conflict → the library preset with that id; name conflict → the first
  library preset (library order, not quarantined) with that name (any case). No library target or a
  target already replaced → Keep both with `fellBack = true`. Action: id = target id, name = incoming
  name unless taken (any case) by a library preset other than the target or by an earlier planned
  name → copy name; `replacesID` = target id. Replace does not use capacity.

## C2. Preset library

- `planArchiveImport(_:policy:overrides:)`.
- `installArchive(_:plan:)`: re-plan with the plan's policy and overrides; `!=` → `.changed`; a held
  replace target → `.refused(nothingInstalled(...))`; else `UserPresetStore.commitImport`.
- Store `commitImport(adding:replacing:)`: all or nothing before the index write; old texts deleted
  after; leftovers finished at load.

## C3. Scene planner and installer (ShowStorage)

- `ShowSceneImportPlanner.plan(incoming:stored:show:libraryDigest:defaultChoice:overrides:)` — pure.
  Per incoming scene in order: same id and same canonical bytes as the stored file → `identical`;
  id stored or planned earlier → `idConflict`; else `new`. Effective choice for a conflict:
  `overrides[id] ?? default`. Keep both → derived scene id (D2), name copy rule, a derived cue;
  Replace (stored target, not replaced earlier) → same id, incoming name, no cue; otherwise Keep both
  with `fellBack`. New → incoming id and name, a derived cue.
- `ShowStore.planSceneImport(_:defaultChoice:overrides:)` reads only.
- `ShowStore.installImportedScenes(_:plan:)` → `ShowSceneImportOutcome` (D4 steps; fault hook on each
  file operation).
- `ShowStore.recoverInterruptedSceneImport()` — call before `load()`.

## C4. App

- Preview identifiers (FILE-003 C4) plus `archiveChoice:<incoming name>:<skip|keepBoth|replace>` and
  the outcome line `archiveOutcome:<incoming name>`.
- DEBUG `-uitestPresetArchiveConflictFixture YES`: previews a two-preset archive whose first preset
  is named "Seeded Lantern" (the UI test's seeded preset) with another text.
- Announcement after install: `PresetArchiveText.installed(_:replaced:)` on the `library` lane.
