# Contract: Reduce flashing preset policy (app)

`PresetCoordinator` (main actor). "Policy on" means `AppSettings.reduceFlashing` is true.

| Member | Behavior |
|---|---|
| `isFlagged(_ preset) -> Bool` | `reduceFlashing && preset.mayFlash` |
| `walkable: [IndexedPreset]` | `members` without flagged presets (equal to `members` with the policy off) |
| `next()`, `previous()`, `random()` | Walk `walkable`. Policy on, members not empty, walkable empty: nothing loads, `failureMessage = "Every preset here may flash."` (ACC-002-R9) |
| planned Random and warm-up | Chosen from `walkable` (ACC-002-R5) |
| `initialPreset` | The last preset if playable and not flagged, else `walkable.first` (ACC-002-R10) |
| `choose(_:from:)` | Locked: purchase first (unchanged). Flagged: `flashWarning = FlashWarning(preset, scope)`, nothing loads (ACC-002-R6). Else: select (unchanged) |
| `confirmFlashWarning()` | Selects the warned preset in its scope; clears the warning |
| `cancelFlashWarning()` | Clears the warning; nothing loads |
| after a purchase | The pending locked preset goes through `choose` (so it is warned if flagged) |

Browser (`PresetBrowserView`, on the navigation stack so it shows over every list):

- Row of a flagged preset, policy on: `exclamationmark.triangle` symbol and the text "May flash"
  (caption, secondary); accessibility label gains ", may flash"; identifier
  `mayFlash:<name>` on the mark.
- Alert titled "May flash", message "“<name>” may contain fast flashing. Reduce flashing still
  limits flashes while it plays.", buttons "Load Anyway" (`loadFlaggedAnyway`) and "Cancel"
  (`cancelFlagged`, cancel role). Load Anyway loads, then closes the browser; Cancel keeps the
  browser open. The browser stays open while the warning is pending.

Strings live as `static let` on `PresetCoordinator` so tests read the same text.
