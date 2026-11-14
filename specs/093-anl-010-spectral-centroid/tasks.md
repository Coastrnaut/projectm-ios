# Tasks: ANL-010 Spectral Centroid

**Input**: Design documents in `specs/093-anl-010-spectral-centroid/` (spec.md, plan.md,
research.md, data-model.md, contracts/spectral-centroid.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure)
is recorded before the production change. Budgets (owner rule 7): a unit test about 1-2 s (≤ 10 s),
each package suite under 1 minute; the AnalysisFeatures Linux-shape suite already takes ≈ 67 s, so
this row adds at most a few hundred milliseconds there. Representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel.
`{sim}` = needs the row's own iOS 27.2 simulator "ANL10 iPhone 17" (created for this row, deleted
afterwards). Inside descriptions "T03" is short for `ANL-010-T03`. A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] ANL-010-T01 Record the baseline: `swift test --package-path Packages/AnalysisFeatures` in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/AnalysisFeatures/.build/linux`); `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`. Evidence: counts and durations recorded here. — Verified 2026-11-13: at 02dec1a, AnalysisFeatures 124 tests in the Linux shape (62.3 s, 1 skipped), 0 failures; check_compliance, validate_docs (821 files), check_motion_policy, check_permission_catalog OK; test_scripts.py 147 OK (1 skipped) (.build/scratch/anl010-T01-*.log).

## Phase 2: Foundational (blocks every story)

- [X] ANL-010-T02 Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralCentroidTests.swift` with a helper that analyses one window of synthetic PCM through `SpectrumAnalyzer` (both backends where compiled) and the estimator, plus tests for `SpectralBinRange` ("first = max(1, ⌈lower·N/R⌉)", "last = min(N/2, ⌊upper·N/R⌋)", nil when empty) and the configuration (`.standard` = 44,100 Hz, 20 Hz, Nyquist, −70 dB, 50 Hz, 10 kHz; each invalid field throws: rate "finite, > 0", lower "finite, > 0, < Nyquist", upper "nil or finite and > lowerFrequency", floor "finite, < 0", normalization "finite, > 0" and upper > lower; `normalized(hz:)` at 50 Hz → 0, 10 kHz → 1, 1 kHz ≈ 0.565, non-finite → 0). Record the red run. — Verified 2026-11-13: red run = compile failure "cannot find type 'SpectralCentroidReading' in scope" (.build/scratch/anl010-T02-red.log). The whole test file (T02 and the T04-T07 cases) was written before the production code, so this one red run covers them all.
- [X] ANL-010-T03 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectralBinRange.swift` and `SpectralCentroid.swift` (contract C1, C2; power-weighted sum accumulated in Double; non-finite magnitudes count 0; typed arithmetic steps; `process` allocates, locks, logs and reads no clock, ANL-010-R10, R11, checked by reading the diff). Evidence: T02 passes on the host and in the Linux shape. — Verified 2026-11-13: SpectralCentroidTests pass on the host and in the Linux shape; diff read: `SpectralCentroidEstimator` is a struct holding only its configuration and last reading, `process` uses a stack loop over the bins (Double accumulation), one `log2` pair, no allocation, lock, print or clock (.build/scratch/anl010-T03-host.log).

## Phase 3: User Story 1 - brighter sound reads higher (P1) 🎯 MVP

**Independent test**: `SpectralCentroidTests` acceptance cases.

- [X] ANL-010-T04 [US1] Add to `SpectralCentroidTests.swift`: tones 100, 200, 400, 800, 1,600, 3,200, 6,400 Hz (−6 dBFS, 2,048 points, 44.1 kHz, not bin-centred) give strictly increasing centroids, each within 1 % of the tone, normalized strictly increasing in 0…1 (print the table); seeded white noise reads within 5 % of the expected mean (k₀ + N/2)/2·R/N; two tones 500 Hz + 2 kHz at amplitudes 1 and 0.25 read (500 + 0.0625·2,000)/1.0625 ≈ 588 Hz within 1 %, equal amplitudes 1,250 Hz. Evidence: passes on both shapes; tone table recorded in spec.md. — Verified 2026-11-13: `testRisingToneFrequencyRaisesTheCentroidMonotonically` (both backends), `testWhiteNoiseReadsTheMeanOfTheAnalysedRange` (10,955.6 Hz vs 11,035.8 expected, −0.7 %) and `testTwoTonesReadTheirPowerWeightedMean` (amplitudes 0.4 and 0.1, ratio 1 : 0.25 → 588.2 Hz; equal 1,250 Hz) pass on the host and in the Linux shape; tone table in spec.md Implementation results.

## Phase 4: User Story 2 - same reading everywhere (P1)

- [X] ANL-010-T05 [US2] Add to `SpectralCentroidTests.swift`: a 1 kHz tone at all five FFT sizes and at 44.1 and 48 kHz reads within 1 %; 200 Hz at 512 points and 100 Hz at 1,024 points within 1 % (R3's per-size floor); a tone at −6 and −40 dBFS reads the same within 0.1 %. Evidence: passes on both shapes. — Verified 2026-11-13: `testSizesRatesAndLevelsAgree` passes on the host and in the Linux shape.

## Phase 5: User Story 3 - silence is calm (P1)

- [X] ANL-010-T06 [US3] Add to `SpectralCentroidTests.swift`: digital silence and ±1 LSB 16-bit dither from the start read (0, 0, no signal); a tone then silence holds the tone's `hz` and `normalized` exactly with `hasSignal` false; `reset()` returns `.none`; a frame at another sample rate or with a wrong magnitude count leaves the reading unchanged; non-finite magnitudes give finite output. Evidence: passes on both shapes. — Verified 2026-11-13: `testSilenceDitherAndHold` passes on the host and in the Linux shape.

## Phase 6: Bus integration (serves US1, US4)

- [X] ANL-010-T07 [US4] Write a pipeline test in `SpectralCentroidTests.swift` (stereo: 0.05 s of digital silence, then a 300 Hz then a 3 kHz tone, about 0.2 s each, through a `NormalizedPCMRing` tap and `AnalysisPipeline.step()`): frames well inside each tone read `centroidHz` within 1 % of it and the 3 kHz frames' `centroid` is higher; the silent lead frames after the session start read 0 in both values; a configuration with a different centroid sample rate throws `.sampleRateMismatch`. Record the red run. — Verified 2026-11-13: red run shared with T02 (no `centroidHz` member); `testThePipelineCarriesBothValuesInEveryFrame` passes: 38 frames, 4 silent lead frames read 0/0, 13 frames inside each tone within 1 %, 3 kHz normalized above 300 Hz; mismatched rate throws.
- [X] ANL-010-T08 [US4] Implement `AnalysisFrame.centroidHz`/`centroid` (defaulted to 0) in `AnalysisBusTypes.swift`, `centroid` with the rate check in `AnalysisPipelineConfiguration.swift`, and in `AnalysisPipeline.swift` own the estimator, reset it per session, run it per frame. Evidence: T07 passes; AnalysisFeatures whole suite on the host and in the Linux shape (delta recorded). — Verified 2026-11-13: AnalysisFeatures whole suite 133 tests (124 + 9), 0 failures on the host (52.0 s) and in the Linux shape (70.7 s, 1 skipped, while a ParameterGraph build ran alongside; the uncontended rerun is in T12). SpectralCentroidTests: 0.11 s on the host, 0.19 s in the Linux shape (.build/scratch/anl010-T08-*.log).

## Phase 7: User Story 4 - Centroid modulation source (P2)

- [X] ANL-010-T09 [P] [US4] Add tests in `Packages/ParameterGraph/Tests/`: `AudioFeatureSourceTests` (`audio.centroid` round-trips, reads `frame.centroid`, nil/non-finite → 0), `AudioFeatureModulatorTests` (a Centroid binding follows the value), `ExpressionEvaluationTests` (`audio.centroid` compiles to opcode 15 and reads the frame). Record the red run. — Verified 2026-11-13: red run = compile failure "type 'AudioFeatureSource' has no member 'centroid'" (.build/scratch/anl010-T09-red.log); `ExpressionPathologicalTests`' closed opcode list gains 15.
- [X] ANL-010-T10 [US4] Implement `AudioFeatureSource.centroid` and `AudioFeatureFrame.centroid` in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`, `ExpressionOpcode.centroid = 15` in `CompiledExpression.swift` and `ExpressionCompiler.swift`. Evidence: ParameterGraph and SceneFormat suites pass on the host. — Verified 2026-11-13: ParameterGraph 115 tests (75 + 40, 1 skipped; was 112), 0 failures on the host; SceneFormat 86 tests, 0 failures (no placeholder used `audio.centroid`, unlike ANL-007's `audio.kick`) (.build/scratch/anl010-T10-*.log).
- [X] ANL-010-T11 [US4] Add `centroid` to `LiveBandFrameInfo` in `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`; in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift` keep the last centroid read (0 after a pause restart) and pass it through `applyModulation(bands:kick:centroid:timeNanoseconds:)`; add "Centroid binds and drives the glow" to `Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift`. Evidence: VisualGenerators suite on the host; projectM-iOSTests pass `{sim}`. — Verified 2026-11-13: VisualGenerators 133 tests, 0 failures on the host (38.5 s); projectM-iOSTests 408 tests (was 407), 0 failures (12.6 s) on the row's iOS 27.2 simulator "ANL10 iPhone 17", including `testCentroidBindsAndDrivesTheGlow` (0.018 s); no compiler warnings in the touched files (.build/scratch/anl010-T11-*.log).

## Phase 8: Polish

- [ ] ANL-010-T12 Build and test the remaining dependants (PerformanceControl, Compositor, RenderGoldens, ShowControl); record the tone table and test cost in `spec.md`; run the five scripts (check_compliance covers ANL-010-R12); count PosterBoard reports; delete the row's simulator; mark the spec Implemented.

## Dependencies

T01 → T02 → T03 → (T04, T05, T06) → T07 → T08 → T09 → T10 → T11 → T12. T09 can be written in
parallel with T04-T08 (different package).

## Parallel example

After T03: T04-T06 (AnalysisFeatures tests) and T09 (ParameterGraph tests) touch different
packages and can be written together.

## Implementation strategy

MVP = T01-T04 (the roadmap acceptance in the package); then consistency and silence (T05, T06),
the bus (T07, T08), the modulation source (T09-T11); polish last.

## Analysis (speckit-analyze, 2026-11-13)

| ID | Category | Severity | Location | Summary | Fix applied |
|----|----------|----------|----------|---------|-------------|
| C1 | Coverage | MEDIUM | spec R3, tasks T05 | R3's "100 Hz within 1 % from 1,024 points" had no test (T05 tested 1 kHz at every size and 200 Hz at 512) | T05 adds 100 Hz at 1,024 points |
| F1 | Inconsistency | MEDIUM | tasks T07 | "Frames before any signal read 0" could not be observed: the fixture started with the tone | T07's fixture starts with 0.05 s of digital silence |
| C2 | Coverage | LOW | spec R10-R12 | Real-time, clock and boundary rules are not unit-testable | Already covered: T03 evidence reads the diff (R10, R11); T12's check_compliance cites R12 |

Coverage: R1-R12 and S1-S7 each map to at least one task (R1-R3 → T02-T04, R4 → T05, R5 → T06,
R6 → T02-T03, R7 → T07-T08, R8 → T09-T10, R9 → T11, R10-R12 → T03, T12; S1-S2 → T04, S3 → T05,
S4 → T06, S5 → T07, S6 → T09-T11, S7 → T08, T12). Constitution: no conflicts (I, VI, VII, VIII, X
pass in plan.md). No critical issues; 0 ambiguities or duplications left.
