# Tasks: ANL-013 Stereo Correlation

**Input**: Design documents from `specs/196-anl-013-stereo-correlation/` (spec, plan, research, data-model, contracts/stereo-correlation.md, quickstart)

**Tests**: requested by the roadmap acceptance and the brief (identical, inverted and independent fixtures; warning hold and hysteresis; silence; NaN; determinism; Linux shape; app binding and status test). Budgets (owner rule 7): each unit test ≤ 2 s, the new package tests together < 1 s on the host.

## Phase 1: Setup

- [ ] ANL-013-T01 Record the baseline: ANL-012 merged into the branch, opcode 34 free in every worktree, AnalysisFeatures test count, PosterBoard count (spec Implementation results)

## Phase 2: Foundational

- [ ] ANL-013-T02 Add `StereoCorrelationConfiguration` (data-model defaults and refusals; derived decay, floorMeanSquare, holdBlocks) and `StereoCorrelationReading` (`.none`) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/StereoCorrelation.swift
- [ ] ANL-013-T03 Add `StereoCorrelationMeter` (contract C1, C2: block sums in Double, smoothed sums, floor, clamp, non-finite → 0, warning counters, `reset`; no buffer, allocation, lock, log or clock) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/StereoCorrelation.swift

## Phase 3: User Story 1 - Opposite signs (P1) 🎯 MVP

**Independent test**: `swift test --filter StereoCorrelationTests`.

- [ ] ANL-013-T04 [US1] Acceptance tests: identical sine and seeded-noise fixtures > 0.99, inverted < −0.99 (opposite signs), independent noise |r| < 0.1; configuration defaults and refusals, in Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/StereoCorrelationTests.swift

## Phase 4: User Story 2 - Warning with hysteresis (P1)

- [ ] ANL-013-T05 [US2] Warning tests: off before the hold and on after it on an inverted fixture; clears only after the clear hold; a short return above −0.3 does not clear it; silence clears it after the hold, in StereoCorrelationTests.swift

## Phase 5: User Story 3 - Calm input (P1)

- [ ] ANL-013-T06 [US3] Silence, dither, one silent channel → 0; NaN/±∞ samples → finite in −1…1; mono (L = R, as AUD-009 non-Mix modes) → 1 and never warns; channels < 2 ignored, in StereoCorrelationTests.swift

## Phase 6: User Story 4 - Determinism (P2)

- [ ] ANL-013-T07 [US4] Bit-equal repeats and chunking invariance (1-frame, 333-frame and whole-buffer appends), reset returns to `.none`, in StereoCorrelationTests.swift

## Phase 7: User Story 5 - Modulation source and app (P2)

- [ ] ANL-013-T08 [US5] Pipeline: `AnalysisFrame.correlation`/`.phaseInverted`, `AnalysisPipelineConfiguration.correlation` (sample-rate check), meter fed each chunk before the mono mix and reset on session start, in Packages/AnalysisFeatures/Sources/AnalysisFeatures/{AnalysisBusTypes,AnalysisPipelineConfiguration,AnalysisPipeline}.swift; pipeline test (identical then inverted, the flag raised) in StereoCorrelationTests.swift
- [ ] ANL-013-T09 [P] [US5] `AudioFeatureSource.correlation` (`audio.correlation`, (r+1)/2), `AudioFeatureFrame.correlation`, `ExpressionOpcode.correlation = 34` with compiler and evaluator cases, in Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift and Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift; tests in Packages/ParameterGraph/Tests/ParameterGraphTests/{AudioFeatureSourceTests,AudioFeatureModulatorTests}.swift and Packages/ParameterGraph/Tests/ParameterExpressionTests/{ExpressionEvaluationTests,ExpressionPathologicalTests}.swift
- [ ] ANL-013-T10 [US5] `LiveBandFrameInfo.correlation`/`.phaseInverted` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift; `NativeSpectrumHost` keeps, resets and passes r and reports warning changes (`onPhaseWarningChange`) in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift; `inspectorName` "Correlation" in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift
- [ ] ANL-013-T11 [US2] App warning: Apps/projectM-iOS/Coordinators/AppCoordinator+StereoPhase.swift (state, `PhaseWarningAnnouncementThrottle`, overlay line), the host connection in AppCoordinator.swift, `SourceStatusIndicator.text(… phaseWarning:)`, `StatusEventCatalog.stereoPhase` (X3a, X3b) in StatusEvents.swift, the overlay line in PerformanceOverlay.swift and VisualizerView.swift; rows X3a/X3b in specs/100-acc-011-captioned-status-events/contracts/status-events.md
- [ ] ANL-013-T12 [US5] App tests: `testCorrelationBindsAndDrivesTheGlow` (glow follows (r+1)/2; inspector "Correlation") in Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift; Apps/projectM-iOS/Tests/StereoPhaseWarningTests.swift (status suffix, X3a once within 30 s, X3b after an announced raise, overlay line), run on simulator "ANL13 iPhone 17"

## Phase 8: Polish

- [ ] ANL-013-T13 Linux shape (ANL-013-R11), type-check budget, repo checks, audit that nothing reaches projectM and no setting or stored key was added (ANL-013-R12), privacy manifest and network symbols on the built app; results, test cost and PosterBoard counts in spec.md; spec status Implemented
- [ ] ANL-013-T14 {device} Play a phase-inverted stereo feed through Mix on D1 with a native visual: the overlay reads negative r and the source status shows the warning after about 1 s; switching AUD-009 to Left clears it (quickstart)

## Dependencies

T01 → T02 → T03 → (T04, T05, T06, T07) → T08; T09 is independent of T02-T08; T10 needs T08 and T09; T11 needs T10; T12 needs T10 and T11; T13 last; T14 after the merge, on a device.
Parallel: T09 alongside T04-T08 (different package).

## Implementation strategy

MVP = Phase 2 + US1 (the roadmap acceptance). Then US2-US4 (same file), then the pipeline, the source and the app.
