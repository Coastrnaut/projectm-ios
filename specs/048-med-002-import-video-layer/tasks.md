# Tasks: MED-002 Import Video Layer

**Input**: Design documents from `specs/048-med-002-import-video-layer/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/video-layer.md,
quickstart.md

**Tests**: Requested by the roadmap row ("simulator fixture media + device picker") and owner rule 7
budgets: a unit test about 1-2 s and at most 10 s, the package suite under 1 minute, a UI test
under 30 s, GPU tests at 64 × 64. Fixtures are generated in the tests (no media files checked in);
timing uses a fake clock (no wall-clock assertions).

**Format**: `[ID] [P?] [Story] Description`. `{device}` = needs D1-D3 and a person (system pickers
cannot be automated; simulator results are never device evidence); left open by this row.

## Phase 1: Setup

- [X] MED-002-T01 Baseline: run `swift test --package-path Packages/Compositor` before any change and record the pass count (no file change) — Verified 2026-11-13: `swift test --package-path Packages/Compositor` at `ce6fe27`: CompositorTests 134/134, ProceduralMaterialsTests 31/31, GeneratorGraphTests 46 (1 skipped)
- [X] MED-002-T02 Add target `VideoLayer` (dependencies `Compositor`, `CameraLayer`) to the `Compositor` library product and to the `CompositorTests` dependencies in `Packages/Compositor/Package.swift`; header comment line for the target — Verified 2026-11-13: `swift build`/`swift test` of the package with the new target, no warnings in VideoLayer

## Phase 2: Foundational (blocks every story)

- [X] MED-002-T03 [P] `VideoImportLimits` (`maxFileBytes` 500 × 1024 × 1024, `maxLongestSide` 4096, `maxFrameRate` 60.5; `.standard`), `VideoCodec` (`h264` from `avc1`/`avc3`, `hevc` from `hvc1`/`hev1`), `VideoImportError` (`notAVideo`, `tooLarge`, `unsupportedCodec`, `pictureTooLarge`, `frameRateTooHigh`, `damaged`, `unreadable`, `saveFailed`, each with a plain `message`) and `VideoTrackInfo` (width, height, rotation `CameraRotation`, frameRate, durationNanoseconds, codec; upright size; `check(limits)`) in `Packages/Compositor/Sources/VideoLayer/VideoImportLimits.swift` (plain Swift) — Verified 2026-11-13: VideoPipelineTests.testLimitsCodecsAndMessages (host and Linux shape)
- [X] MED-002-T04 [P] `VideoPlaybackClock` (integer ns; first call 0; Δ in (0, 1 s] adds Δ; Δ > 1 s or ≤ 0 adds 0; `reset()`) in `Packages/Compositor/Sources/VideoLayer/VideoPlaybackClock.swift`, and `LayerKind.video` (`video`, maximumInstances 1) in `Packages/Compositor/Sources/VideoLayer/VideoLayerKind.swift` (plain Swift) — Verified 2026-11-13: VideoPipelineTests.testClockStartsAtZeroAndAdvancesByPresentationSteps (host and Linux shape)
- [X] MED-002-T05 `VideoFrameReading` protocol (the MED-014 seam), `TimedFrame`, `VideoPipelineStatistics`, `VideoPipelineState` and `VideoDecodePipeline<Reader>` (capacity 3 by a counting semaphore; `NSLock` queue, `try()` on the render side; `take(upTo:)` drops older frames ≤ t; unwrapped timeline `loop × duration + pts`; reopen at 0 at end of file; seek when the target is > 1 s past the next expected timestamp; `stop()` cancels; `waitUntilIdle(timeout:)` for tests; a loop that yields no picture → `.failed(.damaged)`) in `Packages/Compositor/Sources/VideoLayer/VideoFrameQueue.swift` (plain Swift, Foundation + Dispatch only) — Verified 2026-11-13: VideoPipelineTests 8/8 (host 0.25 s; Linux shape)
- [X] MED-002-T06 [P] Pure tests with a fake reader (Int frames, 30 fps, 60 frames) and fake clock: frame for time exact over two loops (S1); `maxDepth ≤ 3` through playback, a 5 s stall, a 10 s jump and stop (S2); late frames counted as dropped and never returned after a newer one; seek counted on a jump; end-of-file loops; a reader error → failed state; clock rules (first frame 0, gap > 1 s, backwards time); limits and error messages, in `Packages/Compositor/Tests/CompositorTests/VideoPipelineTests.swift` (runs in the Linux shape) — Verified 2026-11-13: VideoPipelineTests 8/8 on the host and in the Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`: CompositorTests 83/83)

## Phase 3: User Story 1 - Choose a video and see it play (P1) — MVP

**Goal**: import (checks, remux) and the video layer drawing the picture for the playback time (R1-R5, R9, R12, R15, R16, S1, S3, S5).

**Independent Test**: package tests with a generated fixture; the app's seeded fixture plays in the UI test.

- [X] MED-002-T07 [P] [US1] `VideoProbe.check(_:limits:)` (file size via `.fileSizeKey` before opening; a video track; codec FourCC; natural size; `preferredTransform` → `CameraRotation`; nominal frame rate; duration > 0; first sample decodes through `AVAssetReader`) in `Packages/Compositor/Sources/VideoLayer/AVVideoProbe.swift` (`#if canImport(AVFoundation)`) — Verified 2026-11-13: VideoImportTests.testProbeReadsTheTrackFacts, testRefusalsAreTyped
- [X] MED-002-T08 [US1] `VideoSanitizer.copy(_:to:limits:)` (probe, then `AVMutableComposition` with the video track only and its `preferredTransform`, `AVAssetExportSession` passthrough to `.mov`, `metadata = []`, `metadataItemFilter = .forSharing()`; any failure → `.saveFailed` and no file left) in `Packages/Compositor/Sources/VideoLayer/VideoSanitizer.swift` — Verified 2026-11-13: VideoImportTests.testSanitizedCopyDropsSoundtrackAndMetadataAndKeepsRotation, testSanitizerRefusesWithTheProbeReasonAndLeavesNoFile
- [X] MED-002-T09 [US1] `AVVideoFrameReader` (`VideoFrameReading` with `AVAssetReaderTrackOutput` 32BGRA, `alwaysCopiesSampleData = false`, `timeRange` from the start; each buffer wrapped by a `CVMetalTextureCache` as `.bgra8Unorm_srgb`; frame = texture + its CV wrapper) in `Packages/Compositor/Sources/VideoLayer/AVVideoFrameReader.swift` (AVFoundation + Metal) — Verified 2026-11-13: VideoLayerTests (5/5) play through it; the reader's texture reads back the decoder's code
- [X] MED-002-T10 [US1] `VideoLayerSource` (`LayerSource`, name `video`, transparent fallback; `content` `.none`/`.file(URL)`; state empty/loading/playing/failed with `onStateChange` on the main actor; `render` advances the clock, sets the pipeline target, takes the frame, draws aspect fill with rotation via `CameraPictureGeometry`, alpha 1; `.notReady` without a frame; `suspendDecoding()`; `framesShown`, `shownPresentationNanoseconds`, `statistics`) in `Packages/Compositor/Sources/VideoLayer/VideoLayerSource.swift` — Verified 2026-11-13: VideoLayerTests 5/5 on the host (Metal)
- [X] MED-002-T11 [P] [US1] Fixture writer (`AVAssetWriter` H.264, 64 × 48, 30 fps, 2 s, frame i a solid color encoding i; options: audio track, location and creation-date metadata, rotation) in `Packages/Compositor/Tests/CompositorTests/VideoFixtures.swift` — Verified 2026-11-13: used by VideoImportTests and VideoLayerTests (host)
- [X] MED-002-T12 [US1] Import tests: probe reads size, rate, duration, codec; non-video, truncated/corrupt, over-size, over-rate (fixture at 120 fps), over-size picture (limits lowered) refused with their typed error; remuxed copy has no audio track, no metadata, the original's location and date strings absent from its bytes, the rotation kept (S5, S7) in `Packages/Compositor/Tests/CompositorTests/VideoImportTests.swift` — Verified 2026-11-13: VideoImportTests 4/4 on the host (0.55 s)
- [X] MED-002-T13 [US1] Layer tests through the real compositor at 64 × 64 with injected presentation times: shown picture index = ⌊t × 30⌋ at sampled times over a loop (S1); a solid frame's linear readback within 1/255 of the decoded code's linear value (S3); a corrupt stored copy → transparent fallback, `.failed(.damaged)`, the compositor keeps drawing (S7); `maxDepth ≤ 3` in Packages/Compositor/Tests/CompositorTests/VideoLayerTests.swift — Verified 2026-11-13: VideoLayerTests.testPicturesFollowTheTimelineAtTheIntendedRate, testSolidPictureReadsBackLinear, testDamagedCopyFallsBackTransparentWithTypedError (host)

## Phase 4: User Story 2 - Smooth and bounded (P1)

**Goal**: pause, background and teardown keep the bound (R10, R11, R13, S2).

- [X] MED-002-T14 [US2] Layer tests: a 5 s gap continues from the same picture (pause rule); `suspendDecoding()` releases the queue and playback resumes at the same playback time; changing content stops the old session, in `Packages/Compositor/Tests/CompositorTests/VideoLayerTests.swift` — Verified 2026-11-13: VideoLayerTests.testPauseAndSuspendContinueFromTheSamePicture, testNewContentRestartsAndRotationIsUpright (host); full suite CompositorTests 151/151 twice

## Phase 5: User Story 3 - App: store, visual, persistence, remove (P1)

**Goal**: the Video visual in the app (R1-R3, R6-R8, R13, R14, R17-R20, S4, S6).

- [X] MED-002-T15 [US3] `VideoStore` (`Application Support/Videos/<UUID>.mov`; `settings.video.id`; canonical UUID only; picked file read once under its security scope with a coordinated copy to a temporary file, then `VideoSanitizer`; replace deletes the previous copy after the new one is saved; `remove()`) in `Apps/projectM-iOS/Coordinators/VideoStore.swift` — Verified 2026-11-13: VideoStoreTests 8/8 on the iOS 27.2 simulator (MED2 iPhone 17)
- [X] MED-002-T16 [US3] `VideoCoordinator` (Photos picker item as a movie file through `Transferable`, Files picker result, one import at a time off the main actor, notice for 6 s, Remove Video, `storedCopyFailed()`; DEBUG `importNow`) in `Apps/projectM-iOS/Coordinators/VideoCoordinator.swift` — Verified 2026-11-13: VideoStoreTests (remove, refusals, cancel) on the simulator
- [X] MED-002-T17 [US3] `VideoVisualHost` (video layer under the circular spectrum through `LayerStack`; frame loop only while shown and not paused; `suspendDecoding()` on background and scene disconnect; accessibility label "Video visualization", identifier `videoVisual`, value "No video"/"Loading"/"Video W × H"/"Couldn't play the video") in `Apps/projectM-iOS/Visuals/VideoVisualHost.swift` — Verified 2026-11-13: VideoLayerUITests (VoiceOver value "Video 64 × 48", frames advance) on the simulator; `build-for-testing` with no warnings in the Video files
- [X] MED-002-T18 [US3] App wiring: `Visual.video` ("Video", persisted, `usesVideo`), `AppSettings.videoIDKey` in `allKeys`, `AppCoordinator` creates/releases the host, pauses/resumes, maps state to the coordinator, UI-test reset deletes the folder; Settings "Video" section (Choose from Photos… with `.videos`, Choose from Files… with movie types, Remove Video, summary, notice, footer); diagnostics static texts `videoFramesShown` and `videoFrameIndex` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`, `AppSettings.swift`, `Views/SettingsView.swift`, `Views/VisualizerView.swift` — Verified 2026-11-13: build on the simulator; VideoLayerUITests chooses Video through Settings; CameraVisualTests updated for the new choice; projectM-iOSTests 200/201 (only the known worktree PresetTests failure)
- [X] MED-002-T19 [P] [US3] DEBUG `-uitestSeedVideo counter` (generates the 64 × 48, 30 fps, 2 s fixture with `AVAssetWriter` in the temporary folder and imports it through `VideoStore`) in `Apps/projectM-iOS/Debug/UITestVideoFixture.swift` — Verified 2026-11-13: VideoLayerUITests seeds through it; VideoStoreTests use its writer for picked files
- [X] MED-002-T20 [US3] Store tests (import copies and sets the identifier; a refused file leaves the previous video; replace deletes the old copy; remove; invalid and path-like identifiers ignored and cleared; relaunch resolves the same copy) in `Apps/projectM-iOS/Tests/VideoStoreTests.swift`; update `SettingsTests` for the new key — Verified 2026-11-13: VideoStoreTests 8/8 (0.002-0.62 s each) and SettingsTests on the simulator
- [X] MED-002-T21 [US3] UI test: seed, choose Video, frame index advances, relaunch without the seed still advances, Remove Video → "No video" in `Apps/projectM-iOS/UITests/VideoLayerUITests.swift` — Verified 2026-11-13: VideoLayerUITests.testImportedVideoPlaysAfterRelaunchAndCanBeRemoved passed (21.2 s) on the simulator

## Phase 6: User Story 4 - Broken files (P2)

- [X] MED-002-T22 [US4] Coordinator test: a corrupt pick shows the "couldn't be read" notice and keeps the stored video, in `Apps/projectM-iOS/Tests/VideoStoreTests.swift` — Verified 2026-11-13: VideoStoreTests.testARefusedImportShowsTheNoticeAndKeepsTheStoredVideo, testAFileOverTheSizeLimitIsRefusedBeforeItIsCopied

## Phase 7: Polish & cross-cutting

- [X] MED-002-T23 ADR (next free number) for the imported video layer (decoder choice, queue, clock, remux, audio dropped), `docs/adr/README.md` row — Verified 2026-11-13: `docs/adr/0022-imported-video-layer.md` (0022 was left for MED-002 by OUT-001 and SHD-011) and its README row; `validate_docs.py` OK
- [X] MED-002-T24 [P] Privacy docs: `docs/privacy-policy.md` (imported videos) and `docs/release/app-privacy.md` (Data Not Collected; owner confirms in App Store Connect) — Verified 2026-11-13: `docs/privacy-policy.md` ("A video you choose", summary, permissions, stored data, traceability row) and `docs/release/app-privacy.md` (MED-002 paragraph); `validate_docs.py` OK
- [X] MED-002-T25 Checks: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/check_privacy_manifest.py` on the Debug simulator app; Linux shape of the package; `xcodebuild test -scheme Compositor` once on the simulator; regression run of `projectM-iOSUITests/PhotoLayerUITests` and `projectM-iOSUITests/CameraUITests` with the app unit tests and `VideoLayerUITests`; the built app's Info.plist has no `NSPhotoLibraryUsageDescription` (S8); PosterBoard report count before and after; test report `docs/test-reports/video-layer.md` — Verified 2026-11-13: check_compliance OK, validate_docs OK, check_privacy_manifest OK on the Debug simulator app, no NSPhotoLibraryUsageDescription; Linux shape 83/83; `xcodebuild test -scheme Compositor` 151/151 on the simulator; app unit 200/201 (known PresetTests) and Video, Photo, Camera UI tests pass; PosterBoard 32 → 32; `docs/test-reports/video-layer.md`
- [ ] MED-002-T26 {device} (open: needs D1/D3 and the owner) Photos and Files picks on D1 and D3 (HEVC from the camera, an H.264 file), no permission prompt, Remove Video, relaunch
- [ ] MED-002-T27 {device} (open: needs D1/D3 and the owner) 4K60 HEVC and a long (≥ 10 min) file play at their rate on D1 and D3; memory stays bounded (Xcode memory gauge)
- [ ] MED-002-T28 {device} (open: needs D1/D3 and the owner) Thermal state over 3 minutes of 4K playback on D1 and D3 (`ProcessInfo.thermalState` stays below serious), frame rate recorded

## Dependencies

T01 → T02 → T03-T05 → T06; T07-T11 need T03/T05; T12 needs T07, T08, T11; T13-T14 need T09-T11;
US3 (T15-T21) needs T08 and T10; T22 needs T16; Polish after the stories; device tasks last.

## Parallel examples

T03 and T04 in parallel; T07 and T11 in parallel; T19 alongside T15-T17.

## Implementation strategy

MVP = Phases 1-3 (package import and layer), then US2 tests, then the app (US3), then the polish.
