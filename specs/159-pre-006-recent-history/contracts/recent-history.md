# Contract: PRE-006 recently played history

## C1 — RecentPresetsCoordinator (app, main actor)

| Member | Behavior |
|---|---|
| `ids: [String]` | The stored history, most recent first (observable). |
| `isEnabled: Bool` | The switch (observable); off by default. |
| `shown(_ id:)` | Called by `PresetCoordinator.select` after a successful load. While enabled: the dwell candidate becomes `id` and a check is scheduled `threshold` later. Disabled: nothing. |
| `checkDwell()` | Records the candidate when due (saves `recentPresets` at once). |
| `setEnabled(_:)` | Saves the switch; off removes the history, cancels the candidate and announces "Recently played history is off and was cleared."; on announces "Recently played history is on." |
| `clear()` | Removes `recentPresets` only, cancels the candidate, announces "Recently played history cleared." |
| `listing(in: PresetLibrary?) -> [IndexedPreset]` | The IDs the library lists, in history order. |

Never touches `favorites`, `lastPresetID`, `settings.presetScope`, collections or tags.

## C2 — UI identifiers

| Identifier | Element |
|---|---|
| `node:recent` | Browser home row "Recently Played" (label "Recently Played, N presets"). |
| `recentList` | The Recent list. |
| `recentEmpty` | Empty-state text (`No recently played presets yet.` / `Recently played history is off. Turn on Remember Recently Played in Settings to keep a list.`). |
| `recentClear` | Clear History button (list and Settings). |
| (alert) | The destructive alert button "Clear History" (found by its label: SwiftUI gives an alert action's identifier to every action). |
| `recentToggle` | Settings switch "Remember Recently Played". |

## C3 — Backup and erase

- `LibrarySettingsPolicy.recentPresetsKey` = `recentPresets` ∈ `excludedKeys`.
- `LibrarySettingsPolicy.recentPresetsEnabledKey` = `settings.recentPresets.enabled` ∈ `includedKeys`.
- `LibraryErasePolicy.settingKeys(.collections)` = [`favorites`, `recentPresets`]; title "Collections, tags, favorites and history"; inventory count adds the history's entries.
