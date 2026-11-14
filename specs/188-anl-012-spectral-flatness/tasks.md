# Tasks: ANL-012 Spectral Flatness

**Input**: Design documents from `specs/188-anl-012-spectral-flatness/` (spec, plan, research, data-model, contracts/spectral-flatness.md, quickstart)

**Tests**: requested by the roadmap acceptance and the brief (sine vs white-noise fixture, flat spectrum, silence, NaN, backends, determinism, app binding test). Budgets (owner rule 7): each unit test ≤ 2 s, the new tests together < 1 s on the host.

## Phase 1: Setup

- [X] ANL-012-T01 Record the baseline: ANL-011 merged into the branch, opcode 33 free in every worktree (20 is `min`), PosterBoard count (spec Implementation results) — Verified 2026-11-14: baseline 167 AnalysisFeatures tests with ANL-011 merged (autonomous/integration 2a895211), opcode 20 is `min` and 33 free in every worktree, PosterBoard 25

## Phase 2: Foundational

- [X] ANL-012-T02 Add `SpectralFlatnessConfiguration` (sampleRate 44,100 "finite, > 0"; lowerFrequency 20 "finite, > 0, < Nyquist"; upperFrequency nil = Nyquist; floorDecibels −70 "finite, < 0"; derived floorPower 1.5·10^(floor/10); `relativeEpsilon` 1e-12; `binRange(size:)`) and `SpectralFlatnessReading` (`flatness`, `hasSignal`, `.none`) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectralFlatness.swift — Verified 2026-11-14: SpectralFlatnessTests.testConfigurationDefaultsAndRefusals
- [X] ANL-012-T03 Add `SpectralFlatnessEstimator` with static `measure` (research ANL-012-D1, D2, D5, D6: power, ε = 10⁻¹²·A, Double log sum, clamp 0…1, vDSP total behind `canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`, portable fallback, non-finite → 0) and `process`/`reset` (silence → `.none`; no buffer, allocation, lock, log or clock: ANL-012-R9) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectralFlatness.swift — Verified 2026-11-14: SpectralFlatnessTests 6/6 on the host (vDSP) and with -DANALYSIS_NO_ACCELERATE

## Phase 3: User Story 1 - Tones read low, noise reads high (P1) 🎯 MVP

**Independent test**: `swift test --filter SpectralFlatnessTests`.

- [X] ANL-012-T04 [US1] Acceptance tests: single-bin sine spectrum < 0.05; PCM sines (bin-centred and 1 kHz) through `SpectrumAnalyzer` < 0.05; ≥ 8 seeded white-noise frames each > 0.4, mean in 0.45…0.65; sine ≥ 0.3 below the lowest noise frame; flat spectrum = 1 within 1e-9; configuration defaults and refusals, in Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralFlatnessTests.swift — Verified 2026-11-14: testSineReadsLowerFlatnessThanTheWhiteNoiseFixture (single bin 1.0e-12, PCM sines 1.1e-12 and 6.4e-12, 8 noise frames min 0.544, mean 0.5619), testFlatSpectrumReadsExactlyOne

## Phase 4: User Story 2 - Silence and bad input are calm (P1)

- [X] ANL-012-T05 [US2] Silence, ±1 LSB dither, NaN/inf magnitudes, tone-then-silence reads 0, wrong rate or count leaves the reading unchanged, a range of one bin reads 1 (spec Edge Cases), in SpectralFlatnessTests.swift — Verified 2026-11-14: testSilenceDitherNaNOneBinAndMismatchedFrames

## Phase 5: User Story 3 - Same input, same reading (P2)

- [X] ANL-012-T06 [US3] Determinism (bit-equal repeats), accelerated vs portable within 1e-6, scale invariance (×100 power reads the same within 1e-6), in SpectralFlatnessTests.swift — Verified 2026-11-14: testDeterministicBackendsAgreeAndScaleInvariant (host vDSP and Linux shape)

## Phase 6: User Story 4 - Flatness is a modulation source (P2)

- [X] ANL-012-T07 [US4] Pipeline: `AnalysisFrame.flatness`, `AnalysisPipelineConfiguration.flatness` (sample-rate check), estimator on the existing magnitudes and reset on session start, in Packages/AnalysisFeatures/Sources/AnalysisFeatures/{AnalysisBusTypes,AnalysisPipelineConfiguration,AnalysisPipeline}.swift; pipeline test (tone vs noise) in SpectralFlatnessTests.swift — Verified 2026-11-14: testThePipelineCarriesTheFlatness; AnalysisFeatures 173 tests, 0 failures in the Linux shape
- [X] ANL-012-T08 [P] [US4] `AudioFeatureSource.flatness` (`audio.flatness`), `AudioFeatureFrame.flatness`, `ExpressionOpcode.flatness = 33` with compiler and evaluator cases, in Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift and Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift; tests in Packages/ParameterGraph/Tests/ParameterGraphTests/{AudioFeatureSourceTests,AudioFeatureModulatorTests}.swift and Packages/ParameterGraph/Tests/ParameterExpressionTests/{ExpressionEvaluationTests,ExpressionPathologicalTests}.swift — Verified 2026-11-14: ParameterGraph swift test, 182 tests (1 skipped), 0 failures (3 new)
- [X] ANL-012-T09 [US4] `LiveBandFrameInfo.flatness` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift; `NativeSpectrumHost` keeps, resets and passes it in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift; `inspectorName` "Flatness" in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift — Verified 2026-11-14: VisualGenerators swift build; projectM-iOS build-for-testing succeeded on ANL12 iPhone 17
- [X] ANL-012-T10 [US4] App test `testFlatnessBindsAndDrivesTheGlow` (glow follows the flatness; inspector name "Flatness") in Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift, run on simulator "ANL12 iPhone 17" — Verified 2026-11-14: AudioFeatureBindingAppTests 9/9 on ANL12 iPhone 17 (iOS 27.2) in 1.4 s

## Phase 7: Polish

- [X] ANL-012-T11 Linux shape (ANL-012-R10), type-check budget, repo checks, an audit that nothing reaches projectM and no setting or stored key was added (ANL-012-R11), privacy manifest and network symbols on the built app; results, test cost and PosterBoard counts in spec.md; spec status Implemented — Verified 2026-11-14: repo checks OK (compliance, docs, motion, permission catalog, status events), test_scripts 159 OK, check_privacy_manifest OK, check_network_symbols OK, no type-check warning

## Dependencies

T01 → T02 → T03 → (T04, T05, T06) → T07; T08 is independent of T02-T07; T09 needs T07 and T08; T10 needs T09; T11 last.
Parallel: T08 alongside T04-T07 (different package).

## Implementation strategy

MVP = Phase 2 + US1 (the roadmap acceptance). Then US2-US3 (same file), then US4 integration and the app test.
