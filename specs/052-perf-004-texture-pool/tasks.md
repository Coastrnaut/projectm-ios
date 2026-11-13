# Tasks: PERF-004 Texture Pool

**Input**: design documents in `specs/052-perf-004-texture-pool/` (spec, plan, research,
data-model, contracts/texture-pool.md, quickstart).

**Tests**: requested by the spec (PERF-004-S1 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] PERF-004-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Foundational (blocks every story)

- [X] PERF-004-T01 [P] Pool bookkeeping in plain Swift: `TexturePoolKey` (pixelFormat, width, height, usage, storageMode, mipmapLevelCount, sampleCount, textureType as raw values; Hashable), `TexturePoolLimits` (maxRetiredBytes default "min(128 MiB, recommendedMaxWorkingSetSize / 8)", maxIdleFrames default 300), `TexturePoolCounters` (invariant "liveTextures == checkedOutTextures + retiredTextures"), generic `TexturePoolCore<Resource, Fence>` with `checkOut`, `adopt`, `checkIn(_:fence:)`, `tick`, `purge` per contracts/texture-pool.md, in `Packages/Compositor/Sources/Compositor/TexturePoolCore.swift` — Verified 2026-11-13: `swift test --package-path Packages/Compositor` (158 tests, 0 failures, 2.6 s) and the Linux shape (85 tests, 0 failures)
- [X] PERF-004-T02 [P] Core tests with a fake resource and fence (run on the host and in the Linux shape): hit and miss by key (a different width, format or usage misses); most recently returned reused first; no reuse while the fence is incomplete, reuse after it completes, nil fence reusable at once (S3); byte cap evicts least recently returned first and drops an entry larger than the cap (S4); age eviction after `maxIdleFrames` ticks; purge drops idle and waiting entries and leaves checked-out ones; unknown and double check-ins ignored; counters invariant after every step; `default(recommendedWorkingSetBytes:)`, in `Packages/Compositor/Tests/CompositorTests/TexturePoolCoreTests.swift` — Verified 2026-11-13: TexturePoolCoreTests 14/14 on the macOS host and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`)
- [X] PERF-004-T03 Metal `TexturePool` (`@unchecked Sendable`, one `NSLock`, `makeTexture(descriptor:)` creating outside the lock on a miss with an `OSSignposter` interval, bytes from `allocatedSize`, `recycle(_:after:)` with `MTLCommandBuffer` fences complete at `.completed` or `.error`, `tick`, `purge` with a signpost event, `key(for:)`), in `Packages/Compositor/Sources/Compositor/TexturePool.swift` — Verified 2026-11-13: TexturePoolSwitchTests 7/7 on the macOS host GPU

## Phase 2: User Story 1 - Switching scenes many times does not grow memory (P1)

**Goal**: the compositor takes and returns every picture through a pool; the app's visuals share one.
**Independent test**: 100 scene switches with a resize every 10th keep live textures and bytes at a fixed bound.

- [X] PERF-004-T04 [US1] Compositor through the pool: `init(device:layers:texturePool:)` and `init(device:texturePool:)` (private pool when nil), `texturePool` property, pictures and composite from `texturePool.makeTexture`, `recycle` with the last encoded command buffer on remove (`apply`), resize and `deinit`, `tick()` per `composite`; `pictureAllocations` keeps counting pictures taken, in `Packages/Compositor/Sources/Compositor/Compositor.swift` — Verified 2026-11-13: Compositor package 158/158 (all CMP-001 to CMP-005 and OUT-001 tests unchanged and passing)
- [X] PERF-004-T05 [P] [US1] Metal pool tests on the GPU: same descriptor reuses the texture only after its command buffer completed; an uncommitted (never completed) fence keeps it out; different usage or size misses; purge empties retired; `recycle` of a foreign texture is ignored; two threads checking out and recycling concurrently keep the counters' invariant (R9), in `Packages/Compositor/Tests/CompositorTests/TexturePoolSwitchTests.swift` — Verified 2026-11-13: `testATextureIsReusedOnlyAfterItsCommandBufferCompleted`, `testDifferentDescriptionsMissAndPurgeAndForeignTextures`, `testTwoThreadsShareAPool` on the macOS host GPU
- [X] PERF-004-T06 [US1] The acceptance (S1): 100 scene switches applying alternating `LayerStack`s with different layer sets (new IDs every switch; last-good and transparent fallbacks), a resize every 10 switches between two sizes, a frame after each; live textures and bytes never exceed the exact bound and are equal at switch 20 and switch 100; misses stop after warm-up; `MTLDevice.currentAllocatedSize` does not grow after warm-up beyond a small tolerance; plus S2: 60 frames at a steady size take 0 pictures and 0 pool misses; releasing the compositor returns every picture (checked-out textures 0), in `Packages/Compositor/Tests/CompositorTests/TexturePoolSwitchTests.swift` — Verified 2026-11-13: `testHundredSceneSwitchesKeepLiveTexturesBounded` (live 10 textures, 491,520 bytes at switch 20 and 100; 10 misses, 381 hits; device allocated 1,769,472 → 1,769,472; baseline without reuse 391 creations), macOS host
- [ ] PERF-004-T07 [US1] App: `SharedTexturePool.pool(for:)` (main actor; one pool per `MTLDevice.registryID`; purges on `UIApplication.didReceiveMemoryWarningNotification`), Camera and Photo hosts build their compositors with it (compositor made reachable to app tests), in `Apps/projectM-iOS/Visuals/SharedTexturePool.swift`, `CameraVisualHost.swift`, `PhotoVisualHost.swift`
- [ ] PERF-004-T08 [US1] App unit test (S5): Camera (stub) → Photo → Spectrum → Camera, five cycles, one offscreen frame per visual; the shared pool's live textures stay at the first cycle's bound and later cycles add no misses; a posted memory warning purges retired textures, in `Apps/projectM-iOS/Tests/TexturePoolAppTests.swift`

## Phase 3: User Story 2 - Reuse never corrupts a frame (P1)

**Goal**: no picture is reused before its frame completes.
**Independent test**: covered by T02 (fake fence) and T05 (real command buffers); the compositor-level check is T09.

- [X] PERF-004-T09 [US2] Compositor test: remove a layer and add another of the same size without waiting for the previous frame's command buffer: the new layer gets a different texture; after completion, a further switch reuses it; the composite shows only the new layer's color, in `Packages/Compositor/Tests/CompositorTests/TexturePoolSwitchTests.swift` — Verified 2026-11-13: `testARemovedLayersPicturesAreNotReusedWhileItsFrameIsPending`, macOS host GPU

## Phase 4: User Story 3 - Idle pictures are capped and freed (P2)

**Goal**: caps, age and purge hold through the compositor.
**Independent test**: T02 (core) plus T10.

- [X] PERF-004-T10 [US3] Compositor test: with a pool whose cap holds one picture, a resize retires the old set and only the cap's worth stays retired; after `maxIdleFrames` frames the old size is evicted; `purge()` between frames leaves the visual rendering correctly, in `Packages/Compositor/Tests/CompositorTests/TexturePoolSwitchTests.swift` — Verified 2026-11-13: `testCapAgeAndPurgeThroughTheCompositor`, macOS host GPU

## Phase 5: Polish and verification

- [ ] PERF-004-T11 Linux shape: `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` passes (core tests run)
- [ ] PERF-004-T12 Simulator: `xcodebuild test -scheme Compositor` once on an own iOS 27.2 simulator; app: `projectM-iOSTests`, `CameraUITests`, `PhotoLayerUITests`, `NativeVisualUITests`; PosterBoard reports counted before and after; simulator deleted
- [ ] PERF-004-T13 Gates and docs: `check_compliance.py` and `validate_docs.py` pass; the package header in `Packages/Compositor/Package.swift` mentions the pool; spec status updated
- [ ] PERF-004-T14 {device} D1: 100 visual and stack switches (Camera → Photo → Spectrum → Camera), live GPU memory from Xcode's memory report or `MTLDevice.currentAllocatedSize` plateaus after the first cycle (S6)
- [ ] PERF-004-T15 {device} D3 (iPadOS 26.5): the same as T14
- [ ] PERF-004-T16 {device} D1: Instruments signposts "PERF-004 texture allocation" appear only at the first cycle and at size changes (rotation or external display)

## Dependencies

T01 → T02, T03. T03 → T04, T05. T04 → T06, T09, T10, T07 → T08. T11-T13 after T01-T10. T14-T16 last
(owner).

## Parallel examples

- T01 and the test file of T02 can be written together; T05 alongside T04 (different files).
- US2 and US3 tests (T09, T10) are independent of the app work (T07, T08).

## Implementation strategy

MVP = Phase 1 + US1 (T01-T08): the acceptance holds. US2 and US3 add the targeted checks of the
completion rule and caps through the compositor.
