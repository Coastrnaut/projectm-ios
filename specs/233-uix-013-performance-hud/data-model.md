# Data Model: UIX-013 Scene Performance HUD

## SceneHUDSetting (preference)

| Field | Type | Rule |
|---|---|---|
| `isEnabled` | Bool | key `settings.visualizer.sceneHUD`; absent → false; written on change only |

## SceneHUDContent (derived, not stored)

| Field | Type | Source |
|---|---|---|
| `current` | String | `ShowCueList`: "Cue n of m · label", "Standby · m cues" or "No cues" |
| `next` | String? | next cue label ("Next: Build"), "Next: End of show" on the last cue, nil without cues; SHOW-002 countdown appended (" · in 0:12"); SHOW-003 queued text replaces it |
| `tempo` | String | `TempoReadout` → "120 BPM · Tap", "≈118 BPM · Estimated", "— BPM · None" |
| `source` | String | FR-042 `sourceStatusText`, verbatim |
| spoken values | String | one per line, for VoiceOver (contracts/scene-hud.md) |

Pure function of its inputs; recomputed on every SwiftUI update (all inputs are `@Observable`).
