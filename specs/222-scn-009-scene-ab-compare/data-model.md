# Data Model: SCN-009 Scene A/B Compare

No persisted data (R10). In-memory only:

## SceneCompareChoice
- `.current` — the scene as it was when Compare started (side A only)
- `.snapshot(index: Int)` — a usable snapshot of the current scene

## SceneCompareSide
- `.a`, `.b`

## SceneCompareSession
| Field | Meaning |
|---|---|
| `baseline: SceneInputs` | live inputs at start (after the flush) |
| `baselineValues: [ParameterID: ParameterValue]` | the app-held parameter values at start |
| `a`, `b: SceneCompareChoice` | the chosen sides (`b` is always a snapshot; `a != b`) |
| `aName`, `bName: String` | "Current scene" or the snapshot's name |
| `aValues`, `bValues` | baseline overlaid with the side's usable snapshot values (D4) |
| `shown: SceneCompareSide` | the side on the output |

State transitions: idle → (start; refused while locked or comparing) → comparing(shown A) ⇄ comparing(shown B)
→ keep(side) [refused while locked] / cancel / abandon (history restart) → idle.
