# Data Model: MED-007 Image Ken Burns

| Entity | Fields | Rules |
|---|---|---|
| `KenBurnsRect` | `x`, `y`, `width`, `height` (Double, image fractions, top-left) | Valid: finite, width/height ≥ 0.05, x, y ≥ 0, x + width ≤ 1, y + height ≤ 1 (1e-9 tolerance). `clamped` repairs any input; `init?(validating:)` refuses. `full` = (0, 0, 1, 1). |
| `KenBurnsEasing` | `linear`, `easeInOut` (String raw values) | `shaped(u)`: u, or 3u² − 2u³; monotonic on 0…1. |
| `KenBurnsMotion` | `start`, `end` (`KenBurnsRect`), `durationMilliseconds` (Int, 2000…60000, default 10000), `easing` (default easeInOut) | `crop(elapsedNanoseconds:durationNanoseconds:)`: 0 → start, ≥ duration → end, else eased lerp. Presets `zoomIn`, `zoomOut`, `panLeftToRight`, `panRightToLeft`. JSON keys as the scene field. |
| `KenBurnsPlayhead` | `elapsedNanoseconds`, `started` | `advance(frameDuration:limit:)`; `restart()`; finished when elapsed ≥ duration. |
| `ImageLayerSource` (additions) | `kenBurns: KenBurnsMotion?`, `kenBurnsDurationNanoseconds` (from the motion unless the app overrides), `reduceMotion: Bool`, playhead | Still when off, reduced, start = end, or finished. |
| `SceneKenBurns` | the motion as stored | `photo` asset field `kenBurns`; malformed → nil. |
| `KenBurnsCoordinator` (app) | `motion: KenBurnsMotion?`, `preset` (derived), store | Edits clamp, save, notify the app (`onChange`). |

States of the layer's movement: Off → (movement set) → Waiting (no picture) → Moving (first drawn frame, elapsed 0)
→ Holding (elapsed ≥ duration) → back to Moving on a new picture or a new movement. Reduce Motion: Holding at start.
