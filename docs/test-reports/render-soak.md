# Render soak (QA-006) — test report

Spec: `specs/155-qa-006-render-soak`. Roadmap acceptance: "No unbounded GPU memory growth and no
uncaught render error." Host and simulator results below are development evidence only; the device
soak (QA-006-T13, `{device}`) is open for the final QA phase.

## Result: no leak found (2026-11-14, Mac Studio, Xcode 27.2)

No rendering code was changed (QA-006-R12): no soak found a leak or a render error.

| Run | Platform | Memory figure | Simulated | Scenes shown | Errors | Memory per cycle | Verdict | Wall |
|---|---|---|---|---|---|---|---|---|
| `testDefaultSoakIsBoundedAndErrorFree` | macOS host | device allocated size | 30 s | 60 | 0 | 2,719,744 B high-water every measured cycle, slope 0 | pass | 7.5 s |
| same | iOS 27.2 Simulator (QA6) | pool estimate | 30 s | 60 | 0 | 786,432 B, slope 0 | pass | 6.4 s |
| `run_render_soak.py --seconds 300` | macOS host | device allocated size | 300 s | 600 | 0 | 2,719,744 B over 100 cycles, slope 0; process footprint 370.8 → 371.4 MB | pass | 24.6 s |
| `ProjectMPresetSoakTests` | iOS 27.2 Simulator (QA6) | pool estimate | 20 s | 30 preset loads | 0 | 98,304 B, slope 0; process footprint 15.94 → 15.89 MB | pass | 2.0 s |

Pool checkouts at each dwell end on the host: photo-gradient 2, text-caption 3, spectrum-circular 3,
material-plasma 2, graph-hue-rings 2, stack-composite 5 textures, identical in every cycle; the pool
created 8 textures in the first cycle and none after (misses constant at 8). After release nothing was
checked out and no scene compositor or layer was alive.

## The detector works (negative controls)

| Leak injected per cycle | Platform | Failed rules | Slope (limit) |
|---|---|---|---|
| one pooled 128 × 96 texture, never returned | macOS host | memorySlope, poolBaseline, releaseNotEmpty | 114,688 B (65,536) |
| one device texture, kept | macOS host | memorySlope | 114,688 B (65,536) |
| one pooled texture | iOS Simulator | memorySlope, poolBaseline, releaseNotEmpty | 98,304 B (65,536) |
| one device texture | iOS Simulator | memorySlope (pool estimate + the injected bytes) | 98,304 B (65,536) |

## Limits

- The iOS Simulator reports `MTLDevice.currentAllocatedSize` = 0, so there the memory rule sees only
  pooled textures (and the injected leak); the process footprint is recorded for information. The
  device-wide figure is judged on the macOS host and, in the final phase, on D1.
- The projectM soak keeps one engine and switches presets; engine-internal GPU memory is visible only
  through the process footprint on the simulator.
