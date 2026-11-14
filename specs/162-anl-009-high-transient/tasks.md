# Tasks: ANL-009 High-Frequency Transient Detector

**Input**: `specs/162-anl-009-high-transient/` (spec, plan, research, data-model, contracts/high-transient.md, quickstart).

**Tests**: test-first where practical; budgets (owner rule 7): each new test ≤ 2 s on the host and
≤ 5 s in the Linux shape, representative cases only. `{sim}` = needs the row's simulator
"ANL9 iPhone 17" (iOS 27.2), created for this row and deleted afterwards. "T03" means `ANL-009-T03`.
A task is ticked only with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] ANL-009-T01 Baseline: AnalysisFeatures `KickDetectorTests` and `MidTransientDetectorTests` on the host; opcode 18 free on every `feature/*` branch.

## Phase 2: Foundational

- [ ] ANL-009-T02 Write `HighTransientTestSupport.swift` (high-pass noise clicks, continuous high noise, 1 s span counter, uncapped configuration; research D5) and `testHighTransientDefaults` (data-model values; `refractorySamples == 1764`; `envelopeDecay(hop: 512) == exp(−512/2205)`; `rateWindowSamples == 44100`; kick and mid uncapped; −1 and 65 throw) (ANL-009-R3, R4, R5). Red run = compile failure.
- [ ] ANL-009-T03 Implement contracts C1/C2 in `TransientDetectorConfiguration.swift` and `BandTransientDetector.swift`. Evidence: T02 passes; every `KickDetectorTests` and `MidTransientDetectorTests` test passes unchanged; diff read: the rate ring is allocated in `init`, `process` adds no allocation, lock, log or clock, no second FFT (ANL-009-R10); constructing the detector builds the 6–16 kHz weight tables for every ANL-001 size (its `init` preconditions a non-empty band per size; ANL-009-R2).

## Phase 3: User Story 1 - high-band clicks fire (P1) 🎯 MVP

- [ ] ANL-009-T04 [US1] `testHighBandClicksFireOnceEachWithinOneHop`: 4 clicks (−12 dBFS) → 4 events within one hop, band `.highTransient`, confidence ≥ 0.5, no extras; positions are sample-clock indices (ANL-004's rule, no clock read; ANL-009-R7); identical positions at −30 and −6 dBFS (ANL-009-S1).

## Phase 4: User Story 2 - bounded event counts (P1)

- [ ] ANL-009-T05 [US2] `testDenseClicksAreCappedAtTheMaximumRate` (50/s for 3 s at 2,048/512 and 512/128: ≤ 12 per 1 s span, ≤ 36 in all), `testTheCapLimitsFastClicksThatWouldOtherwiseFire` (20/s at 512/128: uncapped > 12 per 1 s, capped exactly 12, capped + suppressed = uncapped, subset), `testContinuousHighNoiseGivesABoundedEventCount` (10 s: ≤ 12 per 1 s span, ≤ 120 in all, both geometries) (ANL-009-S2, S3).

## Phase 5: User Story 3 - low and mid material, timing (P1)

- [ ] ANL-009-T06 [US3] `testKickAndMidBurstDoNotTriggerConfidently` (60 Hz kick and ANL-008 mid bursts: no event with confidence ≥ 0.5; silence and dither: none) and `testRefractoryPeriodAndDeterminism` (35 ms apart → 1, 2 with refractory 0; 93 ms apart → 2; envelope 1 then decaying; two fresh runs identical) (ANL-009-S4).

## Phase 6: Bus integration

- [ ] ANL-009-T07 Pipeline (contract C3) and `testThePipelinePublishesHighTransientEventsWithConfidence`: 3 clicks → 3 `.highTransient` events within one hop, ordered after their frame, frame envelope 1 and value = confidence, decaying next frame; full AnalysisFeatures suite passes (ANL-009-R6, S5).

## Phase 7: User Story 4 - modulation source (P2)

- [ ] ANL-009-T08 [US4] ParameterGraph: source, frame field, opcode 18; tests in `AudioFeatureSourceTests`, `AudioFeatureModulatorTests`, `ExpressionEvaluationTests`, opcode list in `ExpressionPathologicalTests` (contract C4).
- [ ] ANL-009-T09 [US4] `LiveBandFrameInfo.highTransient`; `NativeSpectrumHost` feeds it; `inspectorName` "High transient"; VisualGenerators suite on the host.
- [ ] ANL-009-T10 [US4] {sim} App test `testHighTransientBindsAndDrivesTheGlow` (glow follows the value; inspector name) on "ANL9 iPhone 17" (ANL-009-R9, S6).

## Phase 8: Polish

- [ ] ANL-009-T11 Linux shape (`-DANALYSIS_NO_ACCELERATE`) for `HighTransient|MidTransient|KickDetector`; type-check budget flags on the app build; repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`); `check_privacy_manifest` and `check_network_symbols` on the Debug app; naming audit (`grep -riE "hi-?hat|cymbal"` in changed sources shows only disclaimers); boundary audit of the diff: no new UserDefaults key, setting or projectM call (ANL-009-R1, R11, R12, S7).
- [ ] ANL-009-T12 Record results (fixture table, test cost) in spec.md; status Implemented.

## Dependencies

T01 → T02 → T03 → T04, T05, T06 → T07 → T08 → T09 → T10 → T11 → T12. T08 can start after T03.

## Analysis (speckit-analyze, 2026-11-14)

Coverage check of R1-R12 and S1-S7 against T01-T12. Three findings fixed: R2 (every FFT size) had
no evidence step (added to T03: the detector's `init` builds and checks the band for every size);
R7 (sample-clock timestamps) was only implied (stated in T04); R12 (no settings, nothing to
projectM) had no evidence step (boundary audit added to T11). No duplicate, ambiguous or
conflicting items remain; the constitution checks in plan.md pass; terminology ("High transient",
`highTransient`, `audio.highTransient`, opcode 18) is consistent across spec, plan, data model,
contract and tasks.
