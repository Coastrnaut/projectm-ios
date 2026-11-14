# Contract: ACC-009 One-Handed Layout

## C1 Geometry (ShowControl, pure)

`OneHandedLayout(width:height:hand:baseTarget:padTarget:actions:)`:
- zone per research D1; margin 8 pt, spacing 8 pt;
- the pad group (in `CriticalAction.allCases` order) is laid first at `padTarget ?? base`, then the main group at `base`, rows from the zone's bottom upward, each aligned to the chosen edge, reading order inside a row;
- if the stack is taller than the zone, `base` shrinks by 4 pt down to 44; `fits` reports whether every frame lies in the zone;
- `reservedInsets`: portrait-shaped → bottom = height − (top of the highest row − margin); landscape-shaped → the chosen side = width − the farthest frame edge + margin; zero when no action is placed;
- `OneHandedLayout.baseTarget(scaled:)` clamps to 44…56.

## C2 Action sets

`CriticalAction.standard(ctx)`: stop, pauseResume, settings, blackout, tapTempo always; previous, next, random, presets unless `alternateVisual`; cuePrevious, cueNext when `hasCues || padOn`.
`CriticalAction.displayed(ctx)`: with `controlsVisible`: `standard(ctx)`; without: the pad group if `padOn`, else nothing.

## C3 App

- Settings → Performance, after Show HUD, iPhone only: "One-handed layout" rows Off / Left hand / Right hand (`oneHanded.off`, `oneHanded.left`, `oneHanded.right`, selected row has the `.isSelected` trait); footer. `-uitestSettingsSection oneHanded` anchors it.
- Active: the card leaves out the moved actions; `OneHandedControlsLayer` (identifier `oneHandedControls`) draws them with the standard identifiers; with the pad on, the pad's targets keep `perf*` and the B key.
- DEBUG `-uitestDiagnostics`: the layer exposes `oneHandedZone` with value "x,y,w,h" (window coordinates) for the UI tests.
