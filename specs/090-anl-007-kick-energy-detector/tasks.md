# Tasks: ANL-007 Kick Energy Detector

**Input**: Design documents in `specs/090-anl-007-kick-energy-detector/` (spec.md, plan.md,
research.md, data-model.md, contracts/transient-detector.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure)
is recorded before the production change. Budgets (owner rule 7): a unit test about 1-2 s (≤ 10 s),
each package suite under 1 minute; the AnalysisFeatures Linux-shape suite already takes ≈ 68-81 s,
so this row adds at most a few hundred milliseconds there. Representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel.
`{sim}` = needs the row's own iOS 27.2 simulator "ANL7 iPhone 17" (created for this row, deleted
afterwards). Inside descriptions "T03" is short for `ANL-007-T03`. A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] ANL-007-T01 Record the baseline: `swift test --package-path Packages/AnalysisFeatures` on the host and in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/AnalysisFeatures/.build/linux`); `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`. Evidence: counts and durations recorded here. — Verified 2026-11-13: at 97bb762, AnalysisFeatures 116 tests on the host (39.9 s) and 116 in the Linux shape (67.7 s, 1 skipped), 0 failures; the four checks OK; test_scripts.py 147 OK (1 skipped) (.build/scratch/anl007-T01-*.log, anl007-scripts.log).

## Phase 2: Foundational (blocks every story)

- [X] ANL-007-T02 Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/TransientTestSupport.swift` (hop-aligned decaying sine bursts, sustained tones, seeded white noise and TPDF-level dither, a runner through a `.silence` lead-in stream at 2,048/512/44.1 kHz returning events, envelopes and per-frame levels) and the configuration tests in `KickDetectorTests.swift` (`.kick` defaults: 40/150 Hz, −70 dB floor, −15 dB dominance, 1.0 s window, 9 dB minimum rise, multiplier 4, 100 ms refractory, 100 ms envelope; each invalid field throws; `baselineFrames(hop: 512) == 86`, `refractorySamples == 4410`). Record the red run. — Verified 2026-11-13: red run = compile failure "cannot find 'TransientDetectorConfiguration' in scope" (.build/scratch/anl007-T02-red.log). Defaults updated to −15 dB and 9 dB by the T04 finding (spec Clarifications).
- [X] ANL-007-T03 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/TransientDetectorConfiguration.swift` (contract C1: `TransientBand`, errors, configuration with the data-model ranges "20 ≤ lower < upper ≤ rate/2", "floor −120…−20", "dominance −60…0", "baseline > 0, ≤ 2 s", "minimum rise > 0, ≤ 40 dB", "multiplier 0…20", "refractory 0…2 s", "envelope > 0, ≤ 5 s"; `TransientEvent`) and `BandTransientDetector.swift` (contract C2; preallocated tables and windows; typed arithmetic steps; `process` allocates, locks, logs and reads no clock, ANL-007-R13, R14, checked by reading the diff). Evidence: T02 passes on the host and in the Linux shape. — Verified 2026-11-13: KickDetectorTests configuration tests pass on the host and in the Linux shape; diff read: every buffer is allocated in `init` (weight tables, squares, level/power histories, D ring, sorted window, deviation scratch), `process` uses only stored arrays and pointers, scalar `log10f` (two per frame) and one `exp` only when the hop changes, no lock, print or clock (.build/scratch/anl007-T03-*.log).

## Phase 3: User Story 1 - kicks fire, other drums do not (P1) 🎯 MVP

**Independent test**: `KickDetectorTests` acceptance cases.

- [X] ANL-007-T04 [US1] Add to `KickDetectorTests.swift`: a 55 Hz decaying burst train (4 pulses, 255 ms apart, −6 dBFS) fires once per pulse within one hop of each start; 5 kHz and 1 kHz bursts (alternating, −6 dBFS) fire zero times; the kick train at −12 dBFS under a sustained pad (2 kHz + 3.3 kHz tones, −6 dBFS each) plus seeded white noise at −30 dBFS (a hi-hat-like layer) fires once per pulse and nothing else. Evidence: passes on the host and in the Linux shape; fixture table recorded. — Verified 2026-11-13: both tests pass on the host (KickDetectorTests 7 tests, 0.29 s) and in the Linux shape (0.97 s); fixture table in spec.md Implementation results (.build/scratch/anl007-T04-*.log).

## Phase 4: User Story 2 - level independence (P1)

- [X] ANL-007-T05 [US2] Add to `KickDetectorTests.swift`: the kick train at −30 dBFS and at −6 dBFS gives identical event sample positions (and equal counts). Evidence: passes on both shapes. — Verified 2026-11-13: part of `testLowPulsesFireOncePerPulseAtAnyLevelAndHighOrMidPulsesNever` (shares the loud run to save time), 4 = 4 events at identical sample indices, host and Linux shape.

## Phase 5: User Story 3 - no false kicks (P1)

- [X] ANL-007-T06 [US3] Add to `KickDetectorTests.swift`: a sustained 60 Hz tone (1.2 s, −12 dBFS) fires at most once, within one hop of its start; digital silence (0.3 s), dither-level noise (±1 LSB of 16 bit, 0.3 s) and white noise at −6 dBFS (1.2 s, seed fixed) fire zero times and the envelope stays 0; two pulses 60 ms apart give one event, 150 ms apart give two; after `reset()` the next pulse fires and the sequence continues; a frame at another sample rate or with a wrong magnitude count is ignored and counted, never an event (spec edge cases). Evidence: passes on both shapes. — Verified 2026-11-13: three tests pass on the host and in the Linux shape; the bass fires exactly once at its start.

## Phase 6: Bus integration (serves US1, US4)

- [X] ANL-007-T07 [US1] Write the pipeline test in `KickDetectorTests.swift` (stereo kick train through a real `NormalizedPCMRing` analysis tap and `AnalysisPipeline.step()` with a `StepClock`): one `.transient(band: .kick, …)` event per pulse, in ID order after its frame, `eventSample` within one hop of the pulse; frames' `kickEnvelope` is 1 at each kick's frame and decays (strictly smaller on the next frame); a 5 kHz train yields no transient event. Record the red run. — Verified 2026-11-13: red run = compile failure (no `.transient` event kind; .build/scratch/anl007-T07-red.log). The test feeds one hop per chunk so the recorder sees every frame; 3 kicks at −12 dBFS give 3 events at 12288, 24064, 35328 for starts 12288, 23552, 34816 (pulses 2-3 one hop later: the previous burst's tail is still in the reference window at 255 ms spacing; offline runs give the same positions at −6, −12, −18, −24, −30 and −40 dBFS).
- [X] ANL-007-T08 [US1] Implement in `AnalysisBusTypes.swift` (`.transient` kind, `AnalysisFrame.kickEnvelope` defaulted to 0), `AnalysisPipelineConfiguration.swift` (`kick`, rate check) and `AnalysisPipeline.swift` (own, reset per session, run per frame, publish after onset and beat); handle `.transient` in `Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift`. Evidence: T07 passes; AnalysisFeatures whole suite on the host and in the Linux shape; PerformanceControl suite on the host. — Verified 2026-11-13: KickDetectorTests 8 pass on the host (0.44 s); AnalysisFeatures whole suite 124 tests, 0 failures on the host (57.5 s while other builds ran) and in the Linux shape (67.4 s, 1 skipped; baseline 67.7 s); PerformanceControl 118 tests (8 + 110), 0 failures (.build/scratch/anl007-T08-*.log).

## Phase 7: User Story 4 - Kick modulation source (P2)

- [X] ANL-007-T09 [P] [US4] Add tests: `AudioFeatureSourceTests` (`audio.kick` round-trips, reads `frame.kick`, nil/non-finite → 0), `ExpressionPathologicalTests` opcode list gains 9, an evaluation test that `audio.kick * 2` reads the frame's kick, in `Packages/ParameterGraph/Tests/`. Record the red run. — Verified 2026-11-13: red run = compile failure "type 'AudioFeatureSource' has no member 'kick'" (.build/scratch/anl007-T09-red.log). Also added: a modulator test that a Kick binding follows the envelope.
- [X] ANL-007-T10 [US4] Implement `AudioFeatureSource.kick` and `AudioFeatureFrame.kick` in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`, `ExpressionOpcode.kick = 9` in `CompiledExpression.swift` and `ExpressionCompiler.swift`. Evidence: ParameterGraph suite passes on the host. — Verified 2026-11-13: ParameterGraph 112 tests (73 + 39, 1 skipped), 0 failures on the host. Finding: MOD-013's migration tests (ParameterGraph `ModulationIDMigrationTests`, SceneFormat `SceneModulationRestoreTests` and `SceneModulationPropertyTests`) used `audio.kick` as a made-up legacy ID renamed to `audio.onset` (and `audio.snare` as an unknown target); with a real `audio.kick` the registry refused that table. The placeholders were renamed `audio.legacyPulse` and `audio.legacyHit` (no production table uses them); SceneFormat 86 tests, 0 failures (.build/scratch/anl007-T10-pg.log, anl007-T11-sf.log).
- [X] ANL-007-T11 [US4] Add `kickEnvelope` to `LiveBandFrameInfo` in `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`; in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift` keep the last envelope read and pass it through `applyModulation(bands:kick:timeNanoseconds:)`; add "Kick binds and drives the glow" to `Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift`. Evidence: VisualGenerators suite on the host; projectM-iOSTests pass `{sim}`. — Verified 2026-11-13: VisualGenerators 133 tests, 0 failures on the host; projectM-iOSTests 403 tests, 0 failures (15.7 s) on the row's iOS 27.2 simulator "ANL7 iPhone 17", including `testKickBindsAndDrivesTheGlow`; no compiler warnings in the touched files. The host also resets its kick envelope when the loop restarts after a pause (.build/scratch/anl007-T11-*.log).

## Phase 8: Polish

- [X] ANL-007-T12 Record the fixture table and the Linux-shape growth in `spec.md` (Implementation findings), run the five scripts (check_compliance covers ANL-007-R15: nothing new reaches projectM), count PosterBoard reports, delete the row's simulator, mark the spec Implemented. — Verified 2026-11-13: spec Implementation results hold the fixture table and the test cost; check_compliance, validate_docs, check_motion_policy, check_permission_catalog OK; test_scripts.py 147 OK (1 skipped); PosterBoard reports 25 before and after the simulator run; simulator "ANL7 iPhone 17" deleted; spec marked Implemented.

## Dependencies

T01 → T02 → T03 → (T04, T05, T06) → T07 → T08 → T09 → T10 → T11 → T12. T09 can be written in
parallel with T04-T08 (different package).

## Parallel example

After T03: T04-T06 (AnalysisFeatures tests) and T09 (ParameterGraph tests) touch different
packages and can be written together.

## Implementation strategy

MVP = T01-T04 (the roadmap acceptance in the package); then level independence and false-trigger
guards (T05, T06), the bus (T07, T08), the modulation source (T09-T11); polish last.

## Analysis (speckit-analyze, 2026-11-13)

| ID | Category | Severity | Location | Summary | Fix applied |
|----|----------|----------|----------|---------|-------------|
| F1 | Inconsistency | MEDIUM | tasks T04 | Garbled noise-layer wording | Reworded: seeded white noise at −30 dBFS as the hi-hat-like layer |
| C1 | Coverage | MEDIUM | spec R13, R14 | No task named the real-time and clock rules | T03 evidence now includes reading the diff for R13/R14 |
| C2 | Coverage | LOW | spec edge cases | Ignored frames (rate, magnitude count) untested | Added to T06 |
| C3 | Coverage | LOW | spec R15 | No task for the projectM boundary | T12's check_compliance run cites R15 |

Coverage: R1-R15 and S1-S7 each map to at least one task (R1-R9 → T02-T06, R10 → T07-T08,
R11 → T09-T10, R12 → T11, R13-R15 → T03, T12; S1 → T04, S2 → T05, S3 → T04, S4 → T06, S5 → T07,
S6 → T09-T11, S7 → T12). Constitution: no conflicts (I, VI, VII, VIII, X pass in plan.md). No
critical issues; 0 ambiguities or duplications left.
