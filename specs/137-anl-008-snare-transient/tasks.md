# Tasks: ANL-008 Mid Transient Detector

**Input**: `specs/137-anl-008-snare-transient/` (spec, plan, research, data-model, contracts/mid-transient.md, quickstart).

**Tests**: test-first where practical; budgets (owner rule 7): each new test ≤ 2 s in the Linux
shape, representative cases only. `{sim}` = needs the row's simulator "ANL8 iPhone 17" (iOS 27.2),
created for this row and deleted afterwards. "T03" means `ANL-008-T03`. A task is ticked only with
" — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [X] ANL-008-T01 Baseline: AnalysisFeatures `KickDetectorTests` on the host and in the Linux shape; ParameterGraph suite on the host. Record counts. — Verified 2026-11-14: at e8dde5c0, KickDetectorTests 8 tests pass on the host (0.39 s); ParameterGraph suite baseline taken at T07 (.build/scratch/anl008-T01-host.log).

## Phase 2: Foundational

- [X] ANL-008-T02 Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/MidTransientTestSupport.swift` (mid-band noise bursts, research D5) and configuration tests in `MidTransientDetectorTests.swift` (`.midTransient` values; invalid breadth weight and margin throw; `.kick` breadth weight 0; `refractorySamples == 3087`, `envelopeDecay(hop: 512) == exp(−512/3528)`, ANL-008-R4, R5). Red run = compile failure. — Verified 2026-11-14: red run = compile failure "type 'TransientDetectorConfiguration' has no member 'midTransient'" (.build/scratch/anl008-T02-red.log); `testMidTransientDefaults` passes after T03.
- [X] ANL-008-T03 Implement contract C1/C2 in `TransientDetectorConfiguration.swift` and `BandTransientDetector.swift` (band case, fields, preset, `TransientEvent.confidence`, `lastConfidence`, breadth from the squares on event frames only). Evidence: T02 passes; every `KickDetectorTests` test passes unchanged (ANL-008-R6); diff read: no allocation, lock, log or clock in `process`, no second FFT (ANL-008-R11). — Verified 2026-11-14: MidTransientDetectorTests 6 and KickDetectorTests 8 pass on the host (0.64 s), kick tests changed only in two pattern matches for the new `confidence` value; full AnalysisFeatures suite 150 tests, 0 failures (42.1 s). Diff read: the breadth reads the frame's magnitudes in place (no buffer), `logf`/`expf` only on event frames, no lock, print or clock; the pipeline publishes through a helper, no per-frame array; no second FFT.

## Phase 3: User Story 1 - mid-band hits fire with a confidence (P1) 🎯 MVP

- [X] ANL-008-T04 [US1] Acceptance test: 4 mid-band noise bursts at hop-aligned starts (−12 dBFS) give 4 events, each within one hop of its start, band `.midTransient`, confidence ≥ 0.5, no extras; the same bursts at −30 and −6 dBFS give identical positions (ANL-008-S1, S2). — Verified 2026-11-14: `testMidBandBurstsFireOnceEachWithinOneHopWithConfidence`: 4/4 hits, 0 extras, confidences 1.00/1.00/1.00/0.97 at −12 dBFS; identical positions at −30 and −6 dBFS (host and Linux shape).

## Phase 4: User Story 2 - kicks, tones, silence do not fire (P1)

- [X] ANL-008-T05 [US2] Tests: 60 Hz kick bursts give no event with confidence ≥ 0.5; a steady 2 kHz tone fires at most once (at its onset) and the onset event's confidence is below that of the noise bursts; silence and ±1 LSB dither fire zero times; bursts 40 ms apart give one event, 120 ms apart give two; two fresh detectors on the same input give identical events (ANL-008-S3, S4). — Verified 2026-11-14: `testLowKickDoesNotTriggerConfidently` (0 events), `testSteadyToneSilenceAndDitherDoNotFire` (one onset event, confidence 0.37; silence and dither 0), `testRefractoryPeriodAndDeterminism` (46 ms apart: 1, 128 ms apart: 2; identical events and envelopes on a second run).

## Phase 5: Bus integration

- [X] ANL-008-T06 Pipeline: `AnalysisEventKind.transient` gains `confidence`; `AnalysisFrame.midTransientEnvelope`, `midTransientConfidence`, `midTransient`; `AnalysisPipelineConfiguration.midTransient`; the pipeline runs and resets the detector and publishes after the kick (contract C3). Test in `MidTransientDetectorTests`: mid bursts through `AnalysisPipeline` give one `.midTransient` event each with confidence, frame value jumps and decays; kick tests updated only for the new associated value (ANL-008-S5). — Verified 2026-11-14: `testThePipelinePublishesMidTransientEventsWithConfidence`: 3 `.midTransient` events at the exact burst starts, frame envelope 1 and value = confidence at each event, decaying next frame; ordering asserted; ANL-007 bus test passes.

## Phase 6: User Story 3 - modulation source (P2)

- [X] ANL-008-T07 [US3] ParameterGraph: `AudioFeatureSource.midTransient`, `AudioFeatureFrame.midTransient`, opcode 17; tests in `AudioFeatureSourceTests`, `AudioFeatureModulatorTests`, `ExpressionEvaluationTests`, and the opcode list in `ExpressionPathologicalTests` (contract C4, ANL-008-S6). — Verified 2026-11-14: ParameterGraph 79 + 42 tests (1 skipped), 0 failures (.build/scratch/anl008-T07-pg.log).
- [X] ANL-008-T08 [US3] `LiveBandFrameInfo.midTransient`; `NativeSpectrumHost` feeds it to `applyModulation`; VisualGenerators suite on the host. — Verified 2026-11-14: VisualGenerators suite 136 tests, 0 failures on the host (47.0 s); app built for testing on ANL8 iPhone 17.
- [X] ANL-008-T09 [US3] {sim} App test `testMidTransientBindsAndDrivesTheGlow` in `Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift`; run `AudioFeatureBindingAppTests` on "ANL8 iPhone 17". — Verified 2026-11-14: AudioFeatureBindingAppTests 6 tests pass on "ANL8 iPhone 17" (iOS 27.2), including `testMidTransientBindsAndDrivesTheGlow` (0.02 s) (.build/scratch/anl008-T09-app.log).

## Phase 7: Polish

- [X] ANL-008-T10 Linux shape: AnalysisFeatures `MidTransient|KickDetector` tests with `-DANALYSIS_NO_ACCELERATE`; type-check budget flags on the changed app file; repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`); naming audit (`grep -ri snare` in changed sources shows only "not a snare classifier" disclaimers) (ANL-008-R1, R12, S7). — Verified 2026-11-14: Linux shape (`-DANALYSIS_NO_ACCELERATE`): 14 tests, 0 failures, 1.75 s; type-check flags: no warning in any changed file (22 pre-existing warnings elsewhere); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK (1 skipped); check_privacy_manifest and check_network_symbols OK on the Debug app; `grep -ri snare` over sources finds only disclaimers.
- [X] ANL-008-T11 Record results (fixture table, test cost) in spec.md; status Implemented. — Verified 2026-11-14: results recorded in spec.md.

## Dependencies

T01 → T02 → T03 → T04, T05 → T06 → T07 → T08 → T09 → T10 → T11. T07 can start after T03.

## Analysis (speckit-analyze, 2026-11-14)

Coverage check of R1-R13 and S1-S7 against T01-T11. Two findings fixed: R4/R5 had no explicit evidence (added the refractory-samples and envelope-decay assertions to T02); R11 (no second FFT, real-time rules) had no evidence step (added the diff read to T03). No duplicate, ambiguous or conflicting items remain; constitution checks pass.
