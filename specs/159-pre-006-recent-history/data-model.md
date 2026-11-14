# Data Model: PRE-006 Recently Played History

## RecentPresetHistory (PresetLibrary, value type)

| Field | Type | Rules |
|---|---|---|
| `ids` | `[String]` | Most recent first; no empty or duplicate IDs; at most `capacity` (50). |

- `record(id)`: ignores an empty ID; removes `id` where it is, inserts it at index 0, drops entries past 50.
- `clear()`: `ids = []`.
- `init(storedValue: Any?)`: lenient (non-array → empty; non-strings, empty and later duplicates dropped; trimmed to 50).

## RecentPresetDwell (PresetLibrary, value type)

| Field | Type | Rules |
|---|---|---|
| `candidate` | `(id: String, since: Double)?` | The preset loaded last and when (monotonic seconds). |

- `threshold` = 3.0 s.
- `shown(id, at:)`: replaces the candidate.
- `deadline`: `since + threshold` or nil.
- `due(at now:) -> String?`: when `now >= deadline`, returns the ID and clears the candidate; else nil.
- `cancel()`: clears the candidate.

States: idle → (shown) → waiting → (due at ≥ 3 s) → idle with the ID recorded; waiting → (shown other) →
waiting for the other; waiting → (cancel: off or clear) → idle.

## Stored keys (UserDefaults)

| Key | Type | Default | FILE-005 | FILE-011 |
|---|---|---|---|---|
| `recentPresets` | `[String]` | absent = empty | excluded | "Collections, tags, favorites and history" |
| `settings.recentPresets.enabled` | `Bool` | absent = off (opt-in) | included | Settings |
