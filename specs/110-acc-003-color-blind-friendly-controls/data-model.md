# Data Model: ACC-003 Color-blind Friendly Controls

## StatusCue (value)

| Field | Type | Rule |
|---|---|---|
| symbol | String | an existing SF Symbol; unique within its group (ACC-003-R1) |
| text | String | the words already shown for this state (unchanged texts) |
| role | StatusColorRole | `neutral`, `positive`, `caution`, `critical`; supplementary only |

## StatusCueGroup (value)

| Field | Type | Rule |
|---|---|---|
| id | String | `source`, `recording`, `camera`, `blackout`, `osc`, `tempo` |
| states | [(name: String, cue: StatusCue)] | every pair must be distinguishable in grayscale (ACC-003-S1) |

`StatusCueCatalog.groups` lists them; the grayscale test iterates it.

## StatusColorRole → InterfacePalette

Four roles plus `accent`, each with light, dark, light-increased and dark-increased sRGB values
(research D2). `neutral` resolves to the primary label colour.

## StatusAppearance (environment value)

| Field | Type | Source |
|---|---|---|
| increasedContrast | Bool | `colorSchemeContrast == .increased` (DEBUG: trait override) |
| differentiateWithoutColor | Bool | `accessibilityDifferentiateWithoutColor` (DEBUG: `-uitestDifferentiateWithoutColor YES`) |

## Setting

`settings.visual.colorBlindSafePalette`: Bool, absent → false. When true, native spectra use
`VisualPalette.colorBlindSafe`; otherwise `.spectrum` (unchanged).
