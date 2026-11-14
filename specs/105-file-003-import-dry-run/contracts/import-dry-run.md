# Contract: Import dry run (FILE-003)

## C1. Planner (PresetLibrary)

`PresetArchiveImportPlanner.plan(archive data: Data, library: [UserPreset], context: PresetImportContext, policy: PresetArchiveConflictPolicy) -> PresetArchiveImportPlan`

- Pure: no file, default or clock access.
- A reader refusal gives `refusal = UserPresetArchiveError.message`, no entries.
- Classification order per preset (archive order): (1) same text as a quarantined file → refused `inQuarantine`; (2) same text as another library preset → `identical`; (3) blocked hash → refused `blocked`; (4) built-in hash → refused `builtIn`; (5) validator rejection → refused `failsChecks`; (6) id taken by a different preset → `idConflict`; (7) name taken (library or earlier planned, case-insensitive) → `nameConflict`; (8) `new`. Capacity: once active presets + planned installs reach 1,000, further installable entries are refused `libraryFull`.
- Install action: `new` keeps the incoming id and name; a conflict under `keepBoth` gets the D3 identifier when its id is taken (else the incoming id) and `UserPresetName.copyName` when its name is taken; under `skip` no action.

## C2. Library (actor)

- `planArchiveImport(_ data: Data, policy:) -> PresetArchiveImportPlan`: reads the store and context only. A library from a newer version gives `refusal = UserPresetText.newerFormat`-equivalent message.
- `installArchive(_ data: Data, plan:) async -> PresetArchiveInstallOutcome`: plans again; `!=` → `.changed(newPlan)` with nothing written; a plan with a refusal or nothing to install → `.refused`; otherwise `UserPresetStore.addAll`; failure → `.refused("Nothing was installed. …")` with the library byte-for-byte unchanged.

## C3. Store

`addAll(_ items: [(UserPreset, Data)]) throws`: stage → verify → move → index once; rollback on any error (D4). `load()` removes `Staging/`.

## C4. App

- `.zip` from "Import Preset…" → preview sheet `presetArchivePreview` with Install (`archiveInstall`) and Cancel (`archiveCancel`), counts `archiveCount:<kind>`, policy picker `archivePolicy`, lists `archiveConflict:<name>`, `archiveNoLicense:<name>`, `archiveRefused:<name>`, size `archiveSize`, refusal `archiveRefusal`, changed notice `archiveNotice`.
- Announcements: lane `library`, wording in the spec's Clarifications.
- DEBUG: `-uitestPresetArchiveFixture` previews a built-in fixture archive after the trials start; `libraryDigest` (list) and `archiveDigestAtPreview` (sheet) probes carry the snapshot digest.

## C5. Scene service

- `planImport(at:) async -> SceneArchiveImportPlan`: no store or default written; the temporary copy is removed.
- `importArchive(at:plan:) async throws(SceneArchiveServiceError)`: `.planChanged` when the archive bytes or current photo/video differ from the plan; else FILE-001's import, emitting the plan's steps.
