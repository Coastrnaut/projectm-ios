# Tasks: MED-003 Video Loop Region

**Input**: `specs/106-med-003-video-loop-region/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MED-003-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1.

## Phase 1: Setup

- [ ] MED-003-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MED3 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] MED-003-T02 [P] `VideoLoopRegion` (plain Swift; `inNanoseconds`, `outNanoseconds`, `minimumLengthNanoseconds` = 250 000 000, `init(inMilliseconds:outMilliseconds:)`, `inMilliseconds`/`outMilliseconds`, `effective(duration:)` per research MED-003-D1, `whole(duration:)`, `isWholeFile(duration:)`, `contains(_:)` with in ≤ t < out, `length`) in `Packages/Compositor/Sources/VideoLayer/VideoLoopRegion.swift`
- [ ] MED-003-T03 Reader seam and pipeline in `Packages/Compositor/Sources/VideoLayer/VideoFrameQueue.swift`: defaulted `open(startNanoseconds:endNanoseconds:)` and `prepare(startNanoseconds:endNanoseconds:)`; `TimedFrame.mediaNanoseconds`; statistics `earlyEnds`, `recoveredErrors`, `prepared`; `start(atNanoseconds:region:mediaStartNanoseconds:)`; the session's region timeline (`base + k × L + (pts − in)`), skip before in with the covering-picture fallback, pass end at out, preparation within 0.5 s of out, recovery and the three-bad-passes rule (research MED-003-D2 to D4)
- [ ] MED-003-T04 Package tests `Packages/Compositor/Tests/CompositorTests/VideoLoopTests.swift` (plain Swift, also in the Linux shape) with a recording fake reader: the clamping table (MED-003-S3); four boundaries with every taken index inside the region, wrap from out−1 to in, playback times continuous, gap 0 frames (S1); every `open` start inside the region; whole-file region equals MED-002; update MED-002's error test in `VideoPipelineTests.swift` to the recovery rule (research D4)

## Phase 3: User Story 1 - Loop only the part of the clip I want (P1) — MVP

**Independent test**: an index-encoded fixture with a region: every shown picture inside across boundaries; relaunch keeps the region; Reset restores the whole file.

- [ ] MED-003-T05 [US1] `AVVideoFrameReader`: `timeRange = [start, end)`, one prepared standby reader swapped in on a matching open, container check before every open (MED-014), in `Packages/Compositor/Sources/VideoLayer/AVVideoFrameReader.swift`
- [ ] MED-003-T06 [US1] `VideoLayerSource.loopRegion`, `shownMediaNanoseconds`, `mediaDurationNanoseconds`, `wraps`, `maxWrapLatenessNanoseconds`; content start and resume pass the region (resume at the shown picture), in `Packages/Compositor/Sources/VideoLayer/VideoLayerSource.swift`
- [ ] MED-003-T07 [US1] Real-file test in `Packages/Compositor/Tests/CompositorTests/VideoLayerTests.swift`: fixture with a region, pixels by index across at least three boundaries all inside, `wraps` ≥ 3 and the gap 0 frames when the decoder keeps up (MED-003-S1)
- [ ] MED-003-T08 [US1] `VideoStore` loop key `settings.video.loop` (`{id, inMilliseconds, outMilliseconds}`; ID must match; removed by `remove()` and by `makeCurrent` of another ID) in `Apps/projectM-iOS/Coordinators/VideoStore.swift`; listed in `AppSettings.allKeys` (`Apps/projectM-iOS/Coordinators/AppSettings.swift`) and `ALLOWED_KEYS` in `scripts/run_device_tests.py`
- [ ] MED-003-T09 [US1] `VideoCoordinator`: `loopRegion`, `durationNanoseconds`, `setLoop(inSeconds:)`, `setLoop(outSeconds:)`, `resetLoop()`, `commitLoop()`, `onLoopRegionChange` after 0.4 s or on commit; `AppCoordinator` and `VideoVisualHost` wiring (region at host creation and on change, duration on play) in `Apps/projectM-iOS/Coordinators/VideoCoordinator.swift`, `AppCoordinator.swift`, `Apps/projectM-iOS/Visuals/VideoVisualHost.swift`
- [ ] MED-003-T10 [US1] `VideoLoopControls` (In and Out sliders 0…duration step 0.1 s, times, Reset Loop; labels "Loop in"/"Loop out", values "1.5 seconds"; small bodies, no animation) in `Apps/projectM-iOS/Views/VideoLoopControls.swift`, mounted in `SettingsView.videoSection`
- [ ] MED-003-T11 [US1] DEBUG probes `videoMediaFrameIndex`, `videoLoopRegion`, `videoLoopStats` in `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] MED-003-T12 [US1] App tests `Apps/projectM-iOS/Tests/VideoLoopTests.swift`: store per ID, foreign ID ignored, remove and new video clear; coordinator clamping (minimum, past the end), save at once, settle then apply (MED-003-R7, R9, R10)
- [ ] MED-003-T13 [US1] UI test `Apps/projectM-iOS/UITests/VideoLoopUITests.swift` (`-uitestSeedVideo counter`): set In and Out in Settings → Video, then sample `videoMediaFrameIndex` for a few seconds: every index inside `videoLoopRegion`; record `videoLoopStats` (MED-003-S6; under 30 s)

## Phase 4: User Story 2 - Edit the region while it plays (P1)

**Independent test**: region changes mid-play never show a picture outside the new region.

- [ ] MED-003-T14 [US2] Pipeline/layer tests in `VideoLoopTests.swift`: edit out and in mid-play (continue when inside, else in), stall seek and resume inside the region (MED-003-S2, R10)

## Phase 5: User Story 3 - A bad ending never stops the loop (P2)

**Independent test**: injected early end and reader error continue at in and are counted.

- [ ] MED-003-T15 [US3] Tests in `VideoLoopTests.swift`: an early end and a reader error near the end continue at in, counted, state running; three bad passes fail; a refused open fails as before (MED-003-S4, R5, R6)

## Phase 6: Scenes and show cues (MED-003-R8)

- [ ] MED-003-T16 [P] `SceneVideoLoop` and `SceneAsset.videoLoop` in `Packages/SceneFormat/Sources/SceneFormat/SceneVideoLoop.swift`; tests `Packages/SceneFormat/Tests/SceneFormatTests/SceneVideoLoopTests.swift` (round trip, malformed → nil, absent field byte-identical re-save)
- [ ] MED-003-T17 `SceneInputs.videoLoop`, `ShowLook.videoLoop` written to the video asset; restore, undo and show apply it when the video matches, in `Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift`, `ShowSceneSnapshot.swift`, `AppCoordinator.swift`, `AppCoordinator+SceneHistory.swift`, `AppCoordinator+Show.swift`; tests in `Apps/projectM-iOS/Tests/VideoLoopTests.swift` (MED-003-S5)

## Phase 7: Polish & cross-cutting

- [ ] MED-003-T18 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; full `projectM-iOSTests` plus `VideoLayerUITests` and `VideoLoopUITests`; PosterBoard count after; delete the simulator
- [ ] MED-003-T19 Report `docs/test-reports/video-loop-region.md` (audit, measured gap, counts, commands) and spec status
- [ ] MED-003-T20 {device} D1: pick a clip with the system picker, set a region, five joints with no visible stall, background/relaunch inside, Reset (MED-003-S7)

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06) → T07; T08 → T09 → T10 → T11 → T12 → T13; T14, T15 after T06;
T16 → T17 after T09; T18 → T19 last; T20 after integration.

## Parallel opportunities

T02 and T16 (different packages); T08 and T05 (app vs package); T14 and T15 (same file: one writer).

## Implementation strategy

MVP = Phases 1-3 (region plays, persists, UI). Then US2/US3 tests (the code is in T03/T06), then
scenes, then checks and the report.
