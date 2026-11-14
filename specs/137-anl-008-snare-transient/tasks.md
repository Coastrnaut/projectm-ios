# Tasks: ANL-008 Mid Transient Detector

**Input**: `specs/137-anl-008-snare-transient/` (spec, plan, research, data-model, contracts/mid-transient.md, quickstart).

**Tests**: test-first where practical; budgets (owner rule 7): each new test ≤ 2 s in the Linux
shape, representative cases only. `{sim}` = needs the row's simulator "ANL8 iPhone 17" (iOS 27.2),
created for this row and deleted afterwards. "T03" means `ANL-008-T03`. A task is ticked only with
" — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] ANL-008-T01 Baseline: AnalysisFeatures `KickDetectorTests` on the host and in the Linux shape; ParameterGraph suite on the host. Record counts.

## Phase 2: Foundational

- [ ] ANL-008-T02 Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/MidTransientTestSupport.swift` (mid-band noise bursts, research D5) and configuration tests in `MidTransientDetectorTests.swift` (`.midTransient` values; invalid breadth weight and margin throw; `.kick` breadth weight 0; `refractorySamples == 3087`, `envelopeDecay(hop: 512) == exp(−512/3528)`, ANL-008-R4, R5). Red run = compile failure.
- [ ] ANL-008-T03 Implement contract C1/C2 in `TransientDetectorConfiguration.swift` and `BandTransientDetector.swift` (band case, fields, preset, `TransientEvent.confidence`, `lastConfidence`, breadth from the squares on event frames only). Evidence: T02 passes; every `KickDetectorTests` test passes unchanged (ANL-008-R6); diff read: no allocation, lock, log or clock in `process`, no second FFT (ANL-008-R11).

## Phase 3: User Story 1 - mid-band hits fire with a confidence (P1) 🎯 MVP

- [ ] ANL-008-T04 [US1] Acceptance test: 4 mid-band noise bursts at hop-aligned starts (−12 dBFS) give 4 events, each within one hop of its start, band `.midTransient`, confidence ≥ 0.5, no extras; the same bursts at −30 and −6 dBFS give identical positions (ANL-008-S1, S2).

## Phase 4: User Story 2 - kicks, tones, silence do not fire (P1)

- [ ] ANL-008-T05 [US2] Tests: 60 Hz kick bursts give no event with confidence ≥ 0.5; a steady 2 kHz tone fires at most once (at its onset) and the onset event's confidence is below that of the noise bursts; silence and ±1 LSB dither fire zero times; bursts 40 ms apart give one event, 120 ms apart give two; two fresh detectors on the same input give identical events (ANL-008-S3, S4).

## Phase 5: Bus integration

- [ ] ANL-008-T06 Pipeline: `AnalysisEventKind.transient` gains `confidence`; `AnalysisFrame.midTransientEnvelope`, `midTransientConfidence`, `midTransient`; `AnalysisPipelineConfiguration.midTransient`; the pipeline runs and resets the detector and publishes after the kick (contract C3). Test in `MidTransientDetectorTests`: mid bursts through `AnalysisPipeline` give one `.midTransient` event each with confidence, frame value jumps and decays; kick tests updated only for the new associated value (ANL-008-S5).

## Phase 6: User Story 3 - modulation source (P2)

- [ ] ANL-008-T07 [US3] ParameterGraph: `AudioFeatureSource.midTransient`, `AudioFeatureFrame.midTransient`, opcode 17; tests in `AudioFeatureSourceTests`, `AudioFeatureModulatorTests`, `ExpressionEvaluationTests`, and the opcode list in `ExpressionPathologicalTests` (contract C4, ANL-008-S6).
- [ ] ANL-008-T08 [US3] `LiveBandFrameInfo.midTransient`; `NativeSpectrumHost` feeds it to `applyModulation`; VisualGenerators suite on the host.
- [ ] ANL-008-T09 [US3] {sim} App test `testMidTransientBindsAndDrivesTheGlow` in `Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift`; run `AudioFeatureBindingAppTests` on "ANL8 iPhone 17".

## Phase 7: Polish

- [ ] ANL-008-T10 Linux shape: AnalysisFeatures `MidTransient|KickDetector` tests with `-DANALYSIS_NO_ACCELERATE`; type-check budget flags on the changed app file; repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`); naming audit (`grep -ri snare` in changed sources shows only "not a snare classifier" disclaimers) (ANL-008-R1, R12, S7).
- [ ] ANL-008-T11 Record results (fixture table, test cost) in spec.md; status Implemented.

## Dependencies

T01 → T02 → T03 → T04, T05 → T06 → T07 → T08 → T09 → T10 → T11. T07 can start after T03.

## Analysis (speckit-analyze, 2026-11-14)

Coverage check of R1-R13 and S1-S7 against T01-T11. Two findings fixed: R4/R5 had no explicit evidence (added the refractory-samples and envelope-decay assertions to T02); R11 (no second FFT, real-time rules) had no evidence step (added the diff read to T03). No duplicate, ambiguous or conflicting items remain; constitution checks pass.
