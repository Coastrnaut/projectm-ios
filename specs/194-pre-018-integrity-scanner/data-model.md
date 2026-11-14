# Data model: PRE-018 Preset integrity scanner

Nothing is persisted by this feature. One quarantine reason code is added.

## PresetIntegrityIssue
- `kind`: `missingTexture` | `danglingReference` | `missingFile` | `unparsable`
- `presetID`: String; `presetName`: String? (from the record)
- `detail`: texture name (missingTexture), unparsable reason message, or nil
- `store`: `PresetReferenceStore?` — favorites | tags | overrides | collections | recents (dangling only)
- `collectionID`, `collectionName`: String? (dangling collection entry)
- `id`: stable key `"<kind>|<store>|<collectionID>|<presetID>|<detail>"` (uniqueness = R5)
- `actions`: [PresetIntegrityAction] — `removeReference`, `relinkFile`, `restoreFromLibrary`,
  `moveToQuarantine`, `removePreset`; `isSafe` true only for `removeReference`
- `title`, `suggestion`: words (contract)

## PresetReferenceSnapshot
favorites [String]; tags [String] (tagged preset IDs); overrides [String]; collections [(id, name,
presetIDs)]; recents [String].

## UserPresetIntegrityEntry (inventory)
record `UserPreset`; `file`: ok | missing (absent/unreadable/size/hash); `missingTextures` [String];
`rejection` PresetQuarantineReason?; `restorableFromLibrary` Bool (duplicate, unedited).

## PresetIntegrityReport
issues (sorted kind, name/ID, detail); presetsChecked; referencesChecked; incomplete Bool;
userPresetsUnavailable Bool. Derived: `danglingCount`, `isClean`.

## PresetIntegrityLimits
maxRecords 1,200; maxTextBytes 128 MiB; maxReferences 60,000; maxIssues 500; maxTexturesPerPreset 8.

## Quarantine reason
`PresetQuarantineReason.Kind.movedByUser` ("You moved this preset to Quarantine." + detail).
