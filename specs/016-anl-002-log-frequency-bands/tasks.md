# Tasks: ANL-002 Log-frequency Bands

**Input**: Design documents in `specs/016-anl-002-log-frequency-bands/` (spec.md, plan.md, research.md,
data-model.md, contracts/band-reducer.md, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator "iPhone 18 Pro" (udid
`62BA098B-4CBB-4DB6-91AD-51494936CF89`).

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions, "T07" is short for `ANL-002-T07`. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] ANL-002-T01 Confirm the baseline before any change: `swift test --package-path Packages/AnalysisFeatures` (with and without `-Xswiftc -DANALYSIS_NO_ACCELERATE`); `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`; record the counts here.

## Phase 2: Foundational (layout, reducer, normalizers; blocks every story)

- [ ] ANL-002-T02 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandTestSupport.swift`: an independent oracle that does not call `BandLayout` — edges `20 · (upper/20)^(i/B)` with upper = min(20,000, R/2), bin intervals per research ANL-002-D2 (bin 1 from 0 Hz, Nyquist bin to R/2, DC none), overlap weights, owner band of a bin (largest weight, lower band on a tie); the multi-tone builder (AUD-016 `ToneGenerator` mono sines 100, 440, 1,000, 1,500, 5,000, 12,000 Hz, amplitude 0.15 each, summed in that order in Float). No Accelerate import.
- [ ] ANL-002-T03 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandLayoutTests.swift`: `BandCount.allCases` raw values exactly [16, 32, 64, 128] and `BandCount(rawValue: 24) == nil`; for all 4 counts × 5 sizes × {44,100, 48,000}: `edges.count == B + 1`, `edges[0] == 20`, `edges[B] == 20,000`, strictly increasing, equal ratio within 1e-9 relative, each edge equals the oracle within 1e-9 relative; every band has `binRange` non-empty and `widthInBins > 0` (no empty band, ANL-002-R6, S4); weights in (0, 1] and equal to the oracle within 1e-6; Σ over bands of each bin's weight ≤ 1 + 1e-6; `ownerBand(ofBin:)` equals the oracle for every bin; `band(containingFrequency:)` for 19.9 (nil), 20 (0), 19,999 (B−1), 20,000 (nil); `centerFrequency` is the geometric mean of the edges. Rate 8,000: upper edge 4,000 and the Nyquist bin weight ≤ 0.5. Errors: rates 7,999, 0, −1, NaN, +∞ throw `invalidSampleRate` (from `BandLayout` and `BandReducer`).
- [ ] ANL-002-T04 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandReducerTests.swift` (for every backend in `TestSupport.backends`): all-zero spectrum → every band `bitPattern == 0` for every count, size and rate (ANL-002-R7); a spectrum with NaN, ±∞, negative values, 1e30 → all outputs finite and ≥ 0, NaN/∞/negative behave as 0; a single bin of value 1 inside a wide band reads `sqrt(1/1.5)` ±1e-6; the analyzer's spectrum of a bin-centred sine of amplitude A ∈ {0.25, 1.0} at the bin nearest the geometric centre of band 9 of 16 at 8,192 points (about 1.2 kHz; the band is about 98 bins wide) reads A within 1e-3 relative, and an off-centre one (that bin + 0.37) reads A within 1e-3 relative; a constant spectrum m ≡ c (bins 1…N/2) reads `c·sqrt(max(W_b, 1)/1.5)` within 1e-5 relative in every band (so sub-bin bands read `c/sqrt(1.5)`); the array convenience equals the pointer API bit for bit; switching size and count between calls on one reducer equals fresh reducers bit for bit; `reduce` with `layout(bandCount:size:)` matches a reducer built for that rate; `BandMath`: `normalizedLinear(0) == 0`, `(0.5) == 0.5`, `(2) == 1`, reference 0.5 doubles, invalid reference → 0; `normalizedDecibels(0) == 0`, `(1) == 1`, `(0.1) == 0.75` ±1e-6 at −80 dB, `(1e-5)` (−100 dB) → 0, `(2)` → 1, NaN → 0; `normalize(_:count:scale:)` equals the scalar functions element by element.
- [ ] ANL-002-T05 Record the red run of T02-T04 (compile failure on missing `BandLayout`/`BandReducer`/`BandMath`) in `.build/scratch/anl002-red-T02-T04.log`.
- [ ] ANL-002-T06 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/BandLayout.swift` per data-model.md (`BandCount`, `BandLayoutError`, `BandLayout`: edges in Double, "edges[B] == upperEdge exactly", intervals and weights per research ANL-002-D2, scale `1 / (1.5 · min(1, W_b))`, inspection queries). Evidence: BandLayoutTests pass on the host.
- [ ] ANL-002-T07 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/BandReducer.swift` (20 layouts and a 4,097-Float power scratch at init; sanitize-and-square pass "non-finite or ≤ 0 → 0, clamp to 1e15"; per band `vDSP_dotpr` under `#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE` or an ordered Float loop; `× scale`, `sqrt`, finite guard) and `BandMath.swift` (`BandScale`, `BandMath`). Evidence: BandReducerTests pass on the host for both backends and with `-DANALYSIS_NO_ACCELERATE`.

## Phase 3: User Story 1 - several known tones light the expected bands (P1)

**Goal**: the roadmap acceptance's first half. **Independent test**: `BandAcceptanceTests.testMultiToneFixturePopulatesExpectedBands`.

- [ ] ANL-002-T08 [US1] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandAcceptanceTests.swift` (multi-tone): for every backend × 6 tones × 4 counts × 5 sizes × 2 rates (240 combinations per backend): the first window from frame 0 through `SpectrumAnalyzer`, reduced; expected band = oracle owner of `ReferenceToneCatalog.nearestBin`; (a) value ≥ 0.35·A; (b) strict combinations (`[f − 2.5Δ, f + 2.5Δ]` inside the expected band, no other tone's lobe touching it) read A within 2 % and are the largest band touching the lobe; (c) every band not touching any tone's `[f − 4Δ, f + 4Δ]` reads ≤ 0.02·A; all outputs finite. Print one `ANL-002 matrix:` line per combination (tone, count, size, rate, expected, measured = largest band touching the lobe, value/A, strict) for the first backend, the number of strict combinations, and the largest far-band ratio; assert the combination count is 240 (ANL-002-R14, S1, S2).
- [ ] ANL-002-T09 [US1] Record the T08 first result (compiled against T06-T07, or red if a symbol is missing) and make it pass; if a threshold fails, investigate the physics before changing it and record any change in research ANL-002-D7. Evidence: `swift test --filter BandAcceptanceTests` passes on the host; the matrix is saved to `.build/scratch/anl002-matrix.txt` and summarized in the final report.

## Phase 4: User Story 2 - zero stays zero (P1)

**Goal**: the acceptance's second half. **Independent test**: `BandAcceptanceTests.testSilenceStaysExactlyZero`.

- [ ] ANL-002-T10 [US2] In `BandAcceptanceTests.swift`: the AUD-016 `silence` fixture (stereo loop, 10 s) through `SpectrumStream` at each size and rate (default hop), every frame reduced to all 4 counts: every value `bitPattern == 0`; also normalized with both `BandScale`s: exactly 0 (ANL-002-S3).
- [ ] ANL-002-T11 [US2] Make T10 pass (no production change expected). Evidence: host run, also with `-DANALYSIS_NO_ACCELERATE`.

## Phase 5: User Story 3 - choose a band count and FFT size freely (P1)

**Goal**: all 16/32/64/128 × 5 sizes × rates usable and switchable. **Independent test**: `BandLayoutTests`, `BandReducerTests` switching cases, the stream composition test.

- [ ] ANL-002-T12 [US3] In `BandAcceptanceTests.swift`: a `SpectrumStream` over the multi-tone loop that switches size 2,048 → 512 → 8,192 and the band count 16 → 128 → 32 between frames on one reducer: each frame's bands equal a fresh reducer's reduction of the same magnitudes bit for bit and have the configured length (ANL-002-R9).
- [ ] ANL-002-T13 [US3] Real-time review of `reduce(magnitudes:size:bandCount:into:)` and `BandMath.normalize`: no Array, String, class or escaping-closure creation, no lock, I/O or log; `BandReducer` not `Sendable`. Evidence: the diff read plus a malloc-stack trace of the bench's reduction loop (as ANL-001-T18).

## Phase 6: User Story 4 - same bands on every run and every CI path (P2)

**Goal**: AUD-016-R22 for bands; backend agreement. **Independent test**: `BandAcceptanceTests.testRepeatedRunsAreBitIdentical`, `testBackendsAgree`.

- [ ] ANL-002-T14 [US4] In `BandAcceptanceTests.swift`: the multi-tone loop and the catalog `sweep-log` and `sweep-linear` fixtures (mid) through a fresh stream and reducer twice, at sizes 512 and 8,192, both rates, all 4 counts per frame: identical bit patterns; with vDSP available, the same magnitudes reduced by both backends agree within `1e-5·max + 1e-7` per band on every frame (largest relative difference printed) (ANL-002-R11, R12, S5).
- [ ] ANL-002-T15 [US4] Make T14 pass. Evidence: host (both backends), `-DANALYSIS_NO_ACCELERATE` (agreement test skipped with a message).

## Phase 7: Polish and cross-cutting

- [ ] ANL-002-T16 [P] Add a band section to `Packages/AnalysisFeatures/Bench/Sources/AnalysisBench/main.swift`: ns per `reduce` for each count at 2,048 and 8,192, both backends; run `swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench` and record the numbers here (ANL-002-S6; reported, not asserted).
- [ ] ANL-002-T17 {sim} Run `xcodebuild test -scheme AnalysisFeatures` from `Packages/AnalysisFeatures` on the iOS 27.2 simulator (udid `62BA098B-…`) with `-test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO`, log in `.build/scratch/`; grep `: error: `, `Executed N tests`, `** TEST`; count new `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` files; shut the simulator down afterwards.
- [ ] ANL-002-T18 `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py` pass; the grep over `project.yml`, `RendererLab.yml`, `Apps`, `Packages/ProjectMBridge`, `Packages/Rendering`, `Packages/ANGLERendering` finds no `AnalysisFeatures` (ANL-002-R13); no third-party code added; CaptureKit and CaptureUI untouched (`git diff --stat`).
- [ ] ANL-002-T19 Run the AnalysisFeatures suites twice at the end (host, host `-DANALYSIS_NO_ACCELERATE`) and record counts and the acceptance suite's runtime; ANL-001's tests still pass unchanged (ANL-002-S7).
- [ ] ANL-002-T20 {device} (open: final device phase, only if a later row needs it) Measure the reduction cost on D1 in Release. Not required for this row's acceptance (spec Assumptions).

## Dependencies

- T01 → T02–T04 (tests, red: T05) → T06 → T07 → US1 (T08–T09), US2 (T10–T11), US3 (T12–T13),
  US4 (T14–T15) → T16–T19. T20 waits for the roadmap's final device phase.
- The acceptance tests (T08, T10, T12, T14) use ANL-001's `SpectrumAnalyzer`/`SpectrumStream`
  (integrated) and T06–T07.

## Parallel opportunities

- T02, T03, T04 (different files). T16 alongside T08–T15. US1–US4 test sections share one file, so
  they are written in sequence.

## Implementation strategy

MVP = Phases 1–4 (the roadmap acceptance: multi-tone bands and zero stays zero). Then switching and
the real-time review, determinism and backend agreement, the bench and the gates.

## Analysis (speckit-analyze, 2026-11-13)

Consistency pass over spec.md, plan.md, tasks.md, research.md, data-model.md and the contract.
Every requirement ANL-002-R1…R14 and success criterion S1…S7 maps to at least one task (R1–R3, R6,
R10: T03, T06; R4, R5, R7, R8: T04, T07; R9: T07, T12, T13; R11, R12: T14; R13: T18; R14: T08;
S1, S2: T08; S3: T10; S4: T03, T04; S5: T14; S6: T13, T16; S7: T19). No constitution conflict;
licensing: no third-party code or dependency (IX); privacy: nothing stored, sent or recorded;
cross-feature: consumes only ANL-001's public API, changes no ANL-001 file, CaptureKit/CaptureUI
and AudioCore untouched, catalog version unchanged (AUD-016). Fixes applied: T04's in-band sine
check names its band and tolerance, and its constant-spectrum check states the exact expected
value `c·sqrt(max(W_b, 1)/1.5)` (two ambiguities). No duplication or critical issue found.
