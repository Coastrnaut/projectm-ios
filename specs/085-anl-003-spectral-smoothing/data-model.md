# Data Model: ANL-003 Spectral Smoothing

## SmoothingTimes (value, Sendable, Equatable)

| Field | Type | Rule |
|---|---|---|
| attackSeconds | Double | clamped to 0…2; NaN → 0 |
| releaseSeconds | Double | clamped to 0…2; NaN → 0 |
| isInstant | Bool (derived) | both 0 |

`SmoothingTimes.instant` = (0, 0), the default.

## BandSmoother (reference type, one owner, not Sendable)

| Field | Type | Rule |
|---|---|---|
| times | SmoothingTimes | effective from the next update; never snaps |
| state | 128 Float, allocated in `init` | the smoothed vector |
| count | Int | band count of the last update (0…128) |
| generation | UInt64 | session of the last update |
| primed | Bool | false after `init` / `reset()` |

State transitions per `update(target, count n, Δt, generation g)`:

- `!primed || n != count || g != generation` → snap: state[i] = finite(target[i]) ? target[i] : 0; primed = true.
- else for each band: x non-finite → keep; else a = x > y ? aA : aR; y += a·(x − y).
- `reset()` → primed = false (next update snaps).

## App settings

| Key | Type | Choices | Default / invalid |
|---|---|---|---|
| `settings.spectrum.attack` | Int (ms) | 0, 25, 50, 100 | 0 |
| `settings.spectrum.release` | Int (ms) | 0, 100, 250, 500 | 0 |

## LiveBandFrameInfo (extended)

Adds `session: UInt64`: the capture-session generation of the bus frame (`AnalysisTimestamp.session`).
