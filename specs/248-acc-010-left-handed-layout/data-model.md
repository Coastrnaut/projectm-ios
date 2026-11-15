# Data Model: ACC-010 Left-Handed Layout

## Left-handed controls preference (`OneHandedSetting.leftHanded`)

| Field | Type | Rules |
|---|---|---|
| key | `settings.controls.leftHanded` | UserDefaults Boolean; absent = false; written on change only (false removes the key) |

- Backed up: FILE-005 `LibrarySettingsPolicy.includedKeys`; erased with the Settings category (FILE-011).
- Removed by `-uitestResetNotice`; a launch argument (`-settings.controls.leftHanded YES`) still overrides.
- Never in scenes, cues, MIDI or OSC.

## ControlsSide (ShowControl)

`right` (default) or `left`. `ControlsSide.resolve(oneHanded: OneHandedHand?, leftHanded: Bool)`: the one-handed hand
when non-nil, else `left` if `leftHanded`, else `right` (ACC-010-R6).

## PadTarget (ShowControl)

`previousCue`, `nextCue`, `tapTempo`, `blackout`; `identifier` = UIX-005's `perfPreviousCue`, `perfNextCue`,
`perfTapTempo`, `perfBlackout` (unchanged in both sides).

## PadPlacement (ShowControl)

| Field | Meaning |
|---|---|
| `rows` | Bar: one row; grid: two rows, left to right (research ACC-010-D3) |
| `leadingColumn`, `trailingColumn` | Side columns, top to bottom |
| `cueReadoutLeading` | The cue readout is on the left (right-handed) or right (left-handed); the tempo readout takes the other side |

`PerformanceLayout.targetFrames(width:height:side:readoutHeight:)` → one `OneHandedLayout.Rect` per target, in
safe-area coordinates.
