# Tasks: ANL-014 Loudness Envelope

**Input**: Design documents in `specs/094-anl-014-loudness-envelope/` (spec.md, plan.md,
research.md, data-model.md, contracts/loudness-envelope.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure)
is recorded before the production change. Budgets (owner rule 7): a unit test about 1-2 s (≤ 10 s),
each package suite under 1 minute; the AnalysisFeatures Linux-shape suite already takes ≈ 62-67 s,
so this row adds at most a few hundred milliseconds there. Representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel.
`{sim}` = needs the row's own iOS 27.2 simulator "ANL14 iPhone 17" (created for this row, deleted
afterwards). Inside descriptions "T03" is short for `ANL-014-T03`. A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] ANL-014-T01 Record the baseline: `swift test --package-path Packages/AnalysisFeatures` in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/AnalysisFeatures/.build/linux`); `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`. Evidence: counts and durations recorded here. — Verified 2026-11-14: at ab68d80, AnalysisFeatures 133 tests in the Linux shape (51.9 s of tests, 1:01.6 wall with the build, 1 skipped), 0 failures; check_compliance, validate_docs (838 files), check_motion_policy, check_permission_catalog OK; test_scripts.py 147 OK (1 skipped) (.build/scratch/anl014-T01-*.log).

## Phase 2: Foundational (blocks every story)

- [X] ANL-014-T02 Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/LoudnessEnvelopeTests.swift` with helpers (one window of synthetic PCM through `SpectrumAnalyzer`; a stream of PCM through `SpectrumStream` frame by frame) and tests for `KWeighting` (contract C1: at 48 kHz the designed shelf and high-pass coefficients equal BS.1770's published values within 1e-6; 10·log10 `powerGain` at 997 Hz = 0.69 ± 0.02 dB at 44.1 and 48 kHz; `table` has `size.binCount` entries with entry 0 = 0) and `LoudnessConfiguration` (`.standard` = 44,100 Hz, −60, 0, attack 0.1 s, release 0.4 s; rate "finite, > 0" and above 3,364 Hz, floor "finite, < ceiling", ceiling "finite" each throw; `normalized(decibels:)` −60 → 0, −30 → 0.5, 0 → 1, +6 → 1, −90 → 0, NaN → 0). Record the red run. — Verified 2026-11-14: red run = compile failure "cannot find type 'LoudnessReading' in scope" (.build/scratch/anl014-T02-red.log). The whole test file (T02 and the T04-T06 cases) was written before the production code, so this one red run covers them all.
- [X] ANL-014-T03 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/KWeighting.swift` and `LoudnessEnvelope.swift` (contracts C1, C2; typed arithmetic steps for every biquad formula; sums in Double; non-finite magnitudes count 0; `process` allocates, locks, logs and reads no clock, ANL-014-R10, R11, checked by reading the diff). Evidence: T02 passes on the host and in the Linux shape. — Verified 2026-11-14: LoudnessEnvelopeTests pass on the host and in the Linux shape (K-weighting coefficients at 48 kHz within 1e-6 of BS.1770, 997 Hz weight 0.69 dB); diff read: `LoudnessEnvelope` is a struct whose only buffer, the weight table, is built in `init`; `process` is one Double loop over the bins, one log10, one exp (inside `SmoothingTimes.coefficient`), no allocation, lock, print or clock (.build/scratch/anl014-T03-host.log).

## Phase 3: User Story 1 - a parameter follows loudness (P1) 🎯 MVP

**Independent test**: `LoudnessEnvelopeTests` acceptance cases.

- [X] ANL-014-T04 [US1] Add to `LoudnessEnvelopeTests.swift`: (a) calibration: one window of a full-scale 997 Hz sine reads −3.01 ± 0.2 dB (`decibels`); (b) step: a 1 kHz tone at −40 dBFS for 0.5 s, −10 dBFS for 0.75 s, −40 dBFS for 0.75 s, streamed through `SpectrumStream` (2,048 points, hop 512) into one envelope; measure on the sample clock (frame end = index + size) the 90 % rise and fall times from each step to the first frame at or past 90 % of the settled change; first run it printing both times and record them in spec.md as the documented lag ("Documented lag" under Implementation results, with the smoother-only part τ and the window part), then assert each equals that recorded constant within one hop (512 samples) and also lies between the smoother's own 90 % time and that time plus one window (2,048 samples), so the constant is tied to the model, not only to the run; the envelope stays in 0…1; (c) weighting: equal-amplitude (−20 dBFS) 100 Hz and 2 kHz read 2 kHz higher, and 20 Hz lower than 1 kHz; (d) monotonic: a 1 kHz tone at −50, −40, −30, −20, −10 dBFS gives strictly increasing settled envelopes (print the table). Evidence: passes on both shapes; tables in spec.md. — Verified 2026-11-14: first run printed rise 5,086 samples and fall 19,115 samples, recorded in spec.md ("Documented lag") and as constants; then `testStepIsFollowedWithTheDocumentedLag`, `testFullScale997HzSineReadsTheReferenceLevel` (−3.007 dB), `testWeightingOrdersEqualAmplitudeTones` and `testLevelRaisesTheEnvelopeMonotonically` pass on the host and in the Linux shape (identical numbers) (.build/scratch/anl014-T04-*.log).

## Phase 4: User Story 2 - the value never breaks (P1)

- [X] ANL-014-T05 [US2] Add to `LoudnessEnvelopeTests.swift`: seeded full-scale white noise (±1), a ±1 square wave clipped at ±1 (1 kHz), magnitudes containing NaN and ±Inf, and digital silence from the start each keep `decibels` finite (≥ −120) and `envelope` in 0…1 over many frames; silence after the −10 dBFS tone decays to exactly 0 within 1.5 s (from ≈ 0.78 to below 0.001 is ≈ 2.9 decades of a 0.4 s-per-decade release, ≈ 1.16 s, plus the window) and stays 0; `reset()` returns `.silent` and the next frame snaps; a frame at another rate, another size, or with a wrong magnitude count leaves the reading unchanged. Evidence: passes on both shapes. — Verified 2026-11-14: `testExtremeAndNonFiniteInputStaysBounded` (noise −1.63 dB/0.973, square +0.83 dB clamped to 1, NaN/±Inf/3e38 magnitudes bounded) and `testSilenceDecaysToExactlyZeroAndResetSnaps` (exact 0 reached 1.19 s after the tone, stays 0; reset snaps; foreign frames ignored) pass on the host and in the Linux shape.

## Phase 5: User Story 3 - Loudness modulation source (P2)

- [X] ANL-014-T06 [US3] Write a pipeline test in `LoudnessEnvelopeTests.swift` (stereo: 0.05 s of digital silence, then a 1 kHz tone at −40 dBFS then at −10 dBFS, about 0.25 s each, through a `NormalizedPCMRing` tap and `AnalysisPipeline.step()`): the silent lead frames read `loudness` 0 and `loudnessDecibels` −120; the last frame of the loud part reads a higher `loudness` and `loudnessDecibels` than the last frame of the quiet part; every frame's `loudness` is in 0…1; a configuration whose loudness rate differs throws `.sampleRateMismatch`. Record the red run. — Verified 2026-11-14: red run shared with T02 (no `loudness` member); `testThePipelineCarriesTheEnvelopeInEveryFrame` passes: 47 frames, 4 silent lead frames read 0 and −120 dB, quiet 0.282 (−43.0 dB) < loud 0.781 (−13.0 dB), mismatched rate throws.
- [X] ANL-014-T07 [US3] Implement `AnalysisFrame.loudness` (default 0) and `loudnessDecibels` (default −120) in `AnalysisBusTypes.swift`, `loudness: LoudnessConfiguration = .standard` with the rate check in `AnalysisPipelineConfiguration.swift`, and in `AnalysisPipeline.swift` own the envelope (built for the spectrum's size), reset it per session, run it per frame. Evidence: T06 passes; AnalysisFeatures whole suite on the host and in the Linux shape (delta recorded). — Verified 2026-11-14: AnalysisFeatures whole suite 142 tests (133 + 9), 0 failures, 0 warnings on the host (46.5 s) and in the Linux shape (59.7 s, 1 skipped, while a ParameterGraph build ran alongside; the uncontended rerun is in T11). LoudnessEnvelopeTests: 0.23 s on the host, 0.38-0.49 s in the Linux shape (.build/scratch/anl014-T07-*.log).
- [X] ANL-014-T08 [P] [US3] Add tests in `Packages/ParameterGraph/Tests/`: `AudioFeatureSourceTests` (`audio.loudness` round-trips, reads `frame.loudness`, nil/non-finite → 0), `AudioFeatureModulatorTests` (a Loudness binding follows the value), `ExpressionEvaluationTests` (`audio.loudness` compiles to opcode 16 and reads the frame); `ExpressionPathologicalTests`' closed opcode list gains 16. Record the red run. — Verified 2026-11-14: red run = compile failure: `AudioFeatureSource` has no member `loudness` (.build/scratch/anl014-T08-red.log); the closed opcode list gains 16.
- [X] ANL-014-T09 [US3] Implement `AudioFeatureSource.loudness` and `AudioFeatureFrame.loudness` in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`, `ExpressionOpcode.loudness = 16` in `CompiledExpression.swift` and `ExpressionCompiler.swift`. Evidence: ParameterGraph and SceneFormat suites pass on the host. — Verified 2026-11-14: ParameterGraph 118 tests (77 + 41, 1 skipped; was 115), 0 failures, 0 warnings on the host; SceneFormat 86 tests, 0 failures (.build/scratch/anl014-T09-*.log).
- [X] ANL-014-T10 [US3] Add `loudness` to `LiveBandFrameInfo` in `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`; in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift` keep the last envelope read (0 after a pause restart) and pass it through `applyModulation(bands:kick:centroid:loudness:timeNanoseconds:)`; add `testLoudnessBindsAndDrivesTheGlow` to `Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift`. Evidence: VisualGenerators suite on the host; projectM-iOSTests pass `{sim}`. — Verified 2026-11-14: VisualGenerators 133 tests, 0 failures on the host (28.3 s); projectM-iOSTests 413 tests (was 412), 0 failures (46.1 s) on the row's iOS 27.2 simulator "ANL14 iPhone 17", including `testLoudnessBindsAndDrivesTheGlow` (0.019 s); no compiler warnings in the touched files (.build/scratch/anl014-T10-*.log).

## Phase 6: Polish

- [X] ANL-014-T11 Build and test the remaining dependants (PerformanceControl, Compositor, RenderGoldens, ShowControl); record the step, weighting and level tables and the test cost in `spec.md`; run the five scripts (check_compliance covers ANL-014-R12); confirm with `git diff --stat main -- Packages/AudioCore` that the level meter and classifier are untouched (R12); count PosterBoard reports; delete the row's simulator; mark the spec Implemented. — Verified 2026-11-14: PerformanceControl 110, Compositor 205, RenderGoldens 39, ShowControl 31 tests, 0 failures on the host (VisualGenerators and SceneFormat in T10/T09); Linux-shape rerun: AnalysisFeatures 142 tests, 61.0 s (baseline 133 tests, 51.9 s; LoudnessEnvelopeTests 0.35 s; the rest of the difference is in unrelated suites, AnalysisPipeline +2.6 s, BeatAcceptance +2.3 s, BandAcceptance +1.9 s, with the Mac at load average 111-153 from parallel lanes, so not an uncontended comparison); tables and test cost in spec.md; check_compliance, validate_docs, check_motion_policy, check_permission_catalog OK; test_scripts.py 147 OK (1 skipped); `git diff --stat ab68d80 -- Packages/AudioCore` empty (meter and classifier untouched, R12); PosterBoard reports 25 before and after the simulator run; simulator "ANL14 iPhone 17" deleted; spec marked Implemented (.build/scratch/anl014-T11-*.log).

## Dependencies

T01 → T02 → T03 → (T04, T05) → T06 → T07 → T08 → T09 → T10 → T11. T08 can be written in parallel
with T04-T07 (different package).

## Parallel example

After T03: T04-T05 (AnalysisFeatures tests) and T08 (ParameterGraph tests) touch different
packages and can be written together.

## Implementation strategy

MVP = T01-T04 (the roadmap acceptance in the package); then bounds and silence (T05), the bus (T06,
T07), the modulation source (T08-T10); polish last.

## Analysis (speckit-analyze, 2026-11-14)

| ID | Category | Severity | Location | Summary | Fix applied |
|----|----------|----------|----------|---------|-------------|
| F1 | Inconsistency | HIGH | spec R4, tasks T04 | T04 asserted "the documented value" before any value was documented: circular | T04 records the measured lag in spec.md first, then asserts that constant within one hop and also against the model bound (smoother's 90 % time ≤ lag ≤ that + one window) |
| F2 | Inconsistency | MEDIUM | spec Clarifications (release 0.4 s, snap 0.001), tasks T05 | "decays to exactly 0 within 1.0 s" contradicted the release time: ≈ 2.9 decades × 0.4 s ≈ 1.16 s plus the window | T05 allows 1.5 s with the arithmetic stated |
| C1 | Coverage | LOW | spec R12 | "the existing level meter is unchanged" had no check | T11 checks `git diff --stat` on Packages/AudioCore |
| C2 | Coverage | LOW | spec R10, R11 | Real-time and clock rules are not unit-testable | Already covered: T03 evidence reads the diff |

Coverage: R1-R12 and S1-S6 each map to at least one task (R1 → T02-T04, R2 → T02, R3-R4 → T04,
R5 → T05, R6 → T04, R7 → T06-T07, R8 → T08-T09, R9 → T10, R10-R11 → T03, R12 → T11;
S1 → T04, S2 → T05, S3 → T04, S4 → T06, S5 → T08-T10, S6 → T07, T11). Constitution: no
conflicts (I, VI, VII, VIII, X pass in plan.md). No critical issues; 0 ambiguities or
duplications left.
