# Tasks: ANL-001 Windowed FFT

**Input**: Design documents in `specs/014-anl-001-windowed-fft/` (spec.md, plan.md, research.md,
data-model.md, contracts/spectrum-analyzer.md, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded in the task that writes the tests, before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator "iPhone 18 Pro" (udid
`62BA098B-4CBB-4DB6-91AD-51494936CF89`).

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions, "T07" is short for `ANL-001-T07`. Every task needs macOS with Xcode
except where noted; Linux is covered by CI and by the `-DANALYSIS_NO_ACCELERATE` host build.

## Phase 1: Setup

- [ ] ANL-001-T01 Confirm the baseline before any change: `swift test` for `Packages/AudioCore` (also with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`), `Packages/CaptureKit`, `Packages/CaptureUI`, `Packages/Diagnostics`; `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`; record the counts here.
- [ ] ANL-001-T02 Create `Packages/AnalysisFeatures/Package.swift` (tools 6.0; platforms `.iOS("26.0"), .macOS(.v15)`; library `AnalysisFeatures`; target `AnalysisFeatures` depending on AudioCore (`../AudioCore`); executable `AnalysisBench`; test target `AnalysisFeaturesTests` depending on AnalysisFeatures and AudioCore), an empty source file and `.gitignore`-covered build output. Evidence: `swift build --package-path Packages/AnalysisFeatures` succeeds.

## Phase 2: Foundational (size, configuration, backends; blocks every story)

- [ ] ANL-001-T03 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/FFTSizeTests.swift`: `FFTSize.allCases` raw values exactly [512, 1024, 2048, 4096, 8192]; `FFTSize(samples:)` nil for 0, 1,000, 16,384, 256; `binCount` = N/2 + 1; `binWidth(sampleRate: 44_100)` for 512 = 86.1328125; `frequency(ofBin:)`; `nearestBin(toFrequency:sampleRate:)` equals `ReferenceToneCatalog.nearestBin` for every catalog sine, size and rate, and clamps to 0…N/2; `SpectrumConfiguration` default hop N/2, "hop 1 … size" (0 and N+1 throw `hopOutOfRange`), sample rate "finite, > 0" (0, −1, NaN, ∞ throw `invalidSampleRate`); `SpectrumMath.decibels` (0 → −120, 1 → 0, 0.25 → −12.0412 ±1e-3, NaN-free).
- [ ] ANL-001-T04 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectrumAnalyzerTests.swift` (run for every available backend): output length `binCount` for every size; silence → every bin exactly 0; a bin-centred sine of amplitude A ∈ {0.25, 1.0} at bin N/16 reads A ±1e-4 at that bin for every size; a constant 0.5 reads 0.5 ±1e-4 at bin 0; a Nyquist-rate alternating ±0.5 reads 0.5 ±1e-4 at bin N/2; sanitizing: inputs with NaN, ±∞, ±3.4e38, ±1e-40 (denormal), ±1e30 give all finite values ≥ 0 and NaN/∞/denormal samples behave as 0 (spectrum equals that of the input with those samples zeroed), values beyond ±64 equal the clamped input's spectrum; the array convenience equals the pointer API bit for bit; the periodic Hann window: `w[0] = 0`, `w[N/2] = 1`, symmetric `w[n] = w[N−n]`.
- [ ] ANL-001-T05 [P] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/TestSupport.swift`: a Double-precision reference DFT (periodic Hann, same normalization), a fixed-seed LCG noise generator, a bitwise array comparison helper, channel extraction from interleaved audio. Test target only; no Accelerate import.
- [ ] ANL-001-T06 Record the red run of T03-T05 (compile failure on missing symbols) in `.build/scratch/anl001-red-T03-T05.log`.
- [ ] ANL-001-T07 Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/FFTSize.swift`, `SpectrumConfiguration.swift`, `SpectrumMath.swift` per data-model.md. Evidence: T03 passes on the host.
- [ ] ANL-001-T08 Implement `HannWindow.swift` (tables for every size, Double → Float), `PortableRealFFT.swift` (packed N/2 complex radix-2 + real split, preallocated twiddles and scratch for 8,192) and `AcceleratedRealFFT.swift` (`#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`; one `vDSP_create_fftsetup(13)`, `vDSP_ctoz`, `vDSP_fft_zrip`, `vDSP_zvabs`, destroyed in `deinit`), and `SpectrumAnalyzer.swift` (shared sanitize-and-window pass, research ANL-001-D5; scaling `·4/N` interior, `·2/N` DC/Nyquist). Evidence: T04 passes on the host for both backends and with `-Xswiftc -DANALYSIS_NO_ACCELERATE`.

## Phase 3: User Story 1 - a known tone shows up in the right place (P1)

**Goal**: every catalog sine peaks at its documented bin. **Independent test**: `FixtureAcceptanceTests`.

- [ ] ANL-001-T09 [US1] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/FixtureAcceptanceTests.swift` (sines): for every sine fixture (`sine-1k`, `sine-100`, `sine-1500`, `sine-split` left and right) × 5 sizes × {44,100, 48,000}: the first window from frame 0 peaks at `ReferenceToneCatalog.nearestBin` (the catalog table), all values finite; every frame of the whole 10 s mono (or per-channel) loop at the default hop peaks within one bin of the documented bin, all finite; `sine-1500` at 48 kHz reads 0.25 ±1e-4 at its bin for every size; `sine-split` through the stream with `.left` and `.right` peaks at the 1 kHz and 440 Hz documented bins. Silence fixture: every bin of every frame is 0. Counts the combinations checked (expect 50 first-window checks) and asserts the count (ANL-001-S1, S2, S4). Run for every available backend.
- [ ] ANL-001-T10 [US1] Sweeps in `FixtureAcceptanceTests.swift`: for `sweep-log` and `sweep-linear` at both rates, every frame at every size is finite; at size 2,048 the frame centred at each catalog check time (1.25, 2.5, 5, 7.5 s) peaks within two bins of `instantaneousFrequency(atSeconds:)`'s nearest bin (ANL-001-R16).
- [ ] ANL-001-T11 [US1] Record the red run of T09-T10 if any symbol is missing (else note that T09-T10 compiled against T07-T08 and record their first result), then make them pass. Evidence: `swift test --package-path Packages/AnalysisFeatures --filter FixtureAcceptanceTests` passes on the host; the acceptance matrix (fixture × size × rate: expected bin, measured bin) is printed by the test log and copied into the report.

## Phase 4: User Story 2 - identical spectra on every run (P1)

**Goal**: bit-identical output (AUD-016-R22). **Independent test**: `DeterminismTests` in `FixtureAcceptanceTests.swift`.

- [ ] ANL-001-T12 [US2] Write the determinism tests: every sine and sweep fixture (whole loop, every size, both rates, mid of the stereo variant) analysed twice with fresh streams → identical frame indices and bitwise-identical magnitudes; a reused stream after `reset()` equals a fresh one bit for bit; a stream that first processed noise, then `reset()`, equals a fresh one (ANL-001-R10, S3). Run for every available backend.
- [ ] ANL-001-T13 [US2] Make T12 pass (no production change expected beyond T08/T16). Evidence: host run, also with `-DANALYSIS_NO_ACCELERATE`.

## Phase 5: User Story 3 - choose the resolution without glitches (P2)

**Goal**: streaming with selectable size and hop, real-time safe. **Independent test**: `SpectrumStreamTests`, `AnalysisTapTests`.

- [ ] ANL-001-T14 [P] [US3] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectrumStreamTests.swift`: no frame before N samples; frame indices 0, hop, 2·hop…; hop = N (no overlap) and hop = 1 work; the frame for index i equals `SpectrumAnalyzer` on samples i…i+N−1 bit for bit; `append` returns accepted frames and never exceeds `fifoCapacity` (16,384); mid/left/right extraction from interleaved stereo; mono append; size change 2,048 → 512 mid-stream: the next frame has 257 bins, starts at the previous frame's index + old hop and no buffered audio is discarded (ANL-001-R17); hop change keeps indices consistent; timestamps come from the injected clock (counter clock gives 1, 2, 3…); `pull(from:)` over a `NormalizedPCMRing` analysis tap yields the same frames as appending the same audio directly; `reset()` restarts indices at 0.
- [ ] ANL-001-T15 [P] [US3] Write `Packages/AudioCore/Tests/AudioCoreTests/AnalysisTapTests.swift`: default ring has no tap (`analysisTap == nil`, counters 0) and behaves as before; with a tap, every written frame appears in the tap in order and the main ring's `read` returns identical data whether the tap is read or not; tap overflow is drop-oldest with `analysisTapDroppedFrames` counted and the main ring unaffected; `discardBuffered()` empties both and keeps counters; `reset()` empties both and restarts the tap counter; the tap reader applies no freshness rule. Record the red run of T14-T15 (missing symbols).
- [ ] ANL-001-T16 [US3] Implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/SpectrumStream.swift` per the contract (FIFO 16,384, `append`, `nextFrame`, `magnitudes`, `copyMagnitudes`, `setConfiguration`, `reset`, `pull` with a preallocated 2,048-frame stereo scratch). Evidence: T14 passes on the host.
- [ ] ANL-001-T17 [US3] Implement the analysis tap in `Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift` (`analysisTapCapacityFrames` default 0, `analysisTapDefaultCapacityFrames = 22_050`, `analysisTap`, `analysisTapAvailableFrames`, `analysisTapDroppedFrames`; `write`, `discardBuffered`, `reset` cover the tap). `AudioAnalyzer` unchanged. Evidence: T15 passes; the full AudioCore suite passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`.
- [ ] ANL-001-T18 [US3] Real-time review of the per-frame paths (`magnitudes(of:size:into:)`, `append`, `nextFrame`, `pull`, `setConfiguration`, tap `write`): no Array, String, class or escaping-closure creation, no lock, no I/O, no logging (ANL-001-R13). Evidence: the diff read and the Instruments Allocations trace of the bench (T21).

## Phase 6: User Story 4 - same results everywhere CI runs (P2)

**Goal**: backends agree and match the reference DFT. **Independent test**: `BackendAgreementTests`, `ReferenceDFTTests`.

- [ ] ANL-001-T19 [P] [US4] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BackendAgreementTests.swift` (skipped with a message when Accelerate is compiled out): for noise, every catalog sine and sweep (first windows and a hop sequence), all 5 sizes: `|accelerated − portable| ≤ 1e-5·peak + 1e-6` per bin, same peak bin for tonal input; record the largest observed relative difference in the log. And `ReferenceDFTTests.swift` (runs on every path): for N = 512 and 1,024, noise and the sine fixtures, each available backend within `1e-5·peak + 1e-6` of the Double reference DFT (ANL-001-R11, S5).
- [ ] ANL-001-T20 [US4] Make T19 pass. Evidence: host run (both backends) and `-DANALYSIS_NO_ACCELERATE` run (portable vs DFT; agreement test skipped).

## Phase 7: Polish and cross-cutting

- [ ] ANL-001-T21 Write `Packages/AnalysisFeatures/Sources/AnalysisBench/main.swift`: for each size and backend, 2,000 frames of noise at the default hop after a warm-up; prints ns per frame and percent of real time at 44.1 kHz. Run `swift run -c release --package-path Packages/AnalysisFeatures AnalysisBench` on the host and record the numbers here; run it under `xcrun xctrace record --template Allocations` and record whether allocations occur in the timed loop (ANL-001-S6, S7). Not asserted by any test.
- [ ] ANL-001-T22 Add `AnalysisFeatures` to every package loop in `.github/workflows/ios-ci.yml` (Linux host tests, macOS host tests, generic iOS compile, the iOS 26 simulator loop, the iOS 27.2 simulator loop). Evidence: `git diff` shows exactly those five loops changed; `python3 scripts/test_scripts.py` passes.
- [ ] ANL-001-T23 {sim} Run `xcodebuild test -scheme AnalysisFeatures` and `-scheme AudioCore` on the iOS 27.2 simulator (udid `62BA098B-…`) with `-test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO`, logs in `.build/scratch/`; grep `: error: `, `Executed N tests`, `** TEST`. Shut the simulator down afterwards.
- [ ] ANL-001-T24 Run the dependents of AudioCore on the host (CaptureKit, CaptureUI, Diagnostics) and confirm counts equal T01's plus nothing removed (ANL-001-S8).
- [ ] ANL-001-T25 `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` pass.
- [ ] ANL-001-T26 Run every suite touched twice at the end (AnalysisFeatures host, host `-DANALYSIS_NO_ACCELERATE`, simulator; AudioCore host, `-DAUDIOCORE_NO_AVFAUDIO`, simulator; CaptureKit, CaptureUI, Diagnostics host) and record the counts.
- [ ] ANL-001-T27 {device} (open: final device phase, only if a later row needs it) Run `AnalysisBench` logic on D1 in Release to record the per-frame cost on the reference device. Not required for this row's acceptance (spec Assumptions).

## Dependencies

- T01 → T02 → T03–T05 (tests, red: T06) → T07 → T08 → US1 (T09–T11) and US2 (T12–T13) → US3
  (T14–T18) → US4 (T19–T20) → T21–T26. T27 waits for the roadmap's final device phase.
- US1 (whole-loop frames, `sine-split` channels) and US2 (whole loops) run through `SpectrumStream`
  from US3's T16, so T16 is implemented before T11 and T13 are ticked; the tests are still written
  first.

## Parallel opportunities

- T03, T04, T05 (different test files). T14 and T15 (different packages). T19 with T21.

## Implementation strategy

MVP = Phases 1–3 (the roadmap acceptance: sine fixtures peak at the documented bin, finite values).
Then determinism (the AUD-016 hand-off), streaming and the tap, backend agreement, CI wiring.
