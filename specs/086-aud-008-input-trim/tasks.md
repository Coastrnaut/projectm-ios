# Tasks: AUD-008 Input Trim

**Input**: Design documents in `specs/086-aud-008-input-trim/` (spec.md, plan.md, research.md,
data-model.md, contracts/input-trim.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s), each package suite under 1 minute, a UI test under 30 s; representative
cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the feature's own iOS 27.2 simulator "AUD8 iPhone 17" (created for
this row, deleted afterwards). Inside descriptions "T03" is short for `AUD-008-T03`. A task is
ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>" appended.
Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] AUD-008-T01 Record the baseline: `swift test --package-path Packages/AudioCore` on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard report count. Evidence: counts recorded here.

## Phase 2: User Story 2 - test tone levels change predictably and saturate safely (P1, the roadmap acceptance)

**Goal**: the gain law, saturation, ramp and pass-through reader (contracts C1-C4). **Independent
test**: `InputTrimTests` (AudioCore), `InputTrimBandTests` (VisualGenerators).

- [ ] AUD-008-T02 [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/InputTrimTests.swift`: `clamped` (−20 → −12, 30 → 24, NaN → 0); `linearGain` (0 → 1 exactly, +6.0206 → 2 within 1e-4, −12 → 0.2512); `softClip` (identity for |v| ≤ 0.5, ±1 for |v| ≥ 1.25 and ±∞, NaN → 0, monotonic and within [−1, 1] over a sweep, odd); a −20 dBFS 1 kHz stereo sine read through `InputTrimReader` at −12, +6 and +12 dB has RMS = input RMS + trim within 0.05 dB; a full-scale sine at +24 dB stays finite and within [−1, 1] with peaks ≥ 0.99; NaN/∞ input samples come out finite; at 0 dB the output is bit-identical (`bitPattern`) to the input, including values above 1 and NaN; a target jump −12 → +24 read in varying buffer sizes (1…700 frames) never changes the gain by more than `maximumRampStep` (+1e-6) between frames and reaches the target exactly after 2,048 frames; a jump back to 0 dB ends bit-exact again; a session-generation change snaps the gain; the frame count and generation are forwarded; `InputTrimProcessor` has only scalar storage (`MemoryLayout` size ≤ 32 bytes). Record the red run.
- [ ] AUD-008-T03 [US2] Implement `Packages/AudioCore/Sources/AudioCore/InputTrim.swift` (contracts C1-C4: `InputTrim`, `InputTrimControl` "stores clamped; lock-free; any thread", `InputTrimProcessor`, `InputTrimReader`). Evidence: T02 passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`; the full AudioCore suite passes with the T01 tests unchanged.
- [ ] AUD-008-T04 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/InputTrimBandTests.swift`: a 1 kHz sine through `SpectrumBandFeed` (32 bars) via `InputTrimReader` at −12 and +6 dB moves the tone's band by trim/80 within 0.005 (band floor −80 dB) relative to 0 dB; at 0 dB the bands are identical to the raw tap's; `WaveformTap` wrapped around the trimmed reader holds the trimmed samples (+6 dB doubles the mid history within 1e-3). Evidence: passes on the host and in the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`).

## Phase 3: User Story 3 - the sinks stay untouched (P1)

**Goal**: prove the seam. **Independent test**: `InputTrimTests.testProjectMRingIsBitIdenticalWithTrimOnTheTap`.

- [ ] AUD-008-T05 [US3] In `InputTrimTests.swift`, write the seam test: a `NormalizedPCMRing` with an analysis tap receives the same tone twice (a fresh ring each run); run A reads the tap raw, run B reads it through `InputTrimReader` at +24 dB; the main ring's (projectM's) frames are bit-identical to the written frames and between A and B, and B's analysis copy differs (the trim did act). Evidence: passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`.

## Phase 4: User Story 1 - set, persist and reset the trim (P1)

**Goal**: the setting, Settings control and wiring. **Independent test**: `InputTrimSettingTests`,
`InputTrimUITests`.

- [ ] AUD-008-T06 [P] [US1] Write `Apps/projectM-iOS/Tests/InputTrimSettingTests.swift`: default 0 dB on empty defaults; stored 6 → 6 and the control reads 6; set 30 → 24, −40 → −12, 5.4 → 5, NaN → 0 (stored value equals the shown value); `reset()` → 0 and stored; `text(for:)` gives "+6 dB", "0 dB", "−12 dB" (U+2212). Uses its own `UserDefaults(suiteName:)`; no main-actor mutation in setUp/tearDown. Record the red run.
- [ ] AUD-008-T07 [US1] Implement `Apps/projectM-iOS/Coordinators/InputTrimSetting.swift` (key `settings.inputTrim.decibels`, "Double (whole dB, −12…24)", default 0) and add the key to `ALLOWED_KEYS` in `scripts/run_device_tests.py` (AUD-008-R6, FR-065 amendment). Evidence: T06 passes `{sim}`; `test_scripts.py` passes.
- [ ] AUD-008-T08 [US1] Wire `AppCoordinator`: own `inputTrim: InputTrimSetting`; add `trimmedAnalysisTap` (a new `InputTrimReader` around `manager.analysisTap` sharing `inputTrim.control`) and use it at every former `manager.analysisTap` consumer (five native-visual hosts and `tempo.runOwnAnalysis`) in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`. Evidence: `grep -n "manager.analysisTap" AppCoordinator.swift` shows only the helper; app unit tests (projectM-iOSTests) pass `{sim}`.
- [ ] AUD-008-T09 [US1] Add `Apps/projectM-iOS/Views/InputTrimSection.swift` (section "Audio Analysis": Slider −12…24 step 1, label "Input trim", value the text, id `inputTrimSlider`; readout id `inputTrimValue`; Button "Reset to 0 dB", id `inputTrimReset`; footer per AUD-008-R8; labels built by typed steps) and pass `inputTrim` from `VisualizerView` into one new optional `SettingsView` parameter rendered with one line. Evidence: the app builds with no new warnings `{sim}`.
- [ ] AUD-008-T10 [US1] Write `Apps/projectM-iOS/UITests/InputTrimUITests.swift` (one test < 30 s): open Settings, move the slider to +6 dB, check the readout, relaunch, check +6 dB, tap Reset, check 0 dB. Evidence: passes on "AUD8 iPhone 17" with SettingsUITests and NativeVisualUITests still passing `{sim}`.

## Phase 5: Polish & cross-cutting

- [ ] AUD-008-T11 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; count PosterBoard reports against T01; delete the "AUD8 iPhone 17" simulator. Evidence: all exit 0; counts recorded.
- [ ] AUD-008-T12 Update the spec's Status line and the roadmap row's gap status in `docs/FEATURE_ROADMAP_AUTONOMOUS.md` (implemented, device task open). Evidence: `validate_docs.py` OK.
- [ ] AUD-008-T13 {device} On D1 (microphone) and D3 (In-App Playback): set +12 dB and check the bars react more strongly while playback volume is unchanged; plug or unplug headphones and take a phone call (interruption): the trim stays and the analysis resumes. Evidence: a device note in `docs/test-reports/` (final roadmap device phase).

## Dependencies

T01 → T02 → T03 → (T04, T05) ; T03 → T06 → T07 → T08 → T09 → T10 → T11 → T12. T13 last (device
phase). US2 is the MVP (the roadmap acceptance); US3 proves the constraint; US1 is the user-facing
control.

## Parallel opportunities

T04 and T05 (different files) after T03; T06 can be written while T04/T05 run.
