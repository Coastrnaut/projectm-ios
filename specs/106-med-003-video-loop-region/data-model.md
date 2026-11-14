# Data Model: MED-003 Video Loop Region

## VideoLoopRegion (package `VideoLayer`, plain Swift)

| Field | Type | Rule |
|---|---|---|
| `inNanoseconds` | Int64 | ≥ 0 after clamping |
| `outNanoseconds` | Int64 | > in |
| `minimumLengthNanoseconds` (static) | Int64 | 250 000 000 |

- `init(inMilliseconds:outMilliseconds:)`, `inMilliseconds`, `outMilliseconds` (rounded down).
- `effective(duration:) -> VideoLoopRegion` (research MED-003-D1); `static whole(duration:)`.
- `isWholeFile(duration:)`, `contains(_ nanoseconds:)` (in ≤ t < out), `length`.

## TimedFrame (changed)

- `mediaNanoseconds: Int64`: the picture's time in the file (defaults to the presentation time
  for callers that do not set it).

## VideoPipelineStatistics (changed)

- `earlyEnds`, `recoveredErrors`, `prepared` (counts, Sendable, Equatable).

## Stored loop (app, UserDefaults `settings.video.loop`)

`{"id": String (canonical UUID), "inMilliseconds": Int, "outMilliseconds": Int}`. Valid only for
the stored video's ID; malformed or foreign values read as none and are removed.

## SceneVideoLoop (package `SceneFormat`)

| Field | Type |
|---|---|
| `inMilliseconds` | Int (≥ 0) |
| `outMilliseconds` | Int (> in) |

`SceneAsset.videoLoop: SceneVideoLoop?` over `extra["loop"]`; malformed → nil.

## State transitions (session)

```text
open(in or hint) → reading ──picture < in──→ skip (remember)
                       ├──picture in [in,out)──→ queue (prepare at out − 0.5 s)
                       ├──picture ≥ out / EOF──→ pass end: clean → next pass at in
                       ├──error after a picture──→ recoveredErrors += 1 → next pass at in
                       └──bad pass ×3 / open fails──→ failed
```
