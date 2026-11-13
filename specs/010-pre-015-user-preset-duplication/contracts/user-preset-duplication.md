# Contract: user preset duplication and editing (PRE-015)

Extends `specs/008-pre-012-preset-import-validation/contracts/user-presets.md`.

## `UserPresetLibrary` (actor), new calls

| Call | Result |
|---|---|
| `setLibraryUnlocked(_ unlocked: Bool)` | Holds or releases copies of locked-pack presets (R8). Default false. |
| `duplicate(_ source: BundledPresetSource, contents: Data) async -> PresetDuplicateOutcome` | R2-R7. Never throws. |
| `editorText(for id: String) -> PresetEditorText?` | The current text of a playable, not held preset, decoded (UTF-8, else Latin-1 with `isUTF8 == false`); nil otherwise. |
| `edit(_ id: String, name: String, text: String?, expectedSHA256: String) async -> PresetEditOutcome` | R11-R15. `text` nil: the text is unchanged (rename only). `expectedSHA256`: the text the editor opened; another stored text → `changedMeanwhile`. Never throws. |
| `takeEditNotices() -> [String]` | Names of presets whose edit was discarded because the app ended during its check (R13); returned once. |

`BundledPresetSource`: `id`, `name`, `author`, `fileName`, `packID`, `packTitle`,
`licenseStatement`, `blobHash` (the index hash), `requiresLibraryUnlock`.

`UserPresetSnapshot` gains `needsUnlock: [UserPreset]` (alphabetical).

Order of checks in `duplicate`: store unavailable → locked → hash mismatch → takedown → same text
already stored (in My Presets or Quarantine) → validator rejection → limit → store → trial.

Order of checks in `edit`: store unavailable → not editable (unknown, not playable) → held →
name → empty → size → unchanged (name-only rename or `unchanged`) → takedown → built-in other
than own source → other user preset → validator → trial busy/unavailable → record → trial →
preset changed meanwhile → replace.

## `UserPresetStore`, new calls

| Call | Result |
|---|---|
| `replaceContents(_ id, with: UserPreset, contents: Data) throws` | Writes the new body, saves the record, deletes the old body; on record failure removes the new body; memory unchanged on any failure. The new record must keep the id and be well formed; its hashes must match `contents`. |
| `writeRecord(.editCheck, presetID:, candidateSHA256:)` | As PRE-012's records. |
| path guard | Every create, write, move and delete targets a standardized path under `directory`, or the call fails with `saveFailed` and nothing is touched. `fileOperationObserver` (internal) sees each operation. |

## Invariants (added to PRE-012's)

6. `data(for:)`, `editorText(for:)` return nil for a held preset.
7. A refused or failing `edit` leaves every byte under the directory unchanged (except a
   transient `edit.json`, removed before the call returns).
8. No call writes, moves or deletes a path outside the directory.
9. A record is never left naming a missing body: the body is written before the record and
   deleted after it.

## App

- `RendererPresetLoader.bundledData(for: IndexedPreset) throws -> Data` (Included: bundle file;
  pack: archive). Read-only.
- `UserPresetsCoordinator`: `duplicate(_:)`, `editorText(for:)`, `saveEdit(_:name:text:)`,
  `needsUnlock`, `duplicateMessage`, `editNotice`.
- `UserPresetGuarding` gains `libraryUnlockChanged(_:) async`, called by
  `PresetCoordinator.setUnlocked` before the scope changes.
- Accessibility identifiers: `duplicatePreset` (context menu item), `duplicateCurrent`
  (controls), `editUserPreset`, `presetEditor`, `presetEditorName`, `presetEditorText`,
  `presetEditorSave`, `presetEditorCancel`, `presetEditorError`, `presetEditorEncodingNote`,
  `needsUnlockSection`, `heldPreset:<name>`, `presetOrigin`; the discard question is an alert
  with the buttons "Discard Changes" and "Keep Editing".
