# Data Model: MED-004 Video Playback Speed

## VideoPlaybackSpeed (package `VideoLayer`, plain Swift)

| Field | Type | Rule |
|---|---|---|
| `percent` | `Int` | One of 25, 50, 75, 100, 125, 150, 200 (`init?(percent:)` rejects others) |

Derived: `isNormal` (100); `prerollLeadNanoseconds` = 500 000 000 × max(percent, 100) / 100.
Constants: `.normal`, `all` (ascending).

## VideoPlaybackClock (extended)

| Field | Type | Rule |
|---|---|---|
| `speed` | `VideoPlaybackSpeed` | Default `.normal`; `setSpeed(_:)` |
| `playbackNanoseconds` | `Int64` | Video time; += ⌊(step × percent + remainder) / 100⌋ for a step in (0, 1 s] |
| `remainder` (private) | `Int64` | 0…99, carried between steps; reset by `reset()` |
| `presentationSinceSpeedChange` | `Int64` | Sum of counted steps since the last `setSpeed`/`reset` |
| `playbackSinceSpeedChange` | `Int64` | Video time added since then |

Transitions: `setSpeed` keeps `playbackNanoseconds` and `remainder` (continuity) and zeroes the two
window sums; `reset()` zeroes everything except `speed`; `forgetPresentation()` unchanged.

## Stored speed (UserDefaults `settings.video.speed`)

`{"id": "<canonical UUID>", "percent": <Int>}`. Absent = 1×. Read only for the stored video's id
and a percent in the set; anything else is removed. Removed by Remove Video, a new current video,
the UI tests' reset and FILE-011's "Photos and videos" erase. Never in a FILE-005 backup.

## Scene speed (SceneFormat)

`video` asset field `speedPercent`: integer, present only when not 100. `SceneAsset.videoSpeedPercent`
returns a positive integer ≤ Int32.max or nil; the app accepts it only through
`VideoPlaybackSpeed(percent:)` (else 1×). Carried verbatim by apps without MED-004.

## App-side carriers

`SceneInputs.videoSpeedPercent`, `SceneRestoredValues.videoSpeedPercent`,
`ShowLook.videoSpeedPercent`, `ShowSceneApply.videoSpeedPercent`: `Int?` (nil = 1×), next to the
existing `videoLoop`.
