# Tasks: ANL-011 Spectral Rolloff

**Input**: Design documents from `specs/182-anl-011-spectral-rolloff/` (spec, plan, research, data-model, contracts/spectral-rolloff.md, quickstart)

**Tests**: requested by the roadmap acceptance and the brief (analytic reference spectra, fractions, silence, NaN, backends, determinism, app binding test). Budgets (owner rule 7): each unit test ≤ 2 s, the package suite < 1 min.

## Phase 1: Setup

- [ ] ANL-011-T01 Record the baseline: AnalysisFeatures test count and duration in the Linux shape, opcode 19 free, PosterBoard count (spec Implementation results)

## Phase 2: Foundational

- [ ] ANL-011-T02 Add `SpectralRolloffConfiguration` (sampleRate 44,100; lowerFrequency 20; upperFrequency nil = Nyquist; fraction 0.85, "finite, 0.5…0.99" else `invalidFraction`; floorDecibels −70, "finite, < 0"; normalization 50…20,000 Hz; `normalized(hz:)`; `binRange(size:)`) and `SpectralRolloffReading` in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectralRolloff.swift
- [ ] ANL-011-T03 Add `SpectralRolloffEstimator` with static `measure` (power, in-bin interpolation per research ANL-011-D2, clamp to [0, Nyquist], vDSP total behind `canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`, portable fallback, non-finite → 0) and `process`/`reset` (silence → `.none`; no buffer, allocation, lock, log or clock: ANL-011-R10) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectralRolloff.swift

## Phase 3: User Story 1 - The rolloff matches a known spectrum (P1) 🎯 MVP

**Independent test**: `swift test --filter SpectralRolloffTests` on reference spectra.

- [ ] ANL-011-T04 [US1] Acceptance tests: single tone at bin k, two tones 9:1 and 4:1, flat to a cutoff C, C = the last flat bin's upper edge (0.85·C), linear power ramp (C·√0.85), each within half a bin, in Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralRolloffTests.swift
- [ ] ANL-011-T05 [US1] Fraction tests: the same references at p = 0.5 and 0.99; configuration refuses 0.49, 1.0 and NaN, in SpectralRolloffTests.swift

## Phase 4: User Story 2 - Silence and bad input are calm (P1)

- [ ] ANL-011-T06 [US2] Silence, ±1 LSB dither (via SpectrumAnalyzer), NaN/inf magnitudes, tone-then-silence reads 0, wrong rate or count leaves the reading unchanged, in SpectralRolloffTests.swift

## Phase 5: User Story 3 - Same input, same reading (P2)

- [ ] ANL-011-T07 [US3] Determinism (bit-equal repeats) and accelerated vs portable within 0.001 bin (equal in the Linux shape), in SpectralRolloffTests.swift

## Phase 6: User Story 4 - Rolloff is a modulation source (P2)

- [ ] ANL-011-T08 [US4] Pipeline: `AnalysisFrame.rolloffHz`/`rolloff`, `AnalysisPipelineConfiguration.rolloff` (sample-rate check), estimator run on the existing magnitudes and reset on session start, in Packages/AnalysisFeatures/Sources/AnalysisFeatures/{AnalysisBusTypes,AnalysisPipelineConfiguration,AnalysisPipeline}.swift; pipeline test (low tone vs noise) in SpectralRolloffTests.swift
- [ ] ANL-011-T09 [P] [US4] `AudioFeatureSource.rolloff` (`audio.rolloff`), `AudioFeatureFrame.rolloff`, `ExpressionOpcode.rolloff = 19` with compiler and evaluator cases, in Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift and Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift; tests in Packages/ParameterGraph/Tests/ParameterGraphTests/{AudioFeatureSourceTests,AudioFeatureModulatorTests}.swift and Packages/ParameterGraph/Tests/ParameterExpressionTests/{ExpressionEvaluationTests,ExpressionPathologicalTests}.swift
- [ ] ANL-011-T10 [US4] `LiveBandFrameInfo.rolloff` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift; `NativeSpectrumHost` keeps, resets and passes it in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift; `inspectorName` "Rolloff" in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift
- [ ] ANL-011-T11 [US4] App test `testRolloffBindsAndDrivesTheGlow` (glow follows the rolloff; inspector name "Rolloff") in Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift, run on simulator "ANL11 iPhone 17"

## Phase 7: Polish

- [ ] ANL-011-T12 Linux shape (ANL-011-R11), type-check budget, repo checks, an audit that nothing reaches projectM and no setting or stored key was added (ANL-011-R12), privacy manifest and network symbols on the built app; results, test cost and PosterBoard counts in spec.md; spec status Implemented

## Dependencies

T01 → T02 → T03 → (T04, T05, T06, T07) → T08; T09 is independent of T02-T08; T10 needs T08 and T09; T11 needs T10; T12 last.
Parallel: T09 alongside T04-T08 (different package).

## Implementation strategy

MVP = Phase 2 + US1 (the roadmap acceptance). Then US2-US3 (same file), then US4 integration and the app test.
