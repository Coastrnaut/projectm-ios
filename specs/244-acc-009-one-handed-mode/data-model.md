# Data Model: ACC-009 One-Handed Performance Mode

- **OneHandedHand** (`left`, `right`): stored as its raw value under `settings.controls.oneHanded`; absent or unknown = Off.
- **CriticalAction** (11 cases): `cuePrevious`, `cueNext`, `tapTempo`, `blackout` (pad group); `previous`, `next`, `random`, `pauseResume`, `presets`, `settings`, `stop` (main group). Each has its standard identifier and, for the pad group, its pad identifier.
- **CriticalActionContext**: `hasCues`, `padOn`, `alternateVisual`, `controlsVisible`. `standard(_:)` = the set the standard layout offers with the controls shown; `displayed(_:)` = what the one-handed layout draws now (pad group always while the pad is on; everything else only with the controls).
- **OneHandedLayout**: inputs safe width and height, hand, base side, pad side (nil when the pad is off), actions. Optional `readoutHeight` (the pad's readout strip). Outputs `zone`, `frames` (action → rect, in safe-area coordinates), `fits`, `reservedInsets`, `reservedRect`, `asideRect`.
- **OneHandedSetting** (app): `hand: OneHandedHand?`, `isPhone`, `isActive = hand != nil && isPhone`.
