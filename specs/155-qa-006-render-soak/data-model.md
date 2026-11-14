# Data Model: QA-006 Render Soak Test

All types are in `Packages/Compositor/Sources/Compositor/RenderSoak.swift` (plain Swift) unless
marked "harness" (`Packages/RenderGoldens/Sources/SceneRenderHarness/RenderSoakDriver.swift`).

## RenderSoakTolerance

| Field | Default | Rule |
|---|---|---|
| `warmUpCycles` | 2 | cycles before measuring |
| `minimumMeasuredCycles` | 3 | fewer → inconclusive |
| `slopeFloorBytes` / `slopeFraction` | 64 KiB / 0.005 | ε = max(floor, fraction × warm-up high-water) per cycle |
| `boundFloorBytes` / `boundFraction` | 2 MiB / 0.10 | bound = warm-up high-water + max(floor, fraction × it) |
| `maxLiveScenesAtDwellEnd` | 1 | live scene objects at a dwell end |

## RenderSoakCycleSample (Codable)

`cycle`, `memoryHighWaterBytes`, `memoryEndBytes`, `poolLiveBytes`, `poolMisses`, `frames`.

## RenderSoakDwellSample (Codable)

`cycle`, `scene` (name), `checkedOutTextures`, `checkedOutBytes`, `liveScenes`.

## RenderSoakError (Codable)

`frame`, `scene`, `message`. The recorder keeps the first 20 and counts all.

## RenderSoakRule (String enum)

`renderErrors`, `memorySlope`, `memoryBound`, `poolBaseline`, `liveObjects`, `releaseNotEmpty`,
`tooFewCycles`.

## RenderSoakVerdict (Codable)

`outcome` (`pass` / `fail` / `inconclusive`), `failedRules`, `warmUpHighWaterBytes`,
`slopeBytesPerCycle`, `slopeLimitBytesPerCycle`, `maxMeasuredHighWaterBytes`, `boundBytes`,
`baselineMismatches` (text), `errorCount`, `measuredCycles`.

Decision: inconclusive when measured cycles < minimum (and no other failure); fail when any rule
failed; else pass. `passed` ⇔ outcome == pass.

## RenderSoakRecorder

Collects cycle samples, dwell samples, errors and the release record (`checkedOutTextures`,
`liveObjects` after everything is dropped); `verdict()` computes the rules. Pure; no clock.

## RenderSoakReport (Codable)

`name`, `platform`, `memorySource` (`deviceAllocatedSize` / `poolEstimate`), `resolution`,
`frames`, `simulatedSeconds`, `wallSeconds` (reported only), `switches`, `cycles`, `samples`,
`dwells`, `errors`, `errorCount`, `release`, `verdict`, `settings` (string map: dwell, transition,
cut cadence, seed, leak).

## Harness: RenderSoakConfiguration, RenderSoakLeak, RenderSoakDriver

- `RenderSoakScene`: a `GoldenSceneRun` and its `SceneDocument`.
- `RenderSoakConfiguration`: `name`, `scenes`, `resolution` (128 × 96), `frames` (1,800),
  `dwellFrames` (30), `transitionSeconds` (0.25), `cutEvery` (3), `seed`, `frameIntervalNanoseconds`
  (1/60 s), `tolerance`, `leak`. `simulatedSeconds = frames × interval`. `cycleFrames = dwell ×
  scenes`. `init(seconds:)` derives frames.
- `RenderSoakLeak`: `none`, `pooledTexturePerCycle`, `deviceTexturePerCycle`.
- `RenderSoakDriver.run(_:) -> RenderSoakReport`: never throws for a render error (counted); throws
  only when no Metal device exists.
