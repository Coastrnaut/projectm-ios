# Tasks: ANL-003 Spectral Smoothing

**Input**: Design documents in `specs/085-anl-003-spectral-smoothing/` (spec.md, plan.md,
research.md, data-model.md, contracts/band-smoother.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure)
is recorded before the production change. Budgets (owner rule 7): a unit test about 1-2 s (≤ 10 s),
each package suite under 1 minute, a UI test under 30 s; representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel.
`{sim}` = needs the row's own iOS 27.2 simulator "ANL3 iPhone 17" (created for this row, deleted
afterwards). Inside descriptions "T03" is short for `ANL-003-T03`. A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] ANL-003-T01 Record the baseline: `swift test` for `Packages/AnalysisFeatures` and `Packages/VisualGenerators` on the host; the five scripts (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`); PosterBoard report count. — Verified 2026-11-13: at 3eae790, AnalysisFeatures 106 tests (54.2 s, pre-existing suite time), VisualGenerators 127 tests (26.4 s), 0 failures; check_compliance, validate_docs, check_motion_policy, check_permission_catalog OK; test_scripts.py 147 tests OK (1 skipped); PosterBoard reports 32 (.build/scratch/anl003-T01-*.log).

## Phase 2: User Story 2 - step reaches 90 % by attack, decays by release (P1, roadmap acceptance)

**Independent test**: `BandSmootherTests`, `BandSmoothingPipelineTests`.

- [X] ANL-003-T02 [US2] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/BandSmootherTests.swift`: step up (attack 25 ms, 100 ms) and step down (release 100 ms, 500 ms) at 60 fps, 120 fps and a seeded jittery 8-25 ms interval, asserting τ ≤ first 90 % crossing < τ + that frame's interval; two bands stepping in opposite directions; instant times copy the input exactly; snap on first update, `reset()`, count change and generation change; non-finite input holds; invalid Δt; times clamp; times changed mid-run do not snap; storage address unchanged over 1,000 updates (ANL-003-S1 to S3). — Verified 2026-11-13: 10 tests written before the smoother; red run `cannot find type 'SmoothingTimes' in scope` (.build/scratch/anl003-red-T02.log).
- [X] ANL-003-T03 [US2] Record the T02 red run; implement `Packages/AnalysisFeatures/Sources/AnalysisFeatures/BandSmoother.swift` (contract C1). Evidence: T02 passes on the host and with `-Xswiftc -DANALYSIS_NO_ACCELERATE`. — Verified 2026-11-13: BandSmootherTests 10 pass on the host (0.014 s) and in the Linux shape (0.013 s). 90 % crossings: attack 25 ms → 25.00 (120 fps), 33.33 (60 fps), 46.02 ms (jitter; that frame 21.5 ms); attack 100 ms → 100.00, 100.00, 115.61 ms; release 100 ms → 100.00, 100.00, 115.61 ms; release 500 ms → 500.00, 500.00, 506.89 ms; all within one frame after τ (.build/scratch/anl003-T03-*.log).
- [X] ANL-003-T04 [US2] Add `session` to `LiveBandFrameInfo` in `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`, and write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/BandSmoothingPipelineTests.swift`: a 1 kHz tone (amplitude 0.5) on for 1 s then off for 1 s, fed through `SpectrumBandFeed` in 735-frame chunks (60 fps), smoothed with attack 100 ms / release 500 ms; the bounds of spec User Story 2 scenario 5 hold, taken from the raw band's own crossings (leaves zero, reaches steady, starts to fall, reaches zero) (ANL-003-S4). Evidence: passes on the host and in the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), whole package suites green. — Verified 2026-11-13: BandSmoothingPipelineTests 2 pass on the host (0.24 s) and in the Linux shape. Band 36 (1 kHz, 64 bands), raw steady 0.9236; the raw band ramps up and down over 66.7 ms (4 frames); smoothed 90 % crossing 116.7 ms after the raw band's last zero (bounds 100 ms … 66.7 + 100 + 16.7 ms), 10 % crossing 550.0 ms after its last steady frame (bounds 500 ms … 66.7 + 500 + 16.7 ms); Instant is bit-identical to the raw bands. Whole suites: VisualGenerators 129 on the host (26.7 s) and 104 in the Linux shape (17.4 s); AnalysisFeatures 116 on the host (47.2 s) and 116 in the Linux shape (81.2 s, 1 skipped; the pre-existing suite dominates, the 10 new tests take 0.01 s); 0 failures (.build/scratch/anl003-T04-*.log).

## Phase 3: User Story 1 - Attack and Release settings (P1)

**Independent test**: `SpectralSmoothingAppTests`, `SpectralSmoothingUITests`.

- [ ] ANL-003-T05 [US1] Write `Apps/projectM-iOS/Tests/SpectralSmoothingAppTests.swift` (defaults 0, choices, persistence, invalid stored → 0, `spectrumSmoothing` mapping to seconds) and add `settings.spectrum.attack` / `settings.spectrum.release` to `ALLOWED_KEYS` in `scripts/run_device_tests.py`.
- [ ] ANL-003-T06 [US1] Implement the settings in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; the host wiring in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift` (smoother after `readLatest`, real display-link interval, frame session, raw bands to modulation, reset on resume and bar-count change); `AppCoordinator.swift` (apply at creation and in `visualSettingsChanged`); `SettingsView.swift` (Attack and Release segmented pickers for the two spectra, identifiers `smoothingAttackPicker` and `smoothingReleasePicker`); `VisualizerView.swift` (`onChange`). Evidence: T05 passes `{sim}`; `test_scripts.py` passes.
- [ ] ANL-003-T07 [US1] Write `Apps/projectM-iOS/UITests/SpectralSmoothingUITests.swift`: choose Circular Spectrum, Attack 50 ms, Release 500 ms, relaunch, both restored; with Oscilloscope chosen neither row exists (ANL-003-S5). Evidence: passes in < 30 s `{sim}`, with `NativeVisualUITests` and `OscilloscopeUITests` unchanged and green; the rows carry the labels "Attack" and "Release" (ANL-003-R9).

## Phase 4: Polish

- [ ] ANL-003-T08 Amend VIS-001-R9's note in `specs/019-vis-001-circular-spectrum/spec.md` (smoothing is ANL-003's setting) and update `SpectrumBandFeed.swift`'s header comment; run the five scripts; count PosterBoard reports; delete the row's simulator; mark the spec Implemented.

## Dependencies

T01 → T02 → T03 → T04; T03 → T05 → T06 → T07 → T08. T04 and T05 can run in parallel after T03.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: every requirement maps to a task (R1-R5, R7, R10 → T02-T03; R2 → T06 raw bands to
modulation; R6, R9 → T05-T07; R8 → T06, T08). Findings applied: (1) the end-to-end bound in spec
User Story 2 scenario 5 now takes its bounds from the raw band's own crossings, because the raw band
ramps over the analysis window and is not a clean step; T04 matches it. (2) T07 checks the rows'
labels (R9). No constitution conflict, no duplicate or orphan task.
