# Data Model: OSC-010 OSC Schema Export

Nothing is stored. In-memory values only.

## OSCSchemaRow (package)

| Field | From | Example |
|---|---|---|
| address | route | `/projectm/param/glow.intensity` |
| parameterID | route | `effect.bloom.intensity` |
| displayName | app name helper (MIDI-003 `name`) | `Glow intensity` |
| arguments | constant | `one number (f, i, h or d)` |
| inputRange | scale: normalized → `0…1`; raw → value range | `0…1` |
| valueRange | descriptor continuous min…max | `0…2` |
| unit | descriptor unit | `none`, `fraction 0-1`, `fraction of output`, `seconds`, `per second`, `degrees`, `count` |
| origin | route origin | `test`, `standard`, `built-in alias`, `your alias` |
| enabled | not in disabled set | `on` / `off` |

Validation: one row per table route (addresses unique by OSC-003-R1); a route whose descriptor is missing keeps
its address and ID with ranges `unknown` (never expected; covered by a test).

## OSCSchemaDocument

Header (title, app version, `Exported: <UTC>`, route count, the value rule sentence), then the table. File name
`projectM-osc-routes-<YYYYMMDD-hhmmss>Z.md`.

## OSCSchemaExportCoordinator (app, memory only)

`request` (share copy URL + id, nil when no sheet), `notice`, `lastOutcome`, DEBUG `lastText`. States: idle →
offered (copy exists) → idle (copy deleted) on any outcome.
