# Tasks: MOD-009 Tempo-Synced LFO

**Input**: Design documents in `specs/165-mod-009-tempo-lfo/` (spec.md, plan.md, research.md, data-model.md,
contracts/tempo-lfo.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded before the
production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under 1 minute. Logs go to
`.build/scratch/mod-009/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-009-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [X] MOD-009-T01 Record the baseline: `swift test` for `Packages/ParameterGraph`, `Packages/PerformanceControl` and `Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at 0c57cf7c on the host: ParameterGraph 160 tests (116 + 44, 1 skipped), 0 failures, 12 s wall; PerformanceControl 186 tests, 0 failures, 29 s wall; SceneFormat 151 tests, 0 failures, 15 s wall; PosterBoard reports 25 (.build/scratch/mod-009/T01-*.log).

## Phase 2: Foundational

None: the sync model (contract T1, T2) is User Story 1's deliverable.

## Phase 3: User Story 1 - a cycle follows the tempo in beats (P1) MVP

**Independent test**: `LFOSyncTests.testQuarterNoteCycleAt120BPMLastsHalfASecond`.

- [X] MOD-009-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/LFOSyncTests.swift`: acceptance at a fixed 120 BPM through the bank (frames at 60 fps from an origin): a 1-beat sine's samples at t and t + 0.5 s are equal within 1e-9 at several t (including after 1 h), its value at 0.125 s is the peak; a 4-beat triangle's samples at t and t + 2.0 s are equal within 1e-9 and at t + 1.0 s is half a cycle on; both equal the closed form at 2 Hz / 0.5 Hz; validation: allowed lengths accepted, 0, 0.3, 3, 16, NaN refused; BPM clamp (300 → 240, 20 → 40, NaN/0/−1 → no tempo). — Verified 2026-11-14: LFOSyncTests.swift written before the production code; red run `extra argument 'tempoBPM' in call` (.build/scratch/mod-009/red-T02.log).
- [X] MOD-009-T03 [US1] Record T02's red run; implement in `Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift`: `LFOSync`, `LFO.sync`, validation, `effectiveRateHz`, `value(elapsedNanoseconds:tempoBPM:maximumRateHz:)`, `LFO.phase(from:elapsedNanoseconds:rateHz:)` (MOD-007's method delegates; bit-identical), `LFOBank` segments and `values(atNanoseconds:tempoBPM:maximumRateHz:into:)`, `hasSyncedOscillators`. Evidence: T02 and every MOD-007 `LFOTests` pass. — Verified 2026-11-14: testQuarterNoteCycleAt120BPMLastsHalfASecond (1 beat at 120 BPM: samples 0.5 s apart equal within 1e-9 at four starts incl. after 1 h, peak at 0.125 s, trough at 0.375 s; 4 beats: equal 2.0 s apart, antisymmetric at 1.0 s; both equal the closed form) and testLengthsAndTempoBounds pass; every MOD-007 LFOTests test still passes; ParameterGraph 166 tests (122 + 44, 1 skipped), 0 failures, 0.29 s of tests (.build/scratch/mod-009/T03.log).

## Phase 4: User Story 2 - right tempo, smooth changes (P1)

**Independent test**: `LFOSyncTests.testTempoChangeKeepsPhaseContinuous`, `LFOTempoSourceTests`.

- [X] MOD-009-T04 [US2] Add to `LFOSyncTests.swift`: a 1-beat LFO at 120 BPM changes to 90 BPM at a frame mid-cycle: every frame-to-frame phase step ≤ max rate · frame (2 Hz · 1/60 s) plus 1e-9, the phase at the change frame equals the 120 BPM phase there, and after the change samples one 90 BPM period (2/3 s, frame-aligned check via the closed form from the change point) apart are equal within 1e-9; tempo lost (nil) falls back to the stored rate without a jump; determinism (two identical runs bit-identical); Reduce flashing: a ¼-beat LFO at 240 BPM (16 Hz) runs at 3 Hz (equals a 3 Hz closed form; 6 upward crossings in 2 s); turning the cap on mid-run is continuous; free-running slots still equal MOD-007's closed form while the tempo changes. — Verified 2026-11-14: testTempoChangeKeepsPhaseContinuous (120 → 90 BPM at 1.25 s where a pure 90 BPM phase would jump by 0.25 in value: every frame step ≤ 2·2 Hz·frame, the change frame keeps the 120 BPM phase, later frames equal the 90 BPM closed form from the change within 1e-9, samples 2 s apart equal), testTempoLostFallsBackWithoutJumpAndRunsAreDeterministic, testReduceFlashingCapsSyncedRateContinuously (¼ beat at 240 BPM equals a 3 Hz triangle, 6 crossings in 2 s; cap toggled mid-run without a jump), testFreeOscillatorsIgnoreTempoChanges pass (.build/scratch/mod-009/T03.log).
- [X] MOD-009-T05 [P] [US2] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/LFOTempoSourceTests.swift` and `Packages/PerformanceControl/Sources/PerformanceControl/TempoSnapshot+LFO.swift`: with a real `TempoSource`, a 1-beat LFO in a bank fed `snapshot.lfoTempoBPM` follows (a) a confident estimate (100 BPM, confidence 0.8) → 1.667 Hz; (b) a manual tap tempo (taps 500 ms apart → 120 BPM) over that estimate → 2 Hz; (c) after reset with an estimate of confidence 0.3 → nil → the stored fallback rate (0.25 Hz). — Verified 2026-11-14: LFOTempoSourceTests 2/2 (no tempo → 0.25 Hz fallback; estimate 100 BPM at 0.8 → 1.667 Hz; four taps 500 ms apart → manual 120 BPM → 2 Hz over the estimate; reset + confidence 0.3 → fallback; confidence exactly 0.5 counts; a bank fed the snapshot continues without a jump at 0.25 Hz after detection is lost); PerformanceControl 188 tests, 0 failures, 22 s wall (.build/scratch/mod-009/T05.log). The adaptor and the test were written together, so no separate red run (honest note).

## Phase 5: User Story 3 - safe, stored, live in the app (P2)

**Independent test**: `SceneLFOTests`, `LFOBindingAppTests.testSyncedLFOFollowsTapTempo`.

- [ ] MOD-009-T06 [P] [US3] Add to `Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift`: a synced entry (`"sync": {"beats": 4, "note": "kept"}`) decodes, encodes byte-identically, reads back `LFO.sync == 4 beats`; `SceneLFOEntry(lfo)` writes `sync` only when set; issues: `"sync": 2` → `invalidLFOSync` at `$.lfos[0].sync`; `{"beats": "x"}` → `invalidLFOSync` at `.sync.beats`; `{"beats": 0.333}` → `unknownLFOSync` at `.sync.beats`; all warnings, those oscillators stay live with `sync == nil`; repair report entries.
- [ ] MOD-009-T07 [US3] Implement `sync` in `Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift`, codes in `SceneIssue.swift`, mappings in `SceneRepair.swift`. Evidence: T06 and the whole SceneFormat suite (QA-004 meta-test) pass.
- [ ] MOD-009-T08 [US3] App: `NativeSpectrumHost.lfoTempoBPM` read per frame while a synced oscillator exists and passed to the bank (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`); `AppCoordinator+LFOs.swift` connects it to `tempo.snapshot.lfoTempoBPM`. Evidence: the app builds for testing with the type-check flags, no new warning over budget.
- [ ] MOD-009-T09 [US3] Add `testSyncedLFOFollowsTapTempo` to `Apps/projectM-iOS/Tests/LFOBindingAppTests.swift`: a `TempoCoordinator` with a 500 ms synthetic tap clock; 4 taps → 120 BPM manual; a 1-beat sine bound to the glow with `host.lfoTempoBPM` reading the coordinator; at 60 fps the effective glow equals the 2 Hz closed form within 1e-6 (peak at 0.125 s, equal values 0.5 s apart); after `reset()` (no estimate) it continues from the reached phase at the stored rate. Run on "MOD9 iPhone 17".

## Phase 6: Polish & Cross-Cutting

- [ ] MOD-009-T10 Whole ParameterGraph, PerformanceControl and SceneFormat suites on the host (each under 1 minute); Linux shape (no Apple-only API or stdio global in the changed package files); repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`), `check_privacy_manifest.py` on the built Debug app and `scripts/check_network_symbols`.
- [ ] MOD-009-T11 Docs: the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) gains the `sync` field and codes; spec Status Implemented; PosterBoard count again; delete the simulator and derived data.

## Dependencies

T01 → T02 → T03 → T04 → T05; T06 alongside T04 (red until T07); T07 → T08 → T09; T10, T11 last.

## Parallel examples

- T05 (PerformanceControl) and T06 (SceneFormat) after T03: different packages.

## Implementation strategy

MVP is User Story 1 (T01-T03): the sync length and the acceptance proof. Then continuity, priority and
safety (T04, T05), scenes and app (T06-T09), polish (T10, T11).
