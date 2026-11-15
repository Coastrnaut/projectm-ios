# Tasks: VIS-020 Spectrum Waterfall

**Input**: `specs/267-vis-020-spectrum-waterfall/` (spec, plan, research, data-model, contracts/waterfall.md)

## Phase 1: Foundational - the history ring (VIS-020-R3, R4, R5, R8)

- [ ] VIS-020-T01 `SpectrumWaterfallHistory` (fixed 512 × 256 `UInt8` ring, sequences, integer-nanosecond row clock, running mean, hold on skipped rows, ≤ 512 rows per frame, re-anchor on time backwards, Reduce Motion doubles the step from the next row, log-band → column interpolation, pending rows, `clear()`) and `WaterfallShader.function` in `Packages/VisualGenerators/Sources/VisualGenerators/SpectrumWaterfall.swift`.
- [ ] VIS-020-T02 `NoiseFieldConfiguration.waterfall` (on forces wedges 0 and tunnel pace 0) and `waterfall(reduceMotion:palette:)` in `NoiseFieldConfiguration.swift`.

## Phase 2: User Stories 1 + 2 - time order and fixed storage (VIS-020-R3, R4; S1, S2)

- [ ] VIS-020-T03 [US1] [US2] `WaterfallHistoryTests` (`WaterfallHistoryTests.swift`) with an injected clock and a band that steps once per second: after 60 s at 60 and 24 fps the 512 rows read oldest → newest have sequences 0…511 and each row inside one second shows that second's band; after 75 s the oldest is 128 and order holds; storage address and byte count constant; stall, time backwards, Reduce Motion, empty and non-finite input; Linux shape.

## Phase 3: User Story 3 - safety (VIS-020-R6 to R8; S4)

- [ ] VIS-020-T04 [US3] `WaterfallFlashCells` and `NoiseFieldFlashAreas.loadWaterfall`; `WaterfallFlashTests`: cell means equal a brute-force mean of the texels; brightness ≤ 0.8; bursts alternating with silence within the envelope in all 17 areas with Reduce flashing on and off.

## Phase 4: User Story 1 - the picture on Metal (VIS-020-R1 to R3, R5, R10, R13; S3, S5)

- [ ] VIS-020-T05 [US1] `NoiseFieldGenerator`: history, `historyTexture` (private `r8Unorm` 256 × 512) and staging buffer made in `init`; blit of pending rows; fourth entry point `vis_waterfall_fragment` with its own lazily built pipeline; entering the mode clears the history.
- [ ] VIS-020-T06 [US1] [US2] `WaterfallRenderTests` (GPU): a known history renders newest at the top in order (sampled pixels within 0.02 of the CPU mirror); 60 s of frames across three output sizes keep the texture identity and size; other modes' render tests unchanged.
- [ ] VIS-020-T07 [US1] `WaterfallGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 5: User Story 4 - the app (VIS-020-R9, R11, R12; S6)

- [ ] VIS-020-T08 [US4] Visual choice `spectrumWaterfall` (Bars applies), host style `.waterfall` with in-place mode switches, accessibility value, scene capture as no layer, snapshot and batch-job arms, Settings description text.
- [ ] VIS-020-T09 [P] [US4] `WaterfallAppTests` (choice stored and restored; host names itself; switches with the other noise-field modes in place; palette and Reduce Motion; no new key written; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` passing.
- [ ] VIS-020-T10 [P] [US4] `WaterfallUITests`: choose Spectrum Waterfall, Bars offered, the visual shown with its value, source started once (< 30 s).

## Phase 6: Polish

- [ ] VIS-020-T11 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-020-T12 {device} On D1 with music, Spectrum Waterfall holds the display's frame rate on the PERF-001/007 overlay and falls steadily, newest at the top.

## Dependencies

T01 → T02 → T03, T04, T05; T05 → T06, T07, T08 → T09, T10; all → T11. T12 needs a device.

## Parallel examples

T03 and T04 (different test files) after T02; T09 and T10 after T08.

## Implementation strategy

MVP = T01-T03 (the acceptance: time order and fixed storage, proven by the pure ring); then the picture (T05-T07),
then the app (T08-T10).
