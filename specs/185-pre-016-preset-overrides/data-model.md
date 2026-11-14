# Data model: PRE-016 Preset parameter overrides

## PresetOverrideParameter (enum, allow-list)

| Case | Key in file | Label | Range | Step | Engine default |
|---|---|---|---|---|---|
| zoom | `zoom` | Zoom | 0.8 … 1.2 | 0.01 | 1 |
| rotation | `rot` | Rotation | -0.2 … 0.2 | 0.01 | 0 |
| warp | `warp` | Warp | 0 … 2 | 0.05 | 1 |
| decay | `fDecay` | Decay | 0.9 … 1 | 0.005 | 0.98 |
| waveRed | `wave_r` | Wave red | 0 … 1 | 0.01 | 1 |
| waveGreen | `wave_g` | Wave green | 0 … 1 | 0.01 | 1 |
| waveBlue | `wave_b` | Wave blue | 0 … 1 | 0.01 | 1 |
| brightness | `fGammaAdj` | Brightness | 1 … 3 | 0.05 | 2 |

`PresetOverrideParameter(key:)` matches without regard to case. `clamped(_:)` clamps then rounds to
4 decimals; non-finite → nil.

## PresetOverrideMap (value)

- `values: [String: [String: Double]]` — preset ID → canonical key → value.
- `set(_ value: Double, for key: String, preset: String) throws(PresetOverrideError) -> Double` —
  unknown key → `.unknownParameter`; non-finite → `.invalidValue`; empty or > 512-byte ID →
  `.invalidPreset`; more than 20,000 presets → `.tooManyPresets`. Returns the stored (clamped) value.
- `remove(_ key:, preset:) -> Bool`, `reset(preset:) -> Bool`, `overrides(for:) -> [String: Double]`.
- `repaired(_ raw:) -> (map, dropped)` for the lenient reader.

## Overrides document (version 1)

```json
{ "schemaVersion": 1, "overrides": { "<preset ID>": { "fDecay": 0.95, "zoom": 1.05 } } }
```

Sorted keys, unescaped slashes; equal maps → equal bytes. Max 1 MiB.

## PresetOverrideStore (class, one owner)

`map`, `availability (.available | .newerFormat(version))`, `loadNotice (.none | .unreadableSetAside |
.repaired(dropped))`, `set`, `remove`, `reset`, `prune`; each change saved before it is visible.

## State

No state machine: a preset either has an override set (non-empty) or not; reset/prune remove the set.
