# Data Model: FX-020 Effect Chain Presets

## OutputEffectKind (Compositor)

| Case | Stored kind | Effect |
|---|---|---|
| `trails` | `fx.trails` | FX-009 Trails |
| `grade` | `fx.grade` | FX-003 Color with FX-004 hue |

## FixedOutputStage (Compositor)

`flashGuard` (`fx.flashGuard`), `toneMap` (`fx.toneMap`): always after every `OutputEffectKind`, in that
order of application: tone map inside the output, guard gain last.

## OutputEffectOrder (Compositor)

- `effects: [OutputEffectKind]`: each kind exactly once. `init(_:)` drops repeats and appends missing kinds
  in standard order. `.standard` = `[trails, grade]`. `gradeBeforeTrails: Bool`.
- `moving(from: IndexSet, to: Int)` (SwiftUI move semantics), `storageText` (`fx.trails,fx.grade`),
  `init(storageText:)` (unknown tokens ignored).

## SceneEffectEntry (SceneFormat)

| Field | JSON | Rule |
|---|---|---|
| `kind` | `"kind"`: string | required |
| `enabled` | `"enabled"`: bool | absent → true (written always) |
| `parameters` | `"parameters"`: object | absent → empty; values kept as written |
| `extra` | other fields | kept verbatim |

`SceneDocument.effects: [SceneEffectEntry]?` — nil: field absent.

## Known parameters

| Kind | Name | Range | Default |
|---|---|---|---|
| `fx.grade` | `temperature` | −1…1 | 0 |
| | `lift` | −0.1…0.1 | 0 |
| | `gamma` | 0.5…2 | 1 |
| | `gain` | 0.5…2 | 1 |
| | `saturation` | 0…2 | 1 |
| | `hue` | −180…180 | 0 |
| `fx.trails` | `halfLife` | 0.05…0.50 s | 0.20 |

## SceneEffectSettings (SceneFormat)

- `order: OutputEffectOrder`
- `grade: ColorGrade?`, `gradeEnabled: Bool?` (nil: no `fx.grade` entry)
- `trails: MotionFeedback?` (nil: no `fx.trails` entry; `isEnabled` = the entry's flag)
- `init(entries:)` → settings; `issues(entries:)` → warnings; `entries(over:)` → stored list.
- `isDefault`: standard order, Trails off, Color on and neutral.

## EffectChainPreset / EffectChainPresetList (SceneFormat)

- Preset: `name` (1…60 characters after trimming), `effects: [SceneEffectEntry]`.
- List: ≤ 32, unique names (case-insensitive); `saving(name:effects:)` replaces in place or appends
  (refused when full), `removing(name:)`, `encoded() -> [UInt8]`, `decode(_:) -> list?`.

## App settings (UserDefaults)

| Key | Type | Absent |
|---|---|---|
| `settings.effectChain.order` | String | standard order |
| `settings.effectChain.presets` | Data | no presets |
| `settings.colorGrade.enabled` | Bool | on |
