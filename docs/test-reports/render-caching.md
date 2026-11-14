# Test report: CMP-013 Render caching

Feature: `specs/113-cmp-013-render-caching` (branch `feature/cmp-013`), ADR-0040. Host: the Mac Studio
(build machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device evidence; no device
run was made. GPU timings are Mac timings, recorded, not asserted, and not device evidence.

## Audit (2026-11-14, commit `a93c29db`)

Before this row every layer rendered its whole picture every frame and the whole stack was composited
every frame. The render contract (CMP-001) gives each layer the frame context (presentation time, frame
index, duration, output size, content scale, Reduce flashing) and the audio context; a layer declared
nothing about which of them it reads.

| Layer | Reads per frame | CMP-013 |
|---|---|---|
| Photo (MED-001) | held image, fit, picture size | cached (content = load generation, parameters = fit generation) |
| Text (MED-009) | held rendering, picture size | cached (content = upload serial) |
| Video (MED-002) | playback clock from presentation time, decoded frames | always rendered (no paused state in the layer) |
| Camera (CAM-001) | newest sensor frame | always rendered (`CVMetalTextureHold` untouched) |
| Spectra, oscilloscope (VIS-001/002, FX-001) | time, bands | always rendered |
| Materials (SHD-001), generator graphs (SHD-002) | frame duration, band level (motion state) | always rendered |
| projectM | engine time and audio | always rendered |

## Baseline (CMP-013-T01, before any change)

`swift test --package-path Packages/Compositor`: 335 tests, 5 skipped, 0 failures, 8.5 s (29.5 s wall).

## Design in one paragraph

A layer may adopt `LayerRenderCaching` and declare, per frame, time, audio, modulation and external
input flags plus a content and a parameter generation; unknown or any flag means render. The key is
those generations plus the picture description, content scale, Reduce flashing and the compositor's
cache epoch. Level 1: an equal key with a last good picture skips `render` and shows that picture;
otherwise the entry is dropped and only a successful render stores the new key. Level 2: when the
composite is valid and every layer's draw input (picture or none, shown opacity, reused) and every
group's opacity is unchanged, the previous composite is kept and only the layer passes are skipped; the
flash guard, output, capture and recording run every frame. Global triggers bump the epoch.

## Invalidation table and its tests

| Trigger | Effect | Test |
|---|---|---|
| Content change (photo loaded, message rendered, colour) | that layer renders once | `testAContentChangeRendersOnce…`, photo acceptance, `TextLayerCacheTests` |
| Parameter change (fit) | that layer renders once | photo acceptance, `testAParameterChangeRendersOnce` |
| Output size | all render | `testAnOutputSizeChangeRendersOnce` |
| Colour space / format | all render (key) | fixed by the picture contract; descriptor in the key (`RenderCacheModelTests`) |
| Reduce flashing, content scale | all cacheable render | `testReduceFlashingAndContentScaleChangesRenderOnce` |
| Pool purge (PERF-006 memory warning) | epoch | `testAPoolPurgeRendersOnce` |
| Render-health reset, explicit invalidation | epoch | `testResetRenderHealthAndExplicitInvalidationRenderOnce` |
| Caching switched off / on | off: every frame; on: epoch | `testSwitchingCachingOffRendersEveryFrameAndOnAgainRendersOnce` |
| Failed render (one-picture layer) | entry dropped, renders next frame, garbage never shown | `testAFailedRenderDropsTheEntry…` |
| Held fault (PERF-014) | fallback, no reuse, one render at the retry tick | `testAHeldFaultIsNotReusedAndRendersOnceAtItsRetry` |
| Observed GPU error | epoch | `testAnObservedGPUErrorInvalidates` |
| Frame returns without finishing | epoch | `testAFrameThatFailsHalfWayInvalidates` |
| Reorder, group, solo, mute, clear | composite redrawn, no layer render | `testStackGroupAndSoloMuteChangesRedrawTheCompositeOnly` |
| Opacity, transform, blend, mask | composite redrawn, no layer render | `testPlacementChangesDoNotRenderTheLayerButShowInTheFrame` |
| Hidden static layer | stays cached; reappears at once | `testAHiddenStaticLayerStaysCachedAndReappearsAtOnce` |

## Results

| Check | Result |
|---|---|
| The acceptance (CMP-013-S1), real photo layer | 1 render over 10 frames (10 shown); fit change → exactly 1 more; new photo → transparent while loading, then exactly 1 render |
| `RenderCacheModelTests` (5, CPU) | pass, 0.002 s; host and Linux shape |
| `RenderCacheCompositeTests` (18 GPU + 1 opt-in bench) | pass, 0.59 s |
| `TextLayerCacheTests` (1) | pass, 0.06 s |
| Bit identity (CMP-013-S3) | 44 frames, every output frame byte-identical (raw `rgba16Float`), caching on vs off; 20 composites reused; base layer renders 6 vs 44, photo 7 vs 44 |
| Dynamic layers (CMP-013-S4) | time, audio, modulation, external input, undeclared and the linear spectrum: 10 of 10 each; composite never reused |
| Compositor full suite | 359 tests, 6 skipped (benches), 0 failures, 8.0 s |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | Compositor 189, 0 failures |
| RenderGoldens / SceneFormat / ImportFuzz / ShowControl / SceneArchive / VisualGenerators | 39 / 112 / 15 / 31 / 27 / 133, 0 failures (goldens unchanged) |
| App unit tests (`projectM-iOSTests`, own iOS 27.2 simulator "CMP13 iPhone 17", created and deleted) | 498 tests, 0 failures, 11.6 s test time (88 s wall with build) |
| `PhotoLayerUITests`, `TextOverlayUITests` (same simulator) | 2 tests, 0 failures (27.2 s and 13.4 s; 78 s wall) |
| PosterBoard reports during the simulator runs | 0 new (25 before and after) |
| Repository checks | compliance, docs, motion policy, permission catalog, status events OK; script tests 153 OK (1 skipped) |

## GPU time (CMP-013-S5; Mac, not device evidence)

`CMP013_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter RenderCacheBench`:
6 static layers (opacity 0.8, rotated and scaled, one screen-mode), 1920 × 1080, `rgba16Float`, 120
measured frames.

| Case | Median (ms) | p95 (ms) |
|---|---|---|
| Caching off | 0.538 | 0.688 |
| Caching on (pictures and composite reused; flash guard and output still run) | 0.052 | 0.062 |

## Not verified

- No device run (performance on D1-D3 not measured).
