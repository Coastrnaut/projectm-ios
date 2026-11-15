# Tasks: VIS-020 Spectrum Waterfall

**Input**: `specs/267-vis-020-spectrum-waterfall/` (spec, plan, research, data-model, contracts/waterfall.md)

## Phase 1: Foundational - the history ring (VIS-020-R3, R4, R5, R8)

- [X] VIS-020-T01 `SpectrumWaterfallHistory` (fixed 512 × 256 `UInt8` ring, sequences, integer-nanosecond row clock, running mean, hold on skipped rows, ≤ 512 rows per frame, re-anchor on time backwards, Reduce Motion doubles the step from the next row, log-band → column interpolation, pending rows, `clear()`, and the CPU pixel mirror `level(atX:y:width:height:)` the shader matches) and `WaterfallShader.function` in `Packages/VisualGenerators/Sources/VisualGenerators/SpectrumWaterfall.swift`. — Verified 2026-11-14: swift test --filter Waterfall (WaterfallHistoryTests 7, WaterfallFlashTests 3, WaterfallRenderTests 3 passed) on the host and in the Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE)
- [X] VIS-020-T02 `NoiseFieldConfiguration.waterfall` (on forces wedges 0 and tunnel pace 0) and `waterfall(reduceMotion:palette:)` in `NoiseFieldConfiguration.swift`. — Verified 2026-11-14: WaterfallRenderTests.testSwitchingModesInPlaceGivesFreshFrames and WaterfallAppTests (waterfall forces the other modes off; plain, kaleidoscope and tunnel suites unchanged and passing)

## Phase 2: User Stories 1 + 2 - time order and fixed storage (VIS-020-R3, R4; S1, S2)

- [X] VIS-020-T03 [US1] [US2] `WaterfallHistoryTests` (`WaterfallHistoryTests.swift`) with an injected clock and a band that steps once per second: after 60 s at 60 and 24 fps the 512 rows read oldest → newest have sequences 0…511 and each row inside one second shows that second's band; after 75 s the oldest is 128 and order holds; storage address and byte count constant; stall, time backwards, Reduce Motion, empty and non-finite input; Linux shape. — Verified 2026-11-14: WaterfallHistoryTests 7 passed in 0.74 s: 60 s at 60 and 24 fps write exactly 512 rows, sequences 0…511 oldest → newest, every row inside one second shows that second's band, bands never go backwards (oldest second 0, newest 59); 75 s wraps to sequences 128…639 (oldest second 15); levels address constant across 75 s and a clear, byte count 131,072; row mean, stall hold (≤ 512 rows), time backwards writes nothing, Reduce Motion 256 rows in 60 s and 256 + 128 after a mid-run switch, NaN/empty/out-of-range input; Linux shape 264 tests passed

## Phase 3: User Story 3 - safety (VIS-020-R6 to R8; S4)

- [X] VIS-020-T04 [US3] `WaterfallFlashCells` and `NoiseFieldFlashAreas.loadWaterfall`; `WaterfallFlashTests`: cell means equal a brute-force mean of the texels; brightness ≤ 0.8; bursts alternating with silence within the envelope in all 17 areas with Reduce flashing on and off. — Verified 2026-11-14: WaterfallFlashTests 3 passed: cells equal a brute-force texel mean (1e-5), × 0.8; full level ≤ 0.8 of white; bursts every 0.1 s worst 1 transition per window with Reduce flashing on (limit 4) and off (limit 6), with and without glow

## Phase 4: User Story 1 - the picture on Metal (VIS-020-R1 to R3, R5, R10, R13; S3, S5)

- [X] VIS-020-T05 [US1] `NoiseFieldGenerator`: history, `historyTexture` (private `r8Unorm` 256 × 512) and staging buffer made in `init`; blit of pending rows; fourth entry point `vis_waterfall_fragment` with its own lazily built pipeline; entering the mode clears the history. — Verified 2026-11-14: swift build plus WaterfallRenderTests on the host GPU and on VIS20 iPhone 17 (iOS 27.2); NoiseFieldRenderTests (recorded digests), KaleidoscopeRenderTests, TunnelRenderTests, NativePipelineArchiveTests unchanged and passing (22 tests on the simulator)
- [X] VIS-020-T06 [US1] [US2] `WaterfallRenderTests` (GPU): a known history renders newest at the top in order (sampled pixels within 0.02 of the CPU mirror); 60 s of frames across three output sizes keep the texture identity and size; other modes' render tests unchanged. — Verified 2026-11-14: WaterfallRenderTests 3 passed on the host and the iOS 27.2 simulator: after 60 s at 20 fps the read-back history texture equals the CPU ring byte for byte, the picture's lit band moves left going down (newest second 59 at the top, second 0 at the bottom), sampled pixels within 0.02 of the CPU mirror; 60 s into 32×32, 64×128 and 200×100 targets keep the texture identity, allocatedSize and ring address (13 checks); mode switches in place equal fresh frames; restart clears the history and keeps the texture
- [X] VIS-020-T07 [US1] `WaterfallGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry. — Verified 2026-11-14: swift test --filter Golden (RenderGoldens 96, 1 on-demand skip; waterfall golden recorded then identical) and xcodebuild test on VIS20 iPhone 17: waterfall goldens identical (SSIM 1.0), integrity passed, noise field, kaleidoscope and tunnel goldens identical

## Phase 5: User Story 4 - the app (VIS-020-R9, R11, R12; S6)

- [X] VIS-020-T08 [US4] Visual choice `spectrumWaterfall` (`usesBars` true: Bars applies), host style `.waterfall` with in-place mode switches, accessibility value, scene capture as no layer, snapshot and batch-job arms, Settings description text. — Verified 2026-11-14: xcodebuild build-for-testing on VIS20 iPhone 17 with the type-check flags: no warning in a touched file; WaterfallAppTests 3 passed
- [X] VIS-020-T09 [P] [US4] `WaterfallAppTests` (choice stored and restored; host names itself; switches with the other noise-field modes in place; palette and Reduce Motion; no new key written; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` passing. — Verified 2026-11-14: xcodebuild test-without-building: WaterfallAppTests, SettingsTests, CameraVisualTests, LibraryBackupAppTests, TunnelAppTests, NoiseFieldAppTests, KaleidoscopeAppTests (37 passed, 2.0 s)
- [X] VIS-020-T10 [P] [US4] `WaterfallUITests`: choose Spectrum Waterfall, Bars offered, the visual shown with its value, source started once (< 30 s). — Verified 2026-11-14: WaterfallUITests passed in 20.5 s on VIS20 iPhone 17

## Phase 6: Polish

- [X] VIS-020-T11 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts. — Verified 2026-11-14: VisualGenerators swift test 317 passed (45 s); Linux shape 264 passed (32 s); RenderGoldens Golden 96 passed; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 179 OK; check_privacy_manifest OK; check_network_symbols OK (19 images); type-check warnings only in untouched files (none in VIS-020's); PosterBoard reports 30 before and 30 after
- [ ] VIS-020-T12 {device} On D1 with music, Spectrum Waterfall holds the display's frame rate on the PERF-001/007 overlay and falls steadily, newest at the top.

## Dependencies

T01 → T02 → T03, T04, T05; T05 → T06, T07, T08 → T09, T10; all → T11. T12 needs a device.

## Parallel examples

T03 and T04 (different test files) after T02; T09 and T10 after T08.

## Implementation strategy

MVP = T01-T03 (the acceptance: time order and fixed storage, proven by the pure ring); then the picture (T05-T07),
then the app (T08-T10).

## Analyze notes (speckit-analyze, 2026-11-14)

- Coverage: every R1-R13 maps to a task (R3-R5, R8 T01-T03; R6, R7 T04; R1, R2, R10, R13 T05-T07, T11; R9, R11,
  R12 T08-T10). S1-S6 each have a test task. No constitution conflict (no new compile site, no new dependency, no
  networking, nothing reaches projectM, no new key).
- Fix applied (underspecification): S3 compares the GPU with "the CPU mirror", which no task defined; T01 now
  includes the per-pixel CPU mirror of the shader's sampling.
- Fix applied (inconsistency): spec R9 says Bars applies, but VIS-013 to VIS-015 hide Bars; T08 sets `usesBars` for
  the waterfall and T10 asserts Bars is offered.
