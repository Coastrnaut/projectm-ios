# Tasks: REC-003 Video Recording

**Input**: design documents in `specs/058-rec-003-video-recording/` (spec, plan, research,
data-model, contracts/video-recording.md, quickstart).

**Tests**: requested by the spec (REC-003-S1 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] REC-003-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Setup

- [X] REC-003-T01 Add target `FrameRecording` (no dependencies) and test target `FrameRecordingTests` (depends on `FrameRecording`) to `Packages/Compositor/Package.swift`; list it in the `Compositor` library product; `CompositorTests` gains `FrameRecording`; header comment names REC-003 — Verified 2026-11-13: `swift test --package-path Packages/Compositor` on the Mac host (8 bundles, 333 tests, 1 skipped, 0 failures, 13 s for CompositorTests; FrameRecordingTests 21/21 in 0.32 s)

## Phase 2: Foundational (blocks every story)

- [X] REC-003-T02 [P] `RecordingCodec` (`hevc`, `h264`; title, four-character code), `RecordingSettings` (`maxFrameRate` 30 "1...60", `maxLongSide` 1920 "≥ 16, even", `maxDurationSeconds` 600, `framesInFlight` 3 "≥ 1", `codecPreference` [.hevc, .h264], static `timescale` 600, `frameIntervalTicks`), `RecordingGeometry(drawableWidth:drawableHeight:maxLongSide:)` (source = drawable rounded down to even; output = fit `maxLongSide`, even, ≥ 2; nil below 2 × 2), in `Packages/Compositor/Sources/FrameRecording/RecordingSettings.swift` — Verified 2026-11-13: `swift test --package-path Packages/Compositor` on the Mac host (8 bundles, 333 tests, 1 skipped, 0 failures, 13 s for CompositorTests; FrameRecordingTests 21/21 in 0.32 s); Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) FrameRecordingTests 15/15
- [X] REC-003-T03 [P] `RecordingTimeline` per research REC-003-D4 (`admit` order: not increasing → duration reached → rate skip with interval/4 tolerance → candidate; `markWritten`; `endTick` = last + interval; ticks rounded to nearest 1/600 s from the first admitted frame), in `Packages/Compositor/Sources/FrameRecording/RecordingTimeline.swift` — Verified 2026-11-13: RecordingRulesTests 15/15 on the host and in the Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) FrameRecordingTests 15/15
- [X] REC-003-T04 [P] `RecordingFrameGate` (`Mutex`; `tryAcquire`, `release`, `inFlight`, `maxInFlight`) and `RecordingStatistics` (`written`, `droppedBusy`, `droppedNotReady`, `droppedNotIncreasing`, `skippedRate`, `dropped`), in `Packages/Compositor/Sources/FrameRecording/RecordingFrameGate.swift` — Verified 2026-11-13: RecordingRulesTests (gate, statistics) on the host and in the Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) FrameRecordingTests 15/15
- [X] REC-003-T05 [P] `RecordingStopReason`, `RecordingRefusal`, `RecordingFailure` with the notices of contracts/video-recording.md, `RecordingGate.refusal(visualAvailable:recordable:outputLive:paused:busy:)`, `RecordedVideo`, in `Packages/Compositor/Sources/FrameRecording/RecordingOutcome.swift` — Verified 2026-11-13: RecordingRulesTests (refusal order, notices) on the host and in the Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) FrameRecordingTests 15/15
- [X] REC-003-T06 Rule tests (Linux shape too): geometry (odd crop, 1179 × 2556 → 884 × 1920, small sizes unchanged, nil below 2 × 2); timeline (30 fps exact ticks 20k; 60 Hz keeps every other; 120 Hz every fourth; equal or earlier time dropped and counted; jitter within tolerance kept; 10-minute limit; `endTick`); gate (capacity 3, fourth refused, release reopens, `maxInFlight`); refusal order, in `Packages/Compositor/Tests/FrameRecordingTests/RecordingRulesTests.swift` — Verified 2026-11-13: RecordingRulesTests 15/15 on the host (0.002 s) and in the Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) FrameRecordingTests 15/15

## Phase 3: User Story 2 - The file plays back with correct, increasing timestamps (P1)

**Goal**: the row's acceptance: a 10-second fixture decodes with monotonic timestamps.
**Independent test**: fixture encode + decode on the Mac host.

- [X] REC-003-T07 [US2] `VideoFileWriter` (AVFoundation): codec fallback HEVC → H.264 (`canApply`, `add`, `startWriting`, delete and retry), output settings per research REC-003-D2 (bit rate, key frames, Rec. 709, scaling mode when output ≠ source), `mediaTimeScale` 600, `metadata` [], adaptor pool attributes (32BGRA, source size, Metal compatible, IOSurface), serial queue, `append(_:tick:)` (real time: drop when not ready; offline: wait on the writer queue), `finish(endTick:)`, `cancel()`, in `Packages/Compositor/Sources/FrameRecording/VideoFileWriter.swift` — Verified 2026-11-13: MetalFrameRecorderTests `testRealWriterScalesToTheCap` (H.264, 320 × 240 → 160 × 120) and CompositorRecordingTests fixture (HEVC on the Mac host) pass
- [X] REC-003-T08 [US2] `RecordedVideoInspector.inspect(_:)` → `RecordedVideoInfo` (codec, size, frame count and presentation ticks by `AVAssetReader` with sample buffers only, duration, video/audio track counts, metadata count, `summary`); in `Packages/Compositor/Sources/FrameRecording/RecordedVideoInspector.swift` — Verified 2026-11-13: CompositorRecordingTests fixture and MetalFrameRecorderTests read the files back (ticks, size, codec, tracks, metadata)
- [X] REC-003-T09 [US2] `MetalFrameRecorder` per the contract: geometry check, timeline, gate, pixel buffer from the adaptor's pool, `CVMetalTextureCache` texture (`bgra8Unorm_srgb`), `encode` closure, completed handler → writer queue append → release; `finish()` idempotent (stop accepting, wait for in-flight, end session at `endTick`, < 2 frames → `tooFewFrames` and delete; writer failure → `writerFailed`, file deleted, resources released, REC-003-R17), `cancel()`, `statistics`, `recordedSeconds`, test hook `waitForPendingFrames()`; an internal writer protocol for the stalled-writer test, in `Packages/Compositor/Sources/FrameRecording/MetalFrameRecorder.swift` — Verified 2026-11-13: MetalFrameRecorderTests 6/6 on the Mac host GPU (0.66 s)
- [X] REC-003-T10 [US2] `Compositor.encodeOutput(into:commandBuffer:)` per the contract (only after a composite into the same command buffer, target ≤ composite, supported format), in `Packages/Compositor/Sources/Compositor/Compositor.swift` — Verified 2026-11-13: CompositorRecordingTests `testEncodeOutputCopiesTheShownFrame` on the Mac host GPU
- [X] REC-003-T11 [US2] Acceptance fixture: a compositor with a test layer drawing frame k's index as a 9-bit bar pattern at 160 × 120 (each bar half white: left for 1, right for 0, so every frame has the same brightness and the composite flash guard never dims it), a simulated 30 fps clock (k × 10⁹ / 30 ns), offline writer; decode: 300 ± 1 frames, ticks strictly increasing and equal to 20 × k, duration 10 s ± 1/30, decoded indices 0...299 in order, one video track, no audio track, no metadata items; codec recorded in the test log (REC-003-S1), in `Packages/Compositor/Tests/CompositorTests/CompositorRecordingTests.swift` — Verified 2026-11-13: CompositorRecordingTests `testTenSecondFixtureDecodesWithMonotonicTimestamps` on the Mac host (2.3 s): HEVC, 300 frames, ticks = 20 × k, 10.0 s, indices 0...299, 1 video track, 0 audio tracks, 0 metadata items
- [X] REC-003-T12 [US2] Compositor tests: `encodeOutput` without a composite returns false; with one, the target equals the drawable's pixels (cropped); the shown output is unchanged, in `Packages/Compositor/Tests/CompositorTests/CompositorRecordingTests.swift` — Verified 2026-11-13: CompositorRecordingTests `testEncodeOutputCopiesTheShownFrame` (0.07 s)

## Phase 4: User Story 3 - Recording never stalls the show (P1)

**Goal**: bounded queue with drops counted; the frame loop never waits.
**Independent test**: stalled writer.

- [X] REC-003-T13 [US3] Stalled-writer test: a writer whose append blocks until released; 12 frames submitted: in flight never above 3, 9 counted `droppedBusy`, every `recordFrame` returned (no wait); after release the frames are appended and new ones are written; non-increasing times never written (REC-003-S2, S3), in `Packages/Compositor/Tests/FrameRecordingTests/MetalFrameRecorderTests.swift` — Verified 2026-11-13: MetalFrameRecorderTests `testStalledWriterBoundsFramesInFlightAndDropsTheRest` (12 frames: 3 submitted, 9 droppedBusy, max in flight 3; equal time dropped)
- [X] REC-003-T14 [US3] Recorder tests: scaling (320 × 240 source with a 160 cap → a 160 × 120 file); odd drawable cropped to even; size change → `sizeChanged`; finish with 1 frame → `tooFewFrames`, file deleted; finish twice returns the same result; an injected writer failure stops the recorder, deletes the file and reports `writerFailed` (REC-003-R17); frames after finish → `finished`, in `Packages/Compositor/Tests/FrameRecordingTests/MetalFrameRecorderTests.swift` — Verified 2026-11-13: MetalFrameRecorderTests 6/6 on the Mac host GPU

## Phase 5: User Story 1 - Record the visual to a video file (P1)

**Goal**: Record / Stop recording on recordable visuals, indicator, file mover.
**Independent test**: app UI test with the DEBUG folder.

- [ ] REC-003-T15 [US1] `VideoRecordingSource` protocol and `VideoRecordingTap` (wraps the recorder, forwards stop-worthy outcomes once); conformances: Camera, Photo, Video, Text hosts (`compositor.encodeOutput` after `composite`), native spectrum host (blit, `framebufferOnly` off while recording, kept off for a pending REC-001 capture), in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`, `Apps/projectM-iOS/Visuals/*Host.swift`
- [ ] REC-003-T16 [US1] `VideoRecordingCoordinator`: gate, start (temporary folder `<tmp>/Recordings`, name "Visualizer Recording <local date and time>.mp4"), state, elapsed text, stop and finish on a task, notices, `fileMover` file and its completion (delete on cancel or failure), launch cleanup of the folder, DEBUG `-uitestRecordingDirectory` move and probe; `AppCoordinator` owns it and names the shown visual's source and whether it is recordable, in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] REC-003-T17 [US1] UI: `record` control ("Record" / "Stop recording"; for projectM its value reads "Unavailable for projectM" and a tap refuses with the notice, REC-003-R12), indicator `recordingIndicator` ("Recording, 0:05", red dot, not part of the frame), `fileMover`, notice `videoRecordingNotice`, DEBUG probe `videoRecordingProbe`; accessibility labels (REC-003-R16; the indicator is SwiftUI app UI above the visual, never in the GPU copy), in `Apps/projectM-iOS/Views/ControlsOverlay.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] REC-003-T18 [US1] UI test on the Photo visual (seeded fixture): Record → indicator appears → ~2 s → Stop recording → probe `video <codec> <w>x<h> frames=<n> duration=<s> audio=0` with n ≥ 2; projectM shows Record unavailable with its notice; under 30 s (REC-003-S5), in `Apps/projectM-iOS/UITests/VideoRecordingUITests.swift`

## Phase 6: User Story 4 - Interruptions end the recording safely (P2)

**Goal**: every stop event finishes a readable file with its notice.
**Independent test**: coordinator tests with a fake source and lifecycle.

- [ ] REC-003-T19 [US4] Lifecycle: the coordinator's context check (pause, blackout, visual change, presentation loss), `didEnterBackground` with a background-task grant, tap outcomes (size changed, duration reached, failure), in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`
- [ ] REC-003-T20 [US4] App tests: refusals (blackout, paused, projectM, busy); each stop reason ends the recording with its notice; a Photo host records offscreen frames and the file decodes after a simulated background stop; launch cleanup empties the folder (REC-003-S4), in `Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift`

## Phase 7: Polish & cross-cutting

- [ ] REC-003-T21 [P] Privacy: `docs/privacy-policy.md` (recorded videos: only on the user's action, temporary file, Files only, no audio, Camera content) and `docs/release/app-privacy.md` (Data Not Collected unchanged; owner confirms)
- [ ] REC-003-T22 Gates: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/check_privacy_manifest.py` on the Debug simulator app; package tests on the host, the Linux shape and once `xcodebuild test -scheme Compositor` on the iOS 27.2 simulator; app tests; PosterBoard reports counted before and after
- [ ] REC-003-T23 {device} D1 and D3 (iPadOS 26.5): 60 s recordings of the Camera and the Circular Spectrum at the device's drawable size: frame rate, dropped frames, thermal state before and after; files play in Files (quickstart D1)
- [ ] REC-003-T24 {device} D3 with a 4K external display: 60 s recording of the Photo visual on the display: size, frame rate, drops, thermal state (quickstart D2)
- [ ] REC-003-T25 {device} Save to On My iPhone/iPad and iCloud Drive; HEVC on iPadOS 26.5 plays (quickstart D3)

## Dependencies

T01 → T02-T05 → T06 → US2 (T07-T12) → US3 (T13-T14) → US1 (T15-T18) → US4 (T19-T20) → T21-T22.
T23-T25 last, owner. US2 comes first because the recorder it builds is what US1 and US3 use.

## Parallel examples

- T02, T03, T04, T05 (separate files).
- T21 with anything after T16.

## Implementation strategy

MVP = Phases 1-4 (the row's acceptance in the package), then the app (US1, US4). Success criteria:
S1 → T11; S2, S3 → T06, T13; S4 → T20; S5 → T18; S6 → T23-T25 (`{device}`).
