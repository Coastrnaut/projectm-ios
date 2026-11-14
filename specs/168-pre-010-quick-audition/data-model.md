# Data Model: PRE-010 Preset Quick Audition

Nothing is stored. One in-memory value on `PresetCoordinator`:

## PresetAudition

| Field | Type | Meaning |
|---|---|---|
| `original` | `IndexedPreset?` | The committed preset when the first preview started; Cancel's target. |
| `showing` | `IndexedPreset?` | The previewed preset now on screen; nil until a preview load succeeded. |
| `loading` | `IndexedPreset?` | A preview whose load is in flight (Keep is disabled meanwhile). |
| `scope` | `PresetScope` | The list the shown preview came from; Keep's scope (FR-116). |
| `notice` | `String?` | "<name> could not be previewed." after a failed preview. |

States: none (`audition == nil`) → started by `preview` → `showing` set on success / `notice` set on
failure → ended by Keep, Cancel, browser close or a committed selection (`audition = nil`).

Derived: `onScreen = audition?.showing ?? current`; `isPreviewing = audition?.showing != nil`.
