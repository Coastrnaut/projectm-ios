# Tasks: PERF-005 Preset prewarm scheduler

**Input**: Design documents from `specs/179-perf-005-prewarm-scheduler/`
**Tests**: requested by the brief (acceptance, executor spy, pause, preset timing, app test).

## Phase 1: Setup

- [X] PERF-005-T01 Confirm the baseline: `swift test --package-path Packages/PresentationLifecycle` and the app build on simulator "PERF5" pass before changes (worktree, `Build` symlink in place) — Verified 2026-11-14: `swift test --package-path Packages/PresentationLifecycle` (60 tests) before changes; Build symlink present

## Phase 2: Foundational (the core)

- [X] PERF-005-T02 [P] Model types `PrewarmAssetKind`, `PrewarmKey`, `PrewarmItem`, `PrewarmLookahead.upcoming(activeIndex:count:depth:)` (next cue and the one after, no wrap; standby → cue 1) and `PrewarmBudget.bytes(physicalMemory:)` (< 4 GB → 48 MB, < 8 GB → 96 MB, else 192 MB) in Packages/PresentationLifecycle/Sources/PresentationLifecycle/PrewarmModel.swift — Verified 2026-11-14: PrewarmSchedulerTests.testLookaheadAndBudget (host, 73/73 package tests pass)
- [X] PERF-005-T03 [P] `PrewarmCache` (Σ bytes ≤ budget; never evict live keys; candidates have rank ≥ incoming rank, least recently used first; if not enough can be freed, drop the incoming item and evict nothing) in Packages/PresentationLifecycle/Sources/PresentationLifecycle/PrewarmCache.swift — Verified 2026-11-14: PrewarmCacheTests (3 tests, host)
- [X] PERF-005-T04 `PrewarmScheduler` with injected executor, clock, loader, budget, settle delay 0.5 s; `plan(_:live:)`, pause reasons, graphics gate, `take`, `releaseForMemoryPressure`, `forwardPresets`, `shutdown`, `lowPower`, stats; default `DispatchPrewarmExecutor` (serial `.utility`) and `DispatchPrewarmClock` in Packages/PresentationLifecycle/Sources/PresentationLifecycle/PrewarmScheduler.swift — Verified 2026-11-14: PrewarmSchedulerTests (10 tests, host)

## Phase 3: User Story 2 - Stale work is cancelled and its memory released (P1)

**Independent test**: heavy fake assets with a live-buffer counter; jump A → C mid-prewarm.

- [X] PERF-005-T05 [US2] Acceptance test: plan A → B → C with fake assets of known sizes; jump from A to C mid-prewarm; B's queued item never starts, its in-flight result is released and the live-buffer counter returns to baseline; held bytes never exceed the budget; live assets are never evicted, in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/PrewarmSchedulerTests.swift — Verified 2026-11-14: PrewarmSchedulerTests.testJumpFromAToCMidPrewarmCancelsBAndReleasesItsBuffers and testHeldBytesNeverExceedTheBudgetAndLiveAssetsSurvive (host)
- [X] PERF-005-T06 [P] [US2] Eviction order test of `PrewarmCache` (LRU among rank ≥ incoming, live pinned, oversized item rejected, peak ≤ budget) in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/PrewarmCacheTests.swift — Verified 2026-11-14: PrewarmCacheTests.testEvictionOrderIsLeastRecentlyUsedAmongNoMoreImportantEntries, testRefusalsChangeNothing, testTakeAndReleaseKeepLiveEntries (host)

## Phase 4: User Story 3 - Prewarming never costs the live frame (P1)

- [X] PERF-005-T07 [US3] Tests in PrewarmSchedulerTests.swift: executor spy (every load on the executor's thread, never the main thread); nothing starts while paused for presentation or thermal; a presentation suspension refuses a pending graphics step and releases non-live entries; settle delay on the injected clock; Low Power keeps rank 0; `forwardPresets` calls through synchronously with no clock use; `releaseForMemoryPressure` releases every non-live entry and reports the bytes (R10) — Verified 2026-11-14: PrewarmSchedulerTests executor spy, pause, suspension, settle, Low Power, preset forwarding, memory pressure tests (host)
- [X] PERF-005-T08 [US3] Preset routing: `AppCoordinator.prewarm` forwards through `MediaPrewarmCoordinator.forwardPresets`; `PresetWarmUpController` and `PresetPrewarmer` unchanged (diff shows no change in Packages/ANGLERendering) in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: `git diff 6b32708e -- Packages/ANGLERendering` is empty; testPresetPicksAreForwardedAtOnceWithoutAnyDelay; PresetTests (19) pass on PERF5

## Phase 5: User Story 1 - The next cue's picture is ready (P1)

- [X] PERF-005-T09 [P] [US1] `ImageLayerSource`: public `decodeStored`, `makeLayerTexture`, `prewarmedTexture` lookup consulted in `content`'s setter, `loadsStarted` counter, in Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift — Verified 2026-11-14: Compositor ImageLayer tests (8) pass on the host
- [X] PERF-005-T10 [P] [US1] Host test: a prewarmed texture is adopted at once (state ready, `loadsStarted` 0); a miss loads as before, in Packages/Compositor/Tests/CompositorTests/ImageLayerPrewarmTests.swift — Verified 2026-11-14: ImageLayerPrewarmTests.testAPrewarmedTextureIsAdoptedWithoutALoad (host Metal)
- [X] PERF-005-T11 [US1] `MediaPrewarmCoordinator` (presentation-bound, PERF-006 cache responder, thermal and Low Power observer) and `PhotoPrewarmLoader` (decode off main, texture in the graphics gate, decode counter) in Apps/projectM-iOS/Coordinators/MediaPrewarmCoordinator.swift — Verified 2026-11-14: app build on PERF5 (no new warnings); MemoryPressureAppTests, BackgroundPolicyAppTests, LifecycleCoordinatorTests pass
- [X] PERF-005-T12 [US1] Wiring: replan at connect and after every applied cue (scene photo URL = slideshow first slide or the stored photo; live key = the live photo URL); each new Photo visual gets the lookup; register presentation and memory pressure, in Apps/projectM-iOS/Coordinators/AppCoordinator+Prewarm.swift (one-line hooks in AppCoordinator.swift and AppCoordinator+Show.swift) — Verified 2026-11-14: MediaPrewarmAppTests, ShowCoordinatorTests (8), CueTransitionAcceptanceTests (3) and ShowCueUITests.testFiveCuesStepDeterministicallyWithoutRestartingTheSource (20 s) pass on PERF5
- [X] PERF-005-T13 [US1] App test: stepping cues A (spectrum) → B (photo) prewarms B's photo with a decode count of 1; applying B reuses the decoded texture (photo layer `loadsStarted` 0, ready at once), in Apps/projectM-iOS/Tests/MediaPrewarmAppTests.swift — Verified 2026-11-14: MediaPrewarmAppTests.testSteppingCuesPrewarmsTheNextPhotoOnceAndApplyingReusesIt on PERF5 (0.98 s)

## Phase 6: Polish

- [X] PERF-005-T14 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), Linux shape of PresentationLifecycle, type-check budget, privacy manifest and network symbols on the Debug app; PosterBoard counts — Verified 2026-11-14: six repo checks exit 0 (159 script tests), check_privacy_manifest and check_network_symbols OK on the Debug app, no type-check warning in changed files; Linux shape not run here (no Linux host): plain Foundation/Dispatch only, pending CI
- [ ] PERF-005-T15 {device} On D1: step a show with photo cues; no frame-rate change versus without prewarm and the photo is on the first frame of the cue

## Dependencies

T01 → T02, T03 → T04 → T05-T07; T09 → T10; T04, T09 → T11 → T12 → T13; T08 after T11; T14 last. US2 and US3 depend only on the core; US1 needs the core and the layer change.

## Parallel examples

T02 and T03; T05/T06 and T09/T10.

## Implementation strategy

Core first (US2 is the roadmap acceptance), then the frame guarantees (US3), then the app path (US1).

## Analysis (speckit-analyze, 2026-11-14)

Applied: R3 cited a non-existent "R-D3" (now research PERF-005-D3); R6 and the data model named a memory-pressure
pause reason that no requirement uses (R10 releases instead; removed); R10 had no test (added to T07). Coverage:
R1-R13 and S1-S6 each map to at least one task; no constitution conflicts; no open placeholders.
