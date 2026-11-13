# Data Model: ACC-002 Reduced Flash Preset Policy

## Flash risk verdict

The ordered list of rule ids that flag one preset text (research ACC-002-D2). Empty means not
flagged.

| Field | Type | Rule |
|---|---|---|
| rules | list of `toggle-driven`, `toggle-flip`, `luma-flicker` | In this order, each at most once |

Computed by `preset_flash_risk.classify(text)` (build) and `PresetFlashRisk.rules(in:)` (app); the
two agree on every fixture (ACC-002-R3).

## Index record field `flash` (PresetIndex.json)

| Field | Type | Rule |
|---|---|---|
| flash | array of rule ids, optional | Present only when the verdict is not empty; absent = not flagged (ACC-002-R13). `version` stays 1 |

`IndexedPreset.flash: [String]?`; `IndexedPreset.mayFlash` is true when it is non-empty. User
presets get the field from the in-app screen when they join the library (ACC-002-R4).

## Flash warning (app, in memory)

| Field | Type | Rule |
|---|---|---|
| preset | IndexedPreset | The flagged preset the user chose |
| scope | PresetScope | The list it was chosen from (becomes the scope on Load Anyway, FR-116) |

States: none → pending (explicit choice of a flagged preset with Reduce flashing on) → none
(Load Anyway: the preset is selected; Cancel or the browser closing: nothing loads). Never stored
(ACC-002-R12).

## Walkable members (app, derived)

The current scope's playable members, minus flagged presets while Reduce flashing is on. Next,
Previous, Random, the planned Random pick, warm-up and the launch preset use it (ACC-002-R5, R10).
The scope line's count and the lists keep showing every member.
