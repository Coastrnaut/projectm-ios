# Tasks: MED-008 Animated Image Support

**Input**: Design documents from `specs/257-med-008-animated-images/` (spec, plan, research, data-model,
contracts/animated-image.md, quickstart).

**Tests**: requested by the spec (acceptance: "Animated fixture loops and large file respects memory budget";
MED-008-S1 to S6). Budgets (owner rule 7): unit test ≤ 2 s (≤ 10 s for the large fixture), package suite < 1 min
for the filtered run, app test < 30 s.

## Phase 1: Setup

- [ ] MED-008-T01 Create the private simulator "MED8 iPhone 17" (iOS 27.2), count PosterBoard reports, check the `Build` symlink and preset submodules, run `xcodegen generate` in the worktree

## Phase 2: Foundational (plain model)

- [ ] MED-008-T02 `AnimationDelayRule`, `AnimationTimeline`, `AnimatedFrameBudget`, `AnimatedFrameCache`, `AnimatedImportLimits` in `Packages/Compositor/Sources/ImageLayer/AnimatedImageModel.swift` (MED-008-R4 to R6, R8, R13)
- [ ] MED-008-T03 Model tests in `Packages/Compositor/Tests/CompositorTests/AnimatedImageModelTests.swift`: delay clamps (browser rule, 60 s cap, Reduce flashing floor), loop property frame(t) == frame(t + total) and boundaries at the clamped delays, budget classes and decoded size, cache eviction, pin, reserve and peak ≤ budget; the Linux shape builds

## Phase 3: User Story 1 - An animated GIF plays (P1) 🎯 MVP

- [ ] MED-008-T04 [US1] `AnimatedImageProbe`, `AnimatedImageFrames`, `AnimatedImageSanitizer` in `Packages/Compositor/Sources/ImageLayer/AnimatedImageDecoding.swift`; `ImageSanitizer.sanitize` sends `.automatic` animations to it (MED-008-R1 to R3)
- [ ] MED-008-T05 [US1] `AnimatedPicture` in `Packages/Compositor/Sources/ImageLayer/AnimatedPicture.swift`; `ImageLayerSource` load/slot/prepared/prewarm/render/dependencies (Reduce flashing from the frame context)/`animationFrameCount`/`shownFrameIndex`/`animationCacheStatistics` (MED-008-R6, R7, R9 to R11)
- [ ] MED-008-T06 [US1] Fixtures (`AnimatedImageFixtures.swift`: GIF via `CGImageDestination`, hand-written APNG) and GPU acceptance in `AnimatedImageLayerTests.swift`: import to APNG keeps frames and delays, no metadata (S4); the fixture loops through the real compositor and boundaries follow the clamped delays (S1); a still behaves as before; a logo stays still

## Phase 4: User Story 2 - A huge animation stays within memory (P1)

- [ ] MED-008-T07 [US2] Large-fixture test: 200 frames at 2048² play through every frame with the cache's peak ≤ a 16 MB budget and decoded frames smaller than the source (S2)

## Phase 5: User Story 3 - Sensory safety (P1)

- [ ] MED-008-T08 [US3] Reduce Motion shows frame 0 and renders once then reuses (S3); Reduce flashing makes 100 ms frames last 334 ms

## Phase 6: User Story 4 - Everywhere a photo goes (P2)

- [ ] MED-008-T09 [US4] Prepared slide (`preload`) adopts an animation; Ken Burns with an animation still moves; the scene archive content check accepts the APNG copy (S5)
- [ ] MED-008-T10 [US4] `PhotoVisualHost` and `VisualizerView`: VoiceOver value "Animated photo W × H, N frames" (R12); app test `Apps/projectM-iOS/Tests/AnimatedPhotoAppTests.swift`: `PhotoStore.importImage` of a generated GIF stores an APNG, the Photo visual's layer animates (S6)

## Phase 7: Polish

- [ ] MED-008-T11 Type-check budget build, repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, PosterBoard count, delete the simulator and derived data
- [ ] MED-008-T12 {device} D1: a large animated GIF from Photos plays smoothly for one minute within the memory budget; Reduce Motion holds frame 0

## Dependencies

T01 → T02 → T03; T04 → T05 → T06 → T07, T08, T09 → T10 → T11. T12 after merge, on a device.
