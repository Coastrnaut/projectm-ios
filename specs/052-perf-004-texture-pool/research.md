# Research: PERF-004 Texture Pool

All open points of the spec were settled in Clarifications (session 2026-11-13); this file records
the technical decisions behind them.

## PERF-004-D1: Key — the full texture description

- **Decision**: `TexturePoolKey` = pixel format, width, height, usage, storage mode, mip level count,
  sample count, texture type (raw values, so the key is plain Swift). Only an identical key is reused.
- **Rationale**: Metal textures cannot change any of these after creation; a "compatible" match
  (larger texture, superset usage) would change sampling coordinates and the compositor's full-size
  picture rule (CMP-001-R6).
- **Alternatives**: size classes or rounding up (wastes memory, breaks the full-size rule); heaps with
  aliasing (`MTLHeap`, `makeAliasable`) — more efficient but needs hazard tracking per resource and
  changes every layer's allocation path; revisit if device traces show fragmentation.

## PERF-004-D2: Return after GPU completion — a polled command-buffer fence

- **Decision**: `checkIn(textures, fence:)` takes the last `MTLCommandBuffer` the owner encoded with
  (the compositor stores a reference each frame: no allocation). A retired entry is reusable when the
  fence is nil (never encoded) or its `status` is `.completed` or `.error`; the check runs when a
  texture of the same key is requested. Waiting entries can still be evicted or purged: dropping
  our reference is always memory-safe because a committed command buffer retains the resources it
  uses (Metal's default retained references); only *reuse* needs the fence.
- **Rationale**: exact, no timing assumptions, no per-frame closure.
- **Alternatives**: `addCompletedHandler` on every frame (allocates a closure per frame against
  CMP-001-R9, and the handler runs on another thread); a fixed N-frame latency (wrong when the GPU
  stalls or frames are dropped); `waitUntilCompleted` on switch (blocks the main thread).
- **Caveat recorded**: a caller that creates its command buffers with
  `makeCommandBufferWithUnretainedReferences` must keep pictures alive itself; no caller does.

## PERF-004-D3: Caps and eviction

- **Decision**: retired bytes (idle + waiting) ≤ `maxRetiredBytes` (default min(128 MiB,
  `recommendedMaxWorkingSetSize` / 8)); on overflow evict the least recently returned first; an entry
  bigger than the cap is dropped on return. Age: entries retired more than `maxIdleFrames` (default
  300) pool frames ago are dropped at `tick()`. Bytes per texture: `MTLTexture.allocatedSize` (actual
  allocation, including alignment).
- **Rationale**: textures in use are never refused (a refusal would blank a layer); only the cache is
  capped. 128 MiB ≈ five iPhone 15 full-screen rgba16Float pictures (≈ 24 MB each): one visual's set.
- **Alternatives**: wall-clock age (untestable without sleeps, owner rule against wall-clock asserts);
  per-key caps (more knobs, no benefit at a handful of keys).

## PERF-004-D4: Thread safety

- **Decision**: the Metal `TexturePool` is a `final class`, `@unchecked Sendable`, guarding the core
  with one `NSLock`. Critical sections are short array/dictionary bookkeeping; `device.makeTexture` is
  called outside the lock. The `Compositor` itself stays single-threaded (not Sendable).
- **Rationale**: the app's hosts render on the main run loop today, but a shared object should not
  depend on that; an uncontended `NSLock` costs tens of nanoseconds.

## PERF-004-D5: Pool frame clock

- **Decision**: each `Compositor.composite` calls `pool.tick()` once. With two compositors on one pool
  the pool ages twice as fast; acceptable (it only shortens idle residency).
- **Alternatives**: a display-link-driven tick in the app (another moving part outside the package).

## PERF-004-D6: Observability

- **Decision**: `TexturePoolCounters` (live/retired/waiting textures and bytes, hits, misses,
  evictions, purged) readable at any time; `OSSignposter` interval "PERF-004 texture allocation"
  around each `makeTexture` on a miss and an event per purge (subsystem `org.projectmios.compositor`,
  category `TexturePool`). MetricKit is not used: it reports per-day aggregates, not per-switch
  allocation; PERF-012 may export the counters.

## PERF-004-D7: Scope — what is not pooled

- **Decision**: only the compositor's composite and layer pictures. Not pooled: effect-chain and bloom
  images (VisualGenerators; created once per size in `prepare`, released with the layer — pooling
  would invert the package dependency), camera `CVMetalTextureCache`, decoded photo textures, stub
  camera texture, `ProjectMLayerSource`'s target texture and projectM/ANGLE GL textures (engine-owned).
  The acceptance test additionally samples `MTLDevice.currentAllocatedSize` around the 100 switches,
  so growth in any of these during compositor switches would be caught. A debug-only tally of
  textures created outside the pool is not built (it would need release tracking in five packages).

## Baseline numbers (host Mac, before the pool)

The compositor creates `1 + Σ pictures` textures at every size change and `pictureCount` per new
layer; 100 switches between two-layer stacks at a resize every 10 switches create about 100 × 3 +
10 × 4 ≈ 340 textures (all released by ARC; nothing reused). With the pool, the same run creates
only the warm-up set per size (see the acceptance numbers in tasks.md, PERF-004-T06).
