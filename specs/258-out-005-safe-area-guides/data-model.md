# Data Model: OUT-005 Safe-Area Guides

## SafeAreaGuideChoice (PresentationLifecycle)

| Field | Type | Rule |
|---|---|---|
| actionPercent | Int | clamped 80…100, default 93 |
| titlePercent | Int | clamped 70…100, default 90; drawn at min(title, action) |
| showsCentreCross | Bool | default false |

## SafeAreaGuideRect

x, y, width, height (Double, view points).

## SafeAreaGuideGeometry

| Field | Meaning |
|---|---|
| output | the output frame (whole view, or the external display's shape fitted and centred) |
| actionSafe, titleSafe | centred insets of `output` at the choice's fractions |
| crossArm | half-length of each cross stroke (4 % of output's shorter side), nil when the cross is off |

## SafeAreaGuideSetting (app, UserDefaults)

| Key | Type | Default |
|---|---|---|
| `settings.visualizer.guides` | Bool | false |
| `settings.visualizer.guides.actionSafe` | Int | 93 |
| `settings.visualizer.guides.titleSafe` | Int | 90 |
| `settings.visualizer.guides.centreCross` | Bool | false |

Absent reads the default; written on change only; included in the library backup; erased with
Settings; removed by `-uitestResetNotice`; in `ALLOWED_KEYS`.
