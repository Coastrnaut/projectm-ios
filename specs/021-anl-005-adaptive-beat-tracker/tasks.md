# Tasks: ANL-005 Adaptive Beat Tracker

**Input**: `specs/021-anl-005-adaptive-beat-tracker/` (spec, plan, research, data-model,
contracts/beat-tracker.md, quickstart)

**Tests**: required (test-first; the spec's acceptance is test evidence). Owner rule 7
(2026-11-13): short tests that exist to produce evidence — each about 1–2 s on the Mac host
(Debug, at most 10 s), all new tests under 20 s, representative cases only, never assert speed.

**Format**: `- [ ] ANL-005-Tnn [P?] [Story?] Description`. Paths are relative to
`Packages/AnalysisFeatures/` unless they start at the repository root. No task needs a physical
device; none is tagged `{device}` (spec Assumptions: device measurements not needed).

## Phase 1: Setup

- [ ] ANL-005-T01 Confirm the baseline before any change: `swift test --package-path Packages/AnalysisFeatures` (with and without `-Xswiftc -DANALYSIS_NO_ACCELERATE`), `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`; record counts here. Logs in `.build/scratch/`.

## Phase 2: Foundational (tests first, then the types every story needs)

- [ ] ANL-005-T02 [P] Write `Tests/AnalysisFeaturesTests/BeatTrackerConfigurationTests.swift`: defaults (44,100 Hz, 60–200 BPM, preferred 120, window 6 s, tolerance 0.035 s, timeout 4 s) and `.standard`; each rule of data-model.md rejected with its named error at the edges and for NaN: "sampleRate finite, ≥ 8,000"; "minimumBPM ≥ 30", "maximumBPM ≤ 300, ≥ 1.5 × minimum"; "preferredBPM minimum…maximum"; "windowSeconds 2…16"; "timingToleranceSeconds 0.005…0.1"; "silenceTimeoutSeconds 1…16 and > 1.5 × 60 / minimum"; `BeatEvent.seconds` (ANL-005-R14).
- [ ] ANL-005-T03 [P] Write `Tests/AnalysisFeaturesTests/BeatTestSupport.swift`: helpers to feed exact onset lists to a tracker while advancing in fixed steps and record every estimate and beat event; the pipeline runner (mono samples → `SpectrumStream` with `.silence` lead-in, `clock: { 0 }` → `SpectralFluxOnsetDetector` → tracker via `process(_:onset:)`), returning per-frame estimates and beat events; the convergence measure (first frame end from which every frame has |BPM − true| ≤ 1.0 and confidence ≥ 0.8 to the end) and the beat matcher (each catalog onset after convergence takes the first unused beat within ±hop; misses, extras, largest |error|); a fixed-seed random onset generator (exponential gaps + 50 ms). No Accelerate import, no C stdio globals.
- [ ] ANL-005-T04 Record the red run: the T02/T03 (and T05) tests fail to compile against the missing symbols; log `.build/scratch/anl005-red.log`.
- [ ] ANL-005-T05 [P] Write `Tests/AnalysisFeaturesTests/BeatTrackerTests.swift` unit tests on exact onset lists (every backend in `TestSupport.backends`): (a) onsets every 22,050 samples → no estimate before 4 matched beats, then 120 BPM within 0.01, confidence 1 after 8 beats, `nextBeatSample` the next multiple; (b) 132 BPM at a fractional period (20,045.45) → 132 within 0.01; (c) a 60 BPM train → 60 (range edge) and a 240 BPM train → 120 (octave folded into the range); (d) one missing onset in a 120 train keeps 120 and confidence > 0.8; (e) out-of-order, duplicate and wrong-rate onsets are ignored and counted; backwards positions ignored and counted; (f) each beat reported once: advancing in 512-sample steps over a locked 120 train reports one event per beat with consecutive sequence numbers and sample indices equal to the predicted grid; a jump over three beats reports one event and counts two skipped; (g) silence after the train: confidence non-increasing, estimate nil at ≥ 4 s after the last onset and no beat events afterwards; (h) `reset()` clears estimate and position, keeps `beatCount`; (i) `process(frame, onset:)` equals `add` + `advance(to: index + size)` (ANL-005-R1 to R11, R15).

- [ ] ANL-005-T06 Implement `Sources/AnalysisFeatures/BeatTrackerConfiguration.swift`: `BeatTrackerConfiguration` (validated init, `.standard`, fixed constants), `BeatTrackerConfigurationError`, `BeatEstimate`, `BeatEvent` per data-model.md (ANL-005-R6, R10, R14). T02 passes.
- [ ] ANL-005-T07 Implement `Sources/AnalysisFeatures/AdaptiveBeatTracker.swift`: preallocated onset ring (64), recency scratch, histogram and preference table; comb histogram (ANL-005-R3), vDSP or portable preference multiply and first maximum (R12), hysteresis (R4), anchor search and three least-squares fits (R5), estimate and confidence factors (R6, R7), `advance` with timeout (R9) and beat reporting (R10), `process`, `reset`, counters (R11, R15); no allocation after `init` (R13); header comment with the boundary (R16). T05 passes on both builds.

## Phase 3: User Story 1 — a steady pulse train locks (P1)

**Independent test**: representative pulse runs converge within 4.0 s to ±1.0 BPM, confidence ≥ 0.8.

- [ ] ANL-005-T08 [US1] Write `Tests/AnalysisFeaturesTests/BeatAcceptanceTests.swift` pulse tests through the full pipeline (ANL-005-R17): `pulse-120` 44.1 kHz at 2048/512 and 4096/1024; `pulse-120-accent` 44.1 kHz at 2048/512 (tempo 120, never 30/60); `pulse-132` 48 kHz at 2048/512 and 44.1 kHz at 4096/1024. Assert convergence ≤ 4.0 s and stays converged to the end (ANL-005-S1); print one `ANL-005 pulse` line per run.

## Phase 4: User Story 2 — beat times on the sample clock (P1)

- [ ] ANL-005-T09 [US2] In the same pulse runs, match beat events after convergence to the catalog onset frames: 0 missed, 0 extra, every |beat − onset| ≤ hop (ANL-005-S2); assert each estimate's `nextBeatSample` ≥ its position; print the largest beat error per run.

## Phase 5: User Story 3 — tempo changes and gaps (P1)

- [ ] ANL-005-T10 [US3] `BeatAcceptanceTests`: `pulse-120` loop followed by the `pulse-132` loop (44.1 kHz, 2048/512): converges to 120 before the change and to 132 within 6.0 s after it (ANL-005-S3); print `ANL-005 change`.
- [ ] ANL-005-T11 [US3] `BeatAcceptanceTests`: `pulse-120` loop, 6 s of silence, `pulse-132` loop (44.1 kHz, 2048/512): during the silence confidence never rises and the estimate is gone within 4.0 s of the last onset event (≤ 4.0 s + one hop of the last pulse) with no beat events after that; the new tempo converges within 4.0 s of its start (ANL-005-S3); print `ANL-005 gap`.

## Phase 6: User Story 4 — noise and silence never claim a tempo (P1)

- [ ] ANL-005-T12 [US4] `BeatTrackerTests`: random onsets at 1, 4 and 16 per second (one fixed seed each, 30 s, advancing in 512-sample steps) never reach confidence 0.5 (`AdaptiveBeatTracker.highConfidence`); print the maxima (ANL-005-S4).
- [ ] ANL-005-T13 [US4] `BeatAcceptanceTests`: the AUD-016 `silence` loop and 10 s of −10 dBFS seeded white noise (44.1 kHz, 512/256) through the pipeline: silence never has an estimate; noise never reaches confidence 0.5 (ANL-005-S4); print `ANL-005 noise`.

## Phase 7: User Story 5 — same beats on every run and path (P2)

- [ ] ANL-005-T14 [US5] `BeatAcceptanceTests`: `pulse-132` 48 kHz 2048/512 tracked twice on the first backend: every estimate and beat event identical, doubles compared by bit pattern; the same onset list tracked with `.portable` and (when available) `.accelerated` gives identical estimates and events (ANL-005-S5, R12).

## Phase 8: Polish

- [ ] ANL-005-T15 Run the whole target twice at the end on the host, with and without `-Xswiftc -DANALYSIS_NO_ACCELERATE`; record test counts and each new test's duration (ANL-005-S6, S7).
- [ ] ANL-005-T16 `xcodebuild test -scheme AnalysisFeatures` on the iOS 27.2 simulator `62BA098B-4CBB-4DB6-91AD-51494936CF89` (`-test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO`, log grepped for `: error: `, `Executed N tests`, `** TEST`); count new `PosterBoard-*.ips` reports; shut the simulator down.
- [ ] ANL-005-T17 Read `AdaptiveBeatTracker.swift` for allocations in `add`/`advance`/`process` (ANL-005-S6, R13) and confirm nothing reaches projectM (R16: the package is not linked by the app, no projectM symbol); `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py` pass.

## Dependencies

T01 → T02, T03, T05 (parallel) → T04 → T06 → T07 → T08 → T09; T10, T11, T12, T13, T14 after T07
(independent of each other, same test file for T08–T11, T13, T14 so written in sequence) → T15 →
T16 → T17.

## Parallel example

T02, T03 and T05 are separate files and can be written together; T12 (unit file) and T13
(acceptance file) can be written together.

## Implementation strategy

MVP = Phase 2 + US1 (the roadmap acceptance). US2–US5 add the beat-time, adaptivity, noise and
determinism evidence; all are in this row's scope. No device step.
