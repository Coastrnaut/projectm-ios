# Tasks: MED-004 Video Playback Speed

**Input**: `specs/124-med-004-video-playback-speed/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MED-004-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1.

## Phase 1: Setup

- [ ] MED-004-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MED4 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] MED-004-T02 [P] `VideoPlaybackSpeed` (plain Swift; `percent: Int`, "One of 25, 50, 75, 100, 125, 150, 200 (`init?(percent:)` rejects others)", `.normal`, `all` ascending, `isNormal`, `prerollLeadNanoseconds` = 500 000 000 × max(percent, 100) / 100; contract C1) in `Packages/Compositor/Sources/VideoLayer/VideoPlaybackSpeed.swift`
- [ ] MED-004-T03 `VideoPlaybackClock` speed: exact integer scaling with the carried remainder (research MED-004-D2), `setSpeed(_:)` keeping the playback time and zeroing the measurement window, `presentationSinceSpeedChange`, `playbackSinceSpeedChange`, `reset()` keeping the speed (contract C2) in `Packages/Compositor/Sources/VideoLayer/VideoPlaybackClock.swift`
- [ ] MED-004-T04 Package tests `Packages/Compositor/Tests/CompositorTests/VideoSpeedTests.swift` (plain Swift, also in the Linux shape): the speed set (C1); **the acceptance** on an injected 60 Hz clock: 2 s of presentation advance 1 s at 0.5× (within one 1/30 s picture interval; exact here), 2 s at 1×, 4 s at 2× (MED-004-S1); the remainder carry over odd steps (no drift); steps over 1 s add nothing at every speed

## Phase 3: User Story 1 - Slow the video down or speed it up (P1) — MVP

**Independent test**: an index-encoded fixture at 0.5×, 1× and 2× on an injected clock shows the picture of the expected video time; relaunch keeps the speed; the audio source is untouched.

- [ ] MED-004-T05 [US1] `VideoDecodePipeline.speed` / `setSpeed(_:)` (the session reads its pre-roll lead under its lock; no restart) and `VideoLayerSource.playbackSpeed` (clock + pipeline; never stops, starts or seeks the decoder) in `Packages/Compositor/Sources/VideoLayer/VideoFrameQueue.swift` and `VideoLayerSource.swift` (contract C3.1-C3.3)
- [ ] MED-004-T06 [US1] Real-file test in `Packages/Compositor/Tests/CompositorTests/VideoLayerTests.swift`: the H.264 counter fixture at 0.5× and 2× through the Metal compositor: the pixel index shown at each injected presentation time equals ⌊video time × 30⌋ mod 30, and `playbackNanoseconds` after 2 s of presentation is 1 s / 4 s (MED-004-S1, R9)
- [ ] MED-004-T07 [US1] `VideoStore` speed key `settings.video.speed` (`{id, percent}`; ID must match and percent be in the set; 1× removes; removed by `remove()` and by `makeCurrent` of another ID) in `Apps/projectM-iOS/Coordinators/VideoStore.swift`; listed in `AppSettings.allKeys` and `ALLOWED_KEYS` in `scripts/run_device_tests.py` (MED-004-R6)
- [ ] MED-004-T08 [US1] Backup and erase policy: `settings.video.speed` in `LibrarySettingsPolicy.excludedKeys` (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`) and `LibraryErasePolicy.videoSpeedKey` in the media category (`LibraryErasePolicy.swift`), with the package's policy tests updated (MED-004-R6, S5)
- [ ] MED-004-T09 [US1] `VideoCoordinator.speed`, `setSpeed(_:)`, `onSpeedChange` (at once), speed reloaded on a new video; `VideoVisualHost.playbackSpeed` and the `speedProbe` text; `AppCoordinator` wiring (speed at host creation, on a new video, on change) in `Apps/projectM-iOS/Coordinators/VideoCoordinator.swift`, `AppCoordinator.swift`, `Apps/projectM-iOS/Visuals/VideoVisualHost.swift` (contract C4.2)
- [ ] MED-004-T10 [US1] `VideoSpeedControls` (menu `Picker` "Speed", identifier `videoSpeedPicker`, options "0.25×"…"2×" with spoken labels per research MED-004-D7 built in typed steps; small bodies; no animation) in `Apps/projectM-iOS/Views/VideoSpeedControls.swift`, mounted above `VideoLoopControls` in `SettingsView.videoSection` when a video is stored; footer sentence "Speed changes only the video, never the music." (MED-004-R8)
- [ ] MED-004-T11 [US1] DEBUG probe `videoSpeed` ("<percent> ratio=<x.xxx>", contract C4.5) in `Apps/projectM-iOS/Views/VisualizerView.swift` (MED-004-R11)
- [ ] MED-004-T12 [US1] App tests `Apps/projectM-iOS/Tests/VideoSpeedTests.swift`: store per ID, foreign ID and bad percent ignored, remove and new video clear; coordinator saves and applies at once; spoken labels; the audio source untouched by every speed change (capture manager mode and the In-App Playback transport unchanged; MED-004-S4); `LibraryEraseAppTests`-style key identity (`LibraryErasePolicy.videoSpeedKey == VideoStore.speedKey`)
- [ ] MED-004-T13 [US1] UI test `Apps/projectM-iOS/UITests/VideoSpeedUITests.swift` (`-uitestSeedVideo counter`): choose 0.5× in Settings → Video, then read `videoSpeed`: percent 50 and ratio 0.5 ± 0.05, and `videoFrameIndex` keeps advancing (MED-004-S6; under 30 s)

## Phase 4: User Story 2 - Change speed live without a jump (P1)

**Independent test**: a speed change mid-play keeps the video time continuous and does not restart the decoder.

- [ ] MED-004-T14 [US2] Tests in `VideoSpeedTests.swift`: clock continuity at a change (the first step after it adds exactly step × new speed); the pipeline with the fake reader: `setSpeed` mid-play causes no new open and no seek, and the pictures taken stay in order (MED-004-S2, R4)

## Phase 5: User Story 3 - Speed and the loop region work together (P2)

**Independent test**: loop wraps at 0.5× and 2× stay inside the region with gap 0 at the fake reader.

- [ ] MED-004-T15 [US3] Pre-roll lead from the speed in the decode session (`VideoFrameQueue.swift`: `regionOut - pts <= lead`, lead = `speed.prerollLeadNanoseconds`; research MED-004-D3, contract C3.2)
- [ ] MED-004-T16 [US3] Tests in `VideoSpeedTests.swift` with `LoopFakeReader`: region [0.5 s, 1.0 s) at 0.5× and 2× across at least three boundaries: every taken picture inside, wrap from out−1 to in, lateness < one video-time picture interval at the speed's step (gap 0 frames); at 2× the first preparation happens when the read picture is within 1 s of out (MED-004-S3, R5)

## Phase 6: Scenes, undo and show cues (MED-004-R7)

- [ ] MED-004-T17 [P] `SceneAsset.videoSpeedPercent` (contract C5.1) in `Packages/SceneFormat/Sources/SceneFormat/SceneVideoLoop.swift` with tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneVideoLoopTests.swift` (get, set, nil removes, other kinds, malformed values, carried verbatim)
- [ ] MED-004-T18 Scene carriers and bridge: `videoSpeedPercent` on `SceneInputs`, `SceneRestoredValues`, `ShowLook`, `ShowSceneApply`; `SceneVideoLoopBridge.asset(storeID:loop:speedPercent:)` and `video(in:)` returning it; `VideoCoordinator.restoreSpeed(storeID:speedPercent:)` next to every `restoreLoop` call (launch restore, reopen, undo, cue) in `Apps/projectM-iOS/Coordinators/*.swift`; round-trip tests in `VideoSpeedTests.swift`

## Phase 7: Polish & cross-cutting

- [ ] MED-004-T19 Linux shape: `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'VideoSpeedTests|VideoLoopTests|VideoPipelineTests'`
- [ ] MED-004-T20 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py` on the built Debug app; long-body type-check flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) report nothing in the new files
- [ ] MED-004-T21 App unit tests (projectM-iOSTests) and UI tests VideoLayerUITests, VideoLoopUITests, VideoSpeedUITests on the own simulator; PosterBoard count after; delete the simulator; report `docs/test-reports/video-playback-speed.md`; spec status updated
- [ ] MED-004-T22 `{device}` On D1 (MED-004-S7): a picked clip at 2× keeps up or drops late pictures without slowing down; 0.25× looks smooth; the In-App Playback music is unchanged at every speed

## Dependencies

- T01 → everything. T02 → T03 → T04, T05. T05 → T06, T09, T14, T15. T07 → T09 → T10, T11, T12, T13. T08 independent after T07's key name. T15 → T16. T17 → T18. T19-T21 after all code; T22 after release to the device stage.
- Stories: US1 (T05-T13) is the MVP; US2 (T14) and US3 (T15-T16) depend only on T05.

## Parallel examples

- T02 and T17 (different packages); T08 with T09 (different packages); T14 and T16 are one test file, so not parallel.

## Implementation strategy

MVP = Phases 1-3 (speed on the clock, the layer, storage and the picker). Then continuity tests
(US2), the loop interaction (US3), scenes, and the polish checks. One commit per complete change.
