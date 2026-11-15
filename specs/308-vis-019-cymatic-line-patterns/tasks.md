# Tasks: VIS-019 Cymatic Line Patterns

**Input**: `specs/308-vis-019-cymatic-line-patterns/` (spec, plan, research, data-model, contracts/cymatic.md)

## Phase 1: Foundational - model (VIS-019-R2 to R5, R7, R9)

- [X] VIS-019-T01 `CymaticBandRange`, `CymaticSettings`, `CymaticMode`, `CymaticField` (mode table, field, blend, line intensity, nodal mask, shade: CPU mirror of one pixel) and `CymaticShader` (MSL text, same operations) in `Packages/VisualGenerators/Sources/VisualGenerators/CymaticPattern.swift`. — Verified 2026-11-15: swift test --filter CymaticPatternTests 10 passed (0.30 s host; 0.57 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape): smallest pairwise mask difference 64% of the combined line pixels; 100 Hz → mode 2, 1 kHz → mode 5 through ANL-002, masks differ 100%; exact rest after 1 s (2 s Reduce Motion), not at 40%
- [X] VIS-019-T02 `CymaticDrive` (selected range, loudest band, part, hysteresis, silence floor, weight and amplitude slews on the injected clock, Reduce Motion, reset, `isAtRest`) in `CymaticDrive.swift`. — Verified 2026-11-15: swift test --filter CymaticPatternTests 10 passed (0.30 s host; 0.57 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape): smallest pairwise mask difference 64% of the combined line pixels; 100 Hz → mode 2, 1 kHz → mode 5 through ANL-002, masks differ 100%; exact rest after 1 s (2 s Reduce Motion), not at 40%
- [X] VIS-019-T03 `NoiseFieldConfiguration.cymatic` (+ factory; `clamped()` turns the other modes off) in `NoiseFieldConfiguration.swift`. — Verified 2026-11-15: swift test --filter CymaticPatternTests 10 passed (0.30 s host; 0.57 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape): smallest pairwise mask difference 64% of the combined line pixels; 100 Hz → mode 2, 1 kHz → mode 5 through ANL-002, masks differ 100%; exact rest after 1 s (2 s Reduce Motion), not at 40%

## Phase 2: User Stories 1-3 on the CPU (R2 to R7, R9; S1, S2, S4)

- [X] VIS-019-T04 [US1] [US2] [US3] `CymaticPatternTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/CymaticPatternTests.swift`): the 9 modes' nodal masks pairwise differ in ≥ 50% of their combined line pixels on a 96 × 72 grid; synthetic band frames with a single lit band in each part settle to that part's mode; pure tones (AUD-016 sines at 100 Hz and 1 kHz through `SpectrumBandFeed`, the real ANL-002 reducer) settle to different modes with masks differing ≥ 50% of their combined line pixels; ties pick the lowest band; hysteresis holds below 1.25×; a range excludes out-of-range tones (rest); silence after any state reaches the exact rest state within 1 s (2 s with Reduce Motion) and not before the slews allow; Reduce Motion halves blend speed and width depth; time backwards and long gaps bounded; NaN/±inf/huge bands, empty bands and every band count give finite state and colours in 0…1 (≤ 0.8 luminance). Runs in the Linux shape. — Verified 2026-11-15: swift test --filter CymaticPatternTests 10 passed (0.30 s host; 0.57 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape): smallest pairwise mask difference 64% of the combined line pixels; 100 Hz → mode 2, 1 kHz → mode 5 through ANL-002, masks differ 100%; exact rest after 1 s (2 s Reduce Motion), not at 40%

## Phase 3: User Stories 1, 2, 4 on Metal (R1, R6 to R8, R11, R14; S1 to S5)

- [ ] VIS-019-T05 [US1] Mode `.cymatic` in `NoiseFieldGenerator` (pipeline, drive, flash sampling, 40-float block at buffer 1, entry points `vis_cym_fragment` and test-only `vis_cym_mask_fragment`, restart, re-entry) and `NoiseFieldFlashAreas.sampleCymatic`.
- [ ] VIS-019-T06 [US1] [US2] [US4] `CymaticRenderTests` (GPU): two tone frames' GPU nodal masks differ ≥ 50% of their combined line pixels and agree with the CPU mirror's mask away from the threshold; tone then 1 s silence gives a frame bit-identical to a fresh generator's silent frame (gain 1); two renders identical; extreme bands and times render finite in 0…1; a size-0 target draws nothing and a landscape target centres the plate on the shorter side; a range change applies in place; entering the mode and a loop restart reset to rest.
- [ ] VIS-019-T07 [US4] `CymaticFlashTests`: bursts alternating with silence stay within the transition budget in all 17 areas, Reduce flashing on and off, portrait and landscape with the strongest glow; sample colours ≤ 0.8.
- [ ] VIS-019-T08 [US1] `CymaticGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 4: User Story 3 - the app (R10, R12, R13; S6)

- [ ] VIS-019-T09 [US3] Visual choice `cymatic` ("Cymatic Lines"), key `settings.cymatic.bands` (in `allKeys`, `ALLOWED_KEYS`, FILE-005 policy), `CymaticOptions` (segmented picker), host style `.cymatic(bands:)` built and updated in place (`CymaticHostSupport.swift`), accessibility value, scene capture as no layer (separate `case` lines), onChange in a one-modifier chain.
- [ ] VIS-019-T10 [P] [US3] `CymaticAppTests` (setting persists and falls back; key in every list; host names itself, applies the range in place, keeps Reduce Motion and palette, switches with other noise-field modes; scene capture no layer); `SettingsTests.testOnlyTheSettingsKeysAreWritten`, `CameraVisualTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` updated and passing.
- [ ] VIS-019-T11 [P] [US3] `CymaticUITests`: choose Cymatic Lines, Bands offered at All, Bars not, choose Low, value updates, source started once (< 30 s).

## Phase 5: Polish

- [ ] VIS-019-T12 Touched package suites, Linux shape, RenderGoldens, LibraryBackup, repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-019-T13 {device} On D1: a test-tone sweep and music for 30 s each; frame rate on the overlay; tones change the figure, silence returns it to the cross within about 1 s; Reduce Motion calmer; device GPU golden look.

## Dependencies

T01, T02 → T03 → T04; T03 → T05 → T06, T07, T08, T09 → T10, T11; all → T12. T13 needs a device.

## Implementation strategy

MVP = T01-T04 (the acceptance proven on the CPU mirror with real ANL-002 tones), then the GPU proof (T05-T08), then
the app (T09-T11).

## Analyze notes (speckit-analyze, 2026-11-15)

- Coverage: R1 T05; R2 T01, T04; R3 T02, T04; R4 T02, T04, T06; R5 T02, T04; R6 T04, T06, T08; R7 T04, T06; R8 T07;
  R9 T04; R10 T09-T11; R11 T08; R12 T09, T10; R13 T09-T11; R14 T12. S1 T04, T06; S2 T04, T06; S3 T06, T08; S4 T04,
  T06; S5 T07; S6 T10, T11; S7 T12. No constitution conflict (no new compile site, no dependency, no networking,
  nothing reaches projectM; bands come from ANL-002, no analysis duplicated).
- Fix applied (coverage): the edge cases "output size 0" and "non-square outputs" had no task; T06 now asserts both.
- Fix applied (consistency): `LibraryEraseAppTests` (FILE-011 erase derives from the FILE-005 lists) added to T10, as
  the agent rules require for a new key.
- No ambiguity left: the nodal mask, the 50% difference threshold, the settle time and the floor are numbers in Clarifications.
