# Data Model: MOD-013 Modulation Serialization

## ModulationIDMigrations (ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| `formatVersion` (static) | Int = 1 | The table's own format |
| `rules` | `[Rule]` | Append-only, `since` non-decreasing |
| `version` | Int | Largest `since`; 0 when empty |

`Rule`: `from: String`, `change: .renamed(to: String) | .retired`, `since: Int` (≥ 1).
Kind: `audio.`-prefixed IDs are audio feature IDs, all others parameter IDs. Parameter IDs use MOD-001
syntax; audio IDs are `audio.` followed by dot-separated segments of ASCII letters and digits.

`ModulationIDResolution`: `.unchanged`, `.renamed(to: String, chain: [String])`,
`.retired(chain: [String])`; `chain` lists every ID from the original to the end.

## ParameterRegistry (changed)

Adds `migrations: ModulationIDMigrations` (default empty), checked at init (problems
`migrationFromRegistered`, `migrationFromNotRetired`, `migrationTargetUnknown`), and
`resolveParameter(_:)`, `resolveAudioFeature(_:)`.

## SceneFormat (changed / new)

- `SceneBinding.sourceID: String` (stored; `source: AudioFeatureSource?` derived).
- `SceneNodeRef`: `.audio(String)`, `.parameter(ParameterID)`, `.generator(String)`.
- `SceneConnection`: `source`, `target: SceneNodeRef`, `input: String`; `edge: ModulationEdge?`.
- `SceneModulation.connections: [SceneConnection]`.
- `SceneModulationOutcome`: `restored`, `rewritten`, `dropped`, `orphaned`, `rejected`.
- `SceneModulationReport.Entry`: `path`, `outcome`, `written` (edge text as stored), `applied`
  (edge text as applied, for restored and rewritten), `reason`.
- `SceneModulationPreserved`: `bindings: [SceneBinding]`, `connections: [SceneConnection]`.
- `SceneModulationRestore`: `bindings: [AudioFeatureBinding]`, `expressions`, `graph: ModulationGraph`
  (declared generators + applied connections), `preserved`, `report`, `issues`.
- `SceneLiveState`: `modulation` becomes a `ModulationGraph`; adds `preserved`.
  `SceneLoadResult` adds `modulationReport`.

## Edge lifecycle

```text
stored ──resolve IDs──▶ malformed? ─▶ rejected (preserved)
                        retired?   ─▶ dropped  (not re-saved)
                        unknown?   ─▶ orphaned (preserved)
                        invalid?   ─▶ rejected (preserved)
                        changed?   ─▶ rewritten (live, re-saved with new IDs)
                        else       ─▶ restored  (live)
```
