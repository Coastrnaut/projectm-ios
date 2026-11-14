# Contract: Library integrity (PRE-018)

## Package API (PresetLibrary)
- `PresetIntegrityScanner.scan(inventory:references:isKnownPreset:userPresetsAvailable:limits:) -> PresetIntegrityReport` — pure, deterministic.
- `UserPresetLibrary.integrityInventory(limits:) -> (entries, incomplete, available)` — reads, never writes.
- `UserPresetLibrary.relink(_ id:, with data:) -> PresetRelinkOutcome` (`.restored`, `.checksumMismatch`, `.notMissing`, `.unknownPreset`, `.saveFailed`, `.unavailable`).
- `UserPresetLibrary.quarantineByUser(_ id:, detail:) -> Bool`.
- `RecentPresetHistory.removing(_ ids: Set<String>) -> RecentPresetHistory`.

## Words (exact)
| Kind | Title | Suggestion | Actions |
|---|---|---|---|
| missingTexture | "<name> uses a missing texture" | "It uses the texture “X”, which the app does not have. The app cannot import textures, so a blank texture is drawn instead. Keep it as it is, move it to Quarantine, or remove it." | Move to Quarantine, Remove Preset |
| danglingReference | "<Store> names a preset that no longer exists" | "<store> entry for “<ID>” points to nothing. Remove it." | Remove from Favorites / Remove Tag Entries / Remove Adjustments / Remove from Collection / Remove from Recently Played |
| missingFile | "<name>: file missing or damaged" | "The stored file of this preset is missing or damaged, so it cannot play. Re-import the original .milk file (it must be the same file), restore it from the library, or remove the preset." | Re-import…, Restore from Library (when possible), Remove Preset |
| unparsable | "<name> no longer passes the checks" | "<reason> Move it to Quarantine so it is never played, or remove it." | Move to Quarantine, Remove Preset |

Results (library lane): "No problems found." · "Found N problems." (+ " The check was incomplete." when
bounded) · "Removed N broken references." · "Restored “name”." · "That file is not the same preset.
Nothing was changed." · "Moved “name” to Quarantine." · "Removed “name”."

## UI
My Presets → row `libraryCheckLink` "Check Library" → screen "Library Check": button `checkLibrary`,
status `libraryCheckResult` ("Not checked yet." initially), rows `integrityIssue:<kind>:<presetID>`
(one accessibility element; fixes as buttons and named actions), button `fixAllSafe` (only with dangling
issues). Remove Preset and Move to Quarantine confirm first.

## DEBUG
`-uitestBrokenLibrary` (with `-uitestResetNotice`): seeds one issue of every kind and store.
