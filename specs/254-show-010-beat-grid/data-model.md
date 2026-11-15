# Data Model: SHOW-010 Beat Grid

No stored data. Value types in ShowControl (`BeatGrid.swift`):

| Type | Fields | Rules |
|---|---|---|
| `BeatGridTempo` | `bpm: Double`, `periodNanoseconds: Int64` (> 0), `anchorNanoseconds: Int64` (a beat on the show timeline; any value), `source: .manual / .estimated` | `init?` fails for a non-positive period or non-finite BPM. |
| `BeatGridTick` | `nanoseconds: Int64`, `beat: Int64` (index from the anchor), `isBar: Bool` (`beat` multiple of 4) | `time: Duration` derived. |
| `BeatGridPosition` | `bar: Int64` (0:00 in bar 1), `beat: Int` (1…4) | |
| `BeatGridMark` | `x: Double`, `isBar: Bool` | x = inset + t / duration × (width − 2 inset). |

App (`ShowBeatGridCoordinator`): `placedAnchor: Int64?` (memory only) — set while playing, kept otherwise.
