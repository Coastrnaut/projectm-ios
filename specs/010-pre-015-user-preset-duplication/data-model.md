# Data model: PRE-015 User preset duplication

Extends PRE-012's model (`specs/008-pre-012-preset-import-validation/data-model.md`). Everything
is Codable, Foundation only, in `Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/`.

## UserPreset (extended)

| Field | Type | New | Rule |
|---|---|---|---|
| id | `user/<uuid>` | | Permanent; a copy gets a new one (R3). |
| name | String | | 1-120 characters; copies: "<original> copy[ N]". |
| author | String | | Copies: the bundled preset's author. |
| originalFileName | String | | Copies: the bundled file's name (display only). |
| sha256, blobHash, byteCount | | | Always describe the **current** text; change on an edit (R14). |
| importedAt | Date | | Copies: the time of duplication. |
| state, provenOnScreen, quarantine, warnings | | | As PRE-012. An edit sets `provenOnScreen = false` and new warnings. |
| license | PresetLicenseMetadata | | `origin` is `userImport` or **`bundledDuplicate`**; `rightsVerified` always false. |
| duplicateOf | PresetDuplicateOrigin? | yes | Present iff `license.origin == bundledDuplicate`. |
| modifiedAt | Date? | yes | Set by the last saved text or name edit. |

## PresetDuplicateOrigin (new)

| Field | Type | Rule |
|---|---|---|
| presetID | String | The bundled id (`included/...` path id or `<pack>/<path>`), 1-300 characters. |
| name | String | The bundled preset's display name, ≤ 120. |
| packID, packTitle | String | e.g. `included`/"Included", `cream-of-the-crop`/"Cream of the Crop"; ≤ 120. |
| sha256 | hex 64 | Of the bundled bytes at copy time. |
| blobHash | hex 40 | Equal to the index's `hash` at copy time (checked, R2). |
| licenseStatement | String | The pack's `license` text verbatim, ≤ 1,000 characters. |
| requiresLibraryUnlock | Bool | The pack's `locked` flag at copy time (R8). |

## Derived state: held

`held(preset) = preset.duplicateOf?.requiresLibraryUnlock == true && !libraryUnlocked`. A held
preset is in `snapshot.needsUnlock` (not `playable`, not `pending`), `data(for:)` and
`editorText(for:)` return nil, and no trial runs for it. Quarantined copies stay in Quarantine.

## Edit check record (`edit.json`)

`{schemaVersion: 1, phase: "editCheck", presetID, candidateSHA256}`; PRE-012's `TrialRecord`
with an optional candidate hash. Present only while an edit's trial runs.

## UserPresetsFile version 2

Same document as version 1 with `schemaVersion: 2` and the optional fields above. Migration 1 →
2: set `schemaVersion` to 2. Golden fixtures: `Golden/user-presets-v1.json` (PRE-012, unchanged)
and `Golden/user-presets-v2.json` (new, with one copy).

## Outcomes

- `PresetDuplicateOutcome`: `added(UserPreset)`, `waiting(UserPreset)`,
  `quarantined(UserPreset)`, `refused(PresetDuplicateRefusal)`.
- `PresetDuplicateRefusal`: `locked`, `notPlayable`, `sourceMismatch`, `blocked`,
  `alreadyCopied(name)`, `alreadyInQuarantine(name, reason)`, `invalid(reason)`, `libraryFull`,
  `quarantineFull`, `libraryUnavailable`, `saveFailed`.
- `PresetEditOutcome`: `saved(UserPreset)`, `unchanged`, `refused(PresetEditRefusal)`.
- `PresetEditRefusal`: `notEditable`, `needsUnlock`, `emptyName`, `emptyText`, `tooLarge`,
  `blocked`, `sameAsBuiltIn(name, pack)`, `sameAsUserPreset(name)`, `invalid(reason)`,
  `checkFailed(message)`, `checkTimedOut`, `checkUnavailable`, `libraryUnavailable`,
  `saveFailed`, `changedMeanwhile`.

## State transitions added

```text
bundled ──duplicate, refused──▶ (nothing stored)
bundled ──duplicate ok──▶ pending ──(PRE-012 trial)──▶ playable | quarantined | pending
playable ──edit saved──▶ playable (new text, not proven)
playable ──edit refused / check failed / app ended during check──▶ playable (unchanged)
playable|pending (copy of a locked pack) ──entitlement lost──▶ held ──entitlement back──▶ as before
```
