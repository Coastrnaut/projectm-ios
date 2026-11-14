# Contract: Scene HUD (UIX-013)

## C1 — Texts (`SceneHUDContent.make`)

| State | current | next |
|---|---|---|
| no cues | `No cues` | — (absent) |
| standby, 5 cues | `Standby · 5 cues` | `Next: <cue 1 label>` |
| cue 2 of 5 | `Cue 2 of 5 · <label>` | `Next: <cue 3 label>` |
| last cue | `Cue 5 of 5 · <label>` | `Next: End of show` |
| SHOW-002 countdown "Next in 0:12" | unchanged | `… · in 0:12` (or `… · in 0:12, held`) |
| SHOW-003 queued text | unchanged | the queued text verbatim |

| Tempo readout | tempo | spoken |
|---|---|---|
| manual(120) | `120 BPM · Tap` | `120 BPM from tap` |
| stable(120) | `120 BPM · Estimated` | `120 BPM, estimated` |
| uncertain(118) | `≈118 BPM · Estimated` | `About 118 BPM, estimated` |
| searching | `— BPM · None` | `No tempo` |

`source` = the FR-042 indicator text.

## C2 — Accessibility

Container identifier `sceneHUD` (label "Show HUD", children contained). Lines: `hudCurrentCue` (label "Current
cue"), `hudNextCue` ("Next cue"), `hudTempo` ("Tempo"), `hudSource` ("Audio source"); each a static text with
the line's spoken value. No announcements.

## C3 — Placement

First element of the visualizer's top status stack, max width 360 pt, inside the safe area, UIX-005's reserved
insets and UIX-007's output pane. Never contains the screen's centre.

## C4 — Exclusion

The HUD exists only in the device window's SwiftUI hierarchy. The external display window, the rehearsal
preview, recordings and saved frames are the visual alone; with the HUD on they are pixel-identical to HUD off.

## C5 — Preference

`settings.visualizer.sceneHUD` (Bool). Settings → Performance → "Show HUD" (`sceneHUDToggle`). FILE-005
included key; FILE-011 Settings erase; removed by `-uitestResetNotice`.
