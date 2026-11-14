# Implementation Plan: CMP-013 Render Caching

**Branch**: `feature/cmp-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/113-cmp-013-render-caching/spec.md`

## Summary

Two cache levels in the CMP-001 compositor, both opt-in by the layer and both proved bit-identical to
caching off.

- **Level 1, layer pictures.** A layer that adopts `LayerRenderCaching` returns a
  `LayerRenderDependencies` value each frame (flags for time, audio, modulation and external input,
  plus a content and a parameter generation). The compositor turns it into a `LayerRenderCacheKey`
  (generations + picture description + content scale + Reduce flashing + the compositor's cache epoch;
  nil when the layer is not cacheable or declares nothing). When the key equals the key stored with the
  layer's last good picture, `render` is skipped, that picture is shown and the layer is told
  (`renderReused(frame:)`). Otherwise the entry is dropped, the layer renders, and only a successful
  render stores the new key. No new texture: the reused picture is the layer's own.
- **Level 2, the composite.** After the layer loop, the compositor keeps last frame's composite and
  skips only the layer drawing passes when the composite is valid (nothing applied or invalidated since
  the last successful frame) and every layer's `LayerDrawInput` (the picture it is drawn from, −1 for
  none, its shown opacity, whether it was reused) is unchanged and every group's shown opacity is
  unchanged. The flash guard, the output pass, capture and recording run every frame.

The plain-Swift model (dependencies, key, per-layer entry, draw input rule) lives in
`Packages/Compositor/Sources/Compositor/LayerRenderCache.swift` and builds on Linux. `ImageLayerSource`
and `TextLayerSource` adopt the protocol; every other layer keeps rendering every frame (unknown).
`TexturePool` gains a purge count so the compositor sees a memory-warning purge (PERF-006) at its
per-frame `tick`. ADR-0040 records the caching contract (a cross-cutting rule for every future layer).
Report: `docs/test-reports/render-caching.md`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/render-caching.md](contracts/render-caching.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26).

**Primary Dependencies**: none new (Metal, existing pipelines).

**Storage**: none.

**Testing**: `Packages/Compositor`:
- `RenderCacheModelTests` (CPU, Linux shape): cacheability, key equality per input, entry transitions,
  the draw-input rule.
- `RenderCacheCompositeTests` (GPU read-back): the acceptance with the real photo layer (1 render over
  10 frames, fit change → exactly 1), placement changes → 0 renders, the invalidation table (one test
  per trigger), dynamic and undeclared layers (10 of 10), the level-2 reuse, the bit-identity sequence
  (caching on vs off, every output frame compared byte for byte), the text layer, the opt-in GPU time
  bench `CMP013_BENCH=1`.
- Regression: Compositor, RenderGoldens, SceneFormat, ImportFuzz, ShowControl, SceneArchive,
  VisualGenerators, app unit tests and the photo and text UI tests (own simulator), the Linux shape.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: a reused layer costs one key comparison; a reused composite saves every layer
draw pass. No allocation per frame. GPU time recorded on the Mac (CMP-013-S5), not device evidence.

**Constraints**: owner rule 7 (unit ~1-2 s, suite < 1 min); no wall-clock assertions; focused edits to
`Compositor.swift` (hot file: ACC-003, FILE-004 and a test-budget agent run in parallel); explicit
closure types; no C stdio globals; no main-actor mutation in setUp/tearDown; keep
`CVMetalTextureHold`'s rules (camera and video are never cached, untouched).

**Scale/Scope**: L. One model file, a compositor change, two layer adoptions, a pool counter, tests,
an ADR, a report.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new API use | Pass |
| VI Modular boundaries | Model in `Compositor`; layers declare their own inputs; no app change | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU model tests, GPU read-back, byte-identity proof; GPU time labelled Mac-only | Pass |
| Accessibility / flashing | The flash guard runs every frame on the shown composite; output identical to caching off | Pass |
| Privacy, no networking, no telemetry | Nothing stored or logged | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/113-cmp-013-render-caching/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/render-caching.md
└── checklists/requirements.md
docs/adr/0040-layer-render-caching.md
docs/test-reports/render-caching.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerRenderCache.swift              (new, plain Swift)
Packages/Compositor/Sources/Compositor/Compositor.swift                    (level 1 + level 2)
Packages/Compositor/Sources/Compositor/TexturePool.swift                   (purge count from tick)
Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift              (adopts; render count)
Packages/Compositor/Sources/TextLayer/TextLayerSource.swift                (adopts; render count)
Packages/Compositor/Tests/CompositorTests/RenderCacheModelTests.swift      (new)
Packages/Compositor/Tests/CompositorTests/RenderCacheCompositeTests.swift  (new)
Packages/Compositor/Tests/TextLayerTests/TextLayerCacheTests.swift         (new)
```

**Structure Decision**: existing packages and targets only.

## Complexity Tracking

| Addition | Why needed | Simpler alternative rejected because |
|---|---|---|
| Level-2 composite reuse | The row says "skip recomposition"; a static stack otherwise redraws every layer every frame | Level 1 alone still pays every draw pass |
| Cache epoch | One counter covers every global trigger (size, purge, GPU error, reset, failed frame) | Per-trigger flags would each need their own test and could be missed |
