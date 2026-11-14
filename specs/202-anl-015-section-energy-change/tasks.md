# Tasks: ANL-015 Section Energy Change

**Input**: Design documents from `specs/202-anl-015-section-energy-change/` (spec, plan, research, data-model, contracts/section-energy-change.md, quickstart)

**Tests**: requested by the roadmap acceptance and the brief (quiet-to-loud fixture fires once after the dwell; bursts fire nothing; loud-to-quiet; NaN; determinism and chunking; Linux shape; app binding test). Budgets (owner rule 7): each unit test ≤ 2 s on the host.

## Phase 1: Setup

- [X] ANL-015-T01 Record the baseline: ANL-013 integrated in the branch (commit `2cf81d9d`), opcode 35 free on `autonomous/integration` and every feature branch, AnalysisFeatures test count, PosterBoard count (spec Implementation results) — Verified 2026-11-14: baseline 2cf81d9d (ANL-013 integrated); opcode 35 unused on autonomous/integration and every feature/* branch; AnalysisFeatures 179 → 186 tests; PosterBoard 25

## Phase 2: Foundational

- [X] ANL-015-T02 Add `SectionChangeConfiguration` (data-model defaults: sampleRate 44,100, hop 512, windowFrames 35 in 1…64, floor −70 "finite, < 0", settle 2.0 s, reference τ 8.0 s, enter 6 dB "> holdDecibels", hold 3 dB "≥ 0", dwell 2.0 s, refractory 4.0 s, envelope τ 1.0 s; refusals as typed errors; derived sample counts and per-frame coefficients), `SectionChangeDirection`, `SectionChange` in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SectionEnergyChange.swift — Verified 2026-11-14: SectionEnergyChangeTests.testConfigurationDefaultsAndRefusals (derived samples 88,200/176,400, coefficients, refusals, pipeline sampleRateMismatch for rate and hop)
- [X] ANL-015-T03 Add `SectionChangeDetector` (contract C1-C3: floor clamp, 35-entry power ring allocated once at init, with a recomputed mean, settle, reference follower, pending with hysteresis, sample-counted dwell, refractory, envelope; `reset`; no heap, lock, log or clock) in Packages/AnalysisFeatures/Sources/AnalysisFeatures/SectionEnergyChange.swift — Verified 2026-11-14: SectionEnergyChangeTests 7/7 on the host and with -DANALYSIS_NO_ACCELERATE

## Phase 3: User Story 1 - Quiet-to-loud fires once after the dwell (P1) 🎯 MVP

**Independent test**: `swift test --filter SectionEnergyChangeTests`.

- [X] ANL-015-T04 [US1] Acceptance test `testQuietToLoudFiresOnceAfterDwell`: 4 s of a 1 kHz tone at −40 dBFS then 6 s at −10 dBFS through the real spectrum stream and ANL-014 level → exactly one `.rising` change with confirmSample in [step + 88,200, step + 88,200 + 2,048]; plus configuration defaults and refusals, in Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SectionEnergyChangeTests.swift — Verified 2026-11-14: testQuietToLoudFiresOnceAfterDwell: one .rising, confirmed step + dwell + 1,128 samples (≤ 2,048)

## Phase 4: User Story 2 - Bursts and steady music fire nothing (P1)

- [X] ANL-015-T05 [US2] Tests: 1.0 s and 1.5 s loud bursts in a quiet tone, steady tone, a jittering level (±2 dB, seeded), silence, a 0.5 dB/s drift → no change; a 4 dB/s fade → only rising changes at least dwell + refractory apart; a step during the 2 s settling period → no change (spec Edge Cases), in SectionEnergyChangeTests.swift — Verified 2026-11-14: testBriefBurstsSteadyInputAndSettlingFireNothing (1.0/1.5 s bursts, settling step, steady, silence, jitter, drift: none; fade: two .rising 6.0 s apart)

## Phase 5: User Story 3 - Loud-to-quiet and bad input (P2)

- [X] ANL-015-T06 [US3] Tests: loud then quiet (and loud then silence) → exactly one `.falling` change after the dwell; non-finite levels and samples keep every value finite and the envelope in 0…1; envelope is 1 on the change frame, decays and snaps to 0; silence then a tone after settling → one `.rising`; a loud section of 3 s (rise, then fall inside the 4 s refractory) → the fall fires only after the refractory ends (ANL-015-R5), in SectionEnergyChangeTests.swift — Verified 2026-11-14: testLoudToQuietFiresOnceAfterDwell and testRefractoryEnvelopeAndNonFiniteLevels

## Phase 6: User Story 4 - Pipeline, source and app (P2)

- [X] ANL-015-T07 [US4] Pipeline: `AnalysisEventKind.sectionChange`, `AnalysisFrame.sectionChangeEnvelope`/`.sectionLevelDecibels`, `AnalysisPipelineConfiguration.sectionChange` (sample-rate and hop check), detector run per frame after the loudness and reset on session start, event published last, in Packages/AnalysisFeatures/Sources/AnalysisFeatures/{AnalysisBusTypes,AnalysisPipelineConfiguration,AnalysisPipeline}.swift; exhaustive switch in Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift; pipeline test (quiet then loud, chunking-invariant: two chunk sizes give identical events, one event, envelope 1 on its frame) in SectionEnergyChangeTests.swift — Verified 2026-11-14: testThePipelinePublishesOneSectionChange and testChunkingInvarianceAndReset; PerformanceControl Tempo 48/48, VisualGenerators BeatRing|LiveBand 16/16; AnalysisFeatures 186 tests, 0 failures in the Linux shape
- [X] ANL-015-T08 [P] [US4] `AudioFeatureSource.sectionChange` (`audio.sectionChange`), `AudioFeatureFrame.sectionChange`, `ExpressionOpcode.sectionChange = 35` with compiler and evaluator cases, in Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift and Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift; tests in Packages/ParameterGraph/Tests/ — Verified 2026-11-14: ParameterGraph swift test: 200 tests (1 skipped), 0 failures (3 new)
- [X] ANL-015-T09 [US4] `LiveBandFrameInfo.sectionChange` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift; `NativeSpectrumHost` keeps, resets and passes it in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift; `inspectorName` "Section change" in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift — Verified 2026-11-14: projectM-iOS build-for-testing succeeded on ANL15 iPhone 17 (iOS 27.2); testSectionChangeBindsAndDrivesTheGlow
- [X] ANL-015-T10 [US4] App test `testSectionChangeBindsAndDrivesTheGlow` in Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift, run on simulator "ANL15 iPhone 17" — Verified 2026-11-14: AudioFeatureBindingAppTests 11/11 on ANL15 iPhone 17 (iOS 27.2) in 1.5 s

## Phase 7: Polish

- [X] ANL-015-T11 Linux shape (ANL-015-R11), type-check budget, repo checks, audit that nothing reaches projectM and no setting, stored key or status event was added (ANL-015-R12), privacy manifest and network symbols on the built app; results, test cost and PosterBoard counts in spec.md; spec status Implemented — Verified 2026-11-14: repo checks OK (compliance, docs, motion, permission catalog, status events), test_scripts 159 OK, check_privacy_manifest OK, check_network_symbols OK; no type-check warning in a touched file (spec Implementation results)
- [ ] ANL-015-T12 {device} Play a track with a quiet intro and a loud chorus on D1 with a native visual and a "Section change" binding on the glow: one flash about 2 s into the chorus, none on drum hits (quickstart)

## Dependencies

T01 → T02 → T03 → (T04, T05, T06) → T07; T08 is independent of T02-T07; T09 needs T07 and T08; T10 needs T09; T11 last; T12 after the merge, on a device.
Parallel: T08 alongside T04-T07 (different package).

## Implementation strategy

MVP = Phase 2 + US1 (the roadmap acceptance). Then US2-US3 (same test file), then the pipeline, the source and the app.
