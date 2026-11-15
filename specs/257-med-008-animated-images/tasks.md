# Tasks: MED-008 Animated Image Support

**Input**: Design documents from `specs/257-med-008-animated-images/` (spec, plan, research, data-model,
contracts/animated-image.md, quickstart).

**Tests**: requested by the spec (acceptance: "Animated fixture loops and large file respects memory budget";
MED-008-S1 to S6). Budgets (owner rule 7): unit test ≤ 2 s (≤ 10 s for the large fixture), package suite < 1 min
for the filtered run, app test < 30 s.

## Phase 1: Setup

- [X] MED-008-T01 Create the private simulator "MED8 iPhone 17" (iOS 27.2), count PosterBoard reports, check the `Build` symlink and preset submodules, run `xcodegen generate` in the worktree — Verified 2026-11-14: simulator "MED8 iPhone 17" (iOS 27.2) created, PosterBoard 28 reports before, `Build` symlink present, preset submodules initialised, `xcodegen generate` OK

## Phase 2: Foundational (plain model)

- [X] MED-008-T02 `AnimationDelayRule`, `AnimationTimeline`, `AnimatedFrameBudget`, `AnimatedFrameCache`, `AnimatedImportLimits` in `Packages/Compositor/Sources/ImageLayer/AnimatedImageModel.swift` (MED-008-R4 to R6, R8, R13) — Verified 2026-11-14: builds on the host and in the Linux shape (`swift build -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`, Build complete)
- [X] MED-008-T03 Model tests in `Packages/Compositor/Tests/CompositorTests/AnimatedImageModelTests.swift`: delay clamps (browser rule, 60 s cap, Reduce flashing floor), loop property frame(t) == frame(t + total) and boundaries at the clamped delays, budget classes and decoded size, cache eviction, pin, reserve and peak ≤ budget; the Linux shape builds — Verified 2026-11-14: AnimatedImageModelTests 5 tests pass in < 0.01 s each (including 32-bit float delays rounding to 200 ms and 20 ms)

## Phase 3: User Story 1 - An animated GIF plays (P1) 🎯 MVP

- [X] MED-008-T04 [US1] `AnimatedImageProbe`, `AnimatedImageFrames`, `AnimatedImageSanitizer` in `Packages/Compositor/Sources/ImageLayer/AnimatedImageDecoding.swift`; `ImageSanitizer.sanitize` sends `.automatic` animations to it (MED-008-R1 to R3) — Verified 2026-11-14: AnimatedImageLayerTests.testImportStoresAnAnimatedPNGWithTheFramesAndDelaysAndNoMetadata (4 frames, delays within 1.1 ms, loop count 0, no GPS/TIFF/IPTC/GIF dictionaries, metadata only ImageIO's own ColorSpace/PixelX/YDimension; the logo format and a single-frame GIF stay stills; 0.003 s)
- [X] MED-008-T05 [US1] `AnimatedPicture` in `Packages/Compositor/Sources/ImageLayer/AnimatedPicture.swift`; `ImageLayerSource` load/slot/prepared/prewarm/render/dependencies (Reduce flashing from the frame context)/`animationFrameCount`/`shownFrameIndex`/`animationCacheStatistics` (MED-008-R6, R7, R9 to R11) — Verified 2026-11-14: the whole Compositor package suite on the host: CompositorTests 639 tests, 10 skipped, 0 failures, 40 s (all bundles 1 min 28 s wall clock including the build); existing ImageLayer, Ken Burns, slideshow, prewarm and render-cache tests pass
- [X] MED-008-T06 [US1] Fixtures (`AnimatedImageFixtures.swift`: GIF via `CGImageDestination`, hand-written APNG) and GPU acceptance in `AnimatedImageLayerTests.swift`: import to APNG keeps frames and delays, no metadata (S4); the fixture loops through the real compositor and boundaries follow the clamped delays (S1); a still behaves as before; a logo stays still — Verified 2026-11-14: AnimatedImageLayerTests.testTheAnimatedFixtureLoopsThroughTheCompositorWithClampedDelays: 39 steps of 50 ms through the real compositor, every shown index and centre colour equal the timeline's frame, frame(t + 650 ms) == frame(t) for 26 steps, 10 ms played as 100 ms, flash gain 1; 0.04 s

## Phase 4: User Story 2 - A huge animation stays within memory (P1)

- [X] MED-008-T07 [US2] Large-fixture test: 200 frames at 2048² play through every frame with the cache's peak ≤ a 16 MB budget and decoded frames smaller than the source (S2) — Verified 2026-11-14: AnimatedImageLayerTests.testALargeAnimationPlaysEveryFrameWithinTheMemoryBudget: 200 frames of 2048 × 2048 each shown in order with a 16 MB budget, peak accounted bytes ≤ 16 MB, frames decoded at 835 px, fewer than 10 resident, ≥ 200 decodes; 5.5 s

## Phase 5: User Story 3 - Sensory safety (P1)

- [X] MED-008-T08 [US3] Reduce Motion shows frame 0 and renders once then reuses (S3); Reduce flashing makes 100 ms frames last 334 ms — Verified 2026-11-14: AnimatedImageLayerTests.testReduceMotionShowsTheFirstFrameAndRendersOnce (10 frames all frame 0, renderCount 1) and testReduceFlashingPlaysEveryFrameForAtLeast334Milliseconds (20 steps follow the 334 ms timeline)

## Phase 6: User Story 4 - Everywhere a photo goes (P2)

- [X] MED-008-T09 [US4] Prepared slide (`preload`) adopts an animation; Ken Burns with an animation still moves; the scene archive content check accepts the APNG copy (S5) — Verified 2026-11-14: AnimatedImageLayerTests.testAPreparedSlideKenBurnsAndAStillKeepWorking (the preloaded slide adopts its animation at once, Ken Burns and animation both run, a still afterwards has no animation); AnimatedPhotoAppTests.testAnImportedGIFIsStoredAsAnAnimatedPNGThatScenesAccept (SceneArchiveContentCheck accepts the `.png` copy); SlideshowTests, SceneArchiveServiceTests, MediaRelinkAcceptanceTests (18 tests) and PhotoLayerUITests, SlideshowUITests pass on "MED8 iPhone 17"
- [X] MED-008-T10 [US4] `PhotoVisualHost` and `VisualizerView`: VoiceOver value "Animated photo W × H, N frames" (R12); app test `Apps/projectM-iOS/Tests/AnimatedPhotoAppTests.swift`: `PhotoStore.importImage` of a generated GIF stores an APNG, the Photo visual's layer animates (S6) — Verified 2026-11-14: AnimatedPhotoAppTests (2 tests, 0.09 s) with PhotoStoreTests, KenBurnsAppTests, LibraryBackupAppTests, MediaPrewarmAppTests: 20 tests pass on "MED8 iPhone 17" (iOS 27.2)

## Phase 7: Polish

- [X] MED-008-T11 Type-check budget build, repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, PosterBoard count, delete the simulator and derived data — Verified 2026-11-14: build-for-testing with the type-check flags: no warning in new or edited files; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts.py exit 0; check_privacy_manifest and check_network_symbols OK on the Debug app; PosterBoard 28 before and 28 after
- [ ] MED-008-T12 {device} D1: a large animated GIF from Photos plays smoothly for one minute within the memory budget; Reduce Motion holds frame 0

Analysis (speckit-analyze, 2026-11-14): every requirement MED-008-R1…R13 and criterion S1…S6 maps to a task; the
reserve size, frame 0 residency, float delays and the Reduce flashing source were aligned across the artifacts.

## Dependencies

T01 → T02 → T03; T04 → T05 → T06 → T07, T08, T09 → T10 → T11. T12 after merge, on a device.
