# Data Model: SCN-015 Scene Lock Mode

## SceneLock (app, main actor, observable)

| Field | Type | Rule |
|---|---|---|
| `isLocked` | Bool | stored as `settings.scene.locked`; absent → false |
| `lastRefusal` | String? | `"Scene locked. Unlock the scene to edit."` after a refused edit |
| `refusals` | Int | count of refused edits (tests, DEBUG) |

Transitions: unlocked → locked (`lock()`, announces "Scene locked"); locked → unlocked (`unlock()` after the
confirmation, announces "Scene unlocked"). `refusesEdit()` is a no-op returning false while unlocked.

The scene document, the show file and the snapshot list are unchanged; no new scene field.
