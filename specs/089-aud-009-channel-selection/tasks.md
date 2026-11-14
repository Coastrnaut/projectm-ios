# Tasks: AUD-009 Channel Selection

**Input**: Design documents in `specs/089-aud-009-channel-selection/` (spec.md, plan.md, research.md,
data-model.md, contracts/channel-selection.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s), each package suite under 1 minute, a UI test under 30 s; representative
cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the feature's own iOS 27.2 simulator "AUD9 iPhone 17" (created for
this row, deleted afterwards). Inside descriptions "T03" is short for `AUD-009-T03`. A task is
ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>" appended.
Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] AUD-009-T01 Record the baseline: `swift test --package-path Packages/AudioCore` on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard report count. Evidence: counts recorded here.

## Phase 2: User Story 2 - a left-only fixture gives the expected values per mode (P1, the roadmap acceptance)

**Goal**: the modes' maths, the control and the pass-through reader (contracts C1-C3). **Independent
test**: `ChannelSelectionTests` (AudioCore), `ChannelSelectionBandTests` (VisualGenerators).

- [ ] AUD-009-T02 [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/ChannelSelectionTests.swift`: a left-only −20 dBFS 1 kHz sine (silence on R) read through `ChannelSelectionReader` in each mode has both output channels equal to s and RMS relative to L of Mix −6.02, Left 0, Mid −3.01, Side −3.01 dB (±0.01) and Right exactly 0; Left output is bit-identical to L; a right-only fixture mirrors it; an anti-phase fixture (R = −L) gives Mix and Mid exactly 0 and Side +3.01 dB; a mono fixture (L = R) gives Mix, Left, Right bit-identical to the mono signal, Mid +3.01 dB and Side exactly 0; Mix output is bit-identical to the input (`bitPattern`, including values above 1 and NaN); downstream (s + s)·0.5 equals s bit for bit in every mode; a mode change through the shared control reaches a live reader at its next read (R10); frame count and session generation are forwarded; the control maps unknown raw values to Mix; composition: `InputTrimReader(ChannelSelectionReader(...))` at +6.0206 dB in Left doubles L (±1e-4) and in Mid on a full-scale correlated tone stays within [−1, 1]. Record the red run.
- [ ] AUD-009-T03 [US2] Implement `Packages/AudioCore/Sources/AudioCore/ChannelSelection.swift` (contracts C1-C3: `AnalysisChannelMode`, `ChannelSelection.apply`, `ChannelSelectionControl` "lock-free; any thread", `ChannelSelectionReader`). Evidence: T02 passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`; the full AudioCore suite passes with the T01 tests unchanged.
- [ ] AUD-009-T04 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/ChannelSelectionBandTests.swift`: the left-only 1 kHz fixture through `SpectrumBandFeed` (32 bars) via `ChannelSelectionReader`: the tone band relative to Left moves by −6.02/80 (Mix), −3.01/80 (Mid, Side) within 0.005, Right lights no band above the floor; Mix bands equal the raw tap's; `WaveformTap` around the reader holds s (Left: the L samples, Right: zeros) within 1e-6. Evidence: passes on the host and in the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`).

## Phase 3: User Story 3 - nothing outside the analysis changes (P1)

**Goal**: prove the seam. **Independent test**: `ChannelSelectionSeamTests`.

- [ ] AUD-009-T05 [US3] In `ChannelSelectionTests.swift`, write the seam test (AUD-008-T05's pattern): a fresh `NormalizedPCMRing` with an analysis tap per run receives a stereo tone with different L and R; run A reads the tap raw, run B through `InputTrimReader(ChannelSelectionReader(tap, Side), +24 dB)`; projectM's ring frames are bit-identical to the written frames in both runs, and B's analysis copy differs. Evidence: passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`.

## Phase 4: User Story 1 - choose, persist and apply the mode (P1)

**Goal**: the setting, Settings control and wiring. **Independent test**: `ChannelSelectionSettingTests`,
`ChannelSelectionUITests`.

- [ ] AUD-009-T06 [P] [US1] Write `Apps/projectM-iOS/Tests/ChannelSelectionSettingTests.swift`: default Mix on empty defaults; stored `left` → Left and the control reads Left; unknown string and non-string values → Mix; setting Side stores `side` and updates the control; `title(for:)` and `spokenName(for:)` per the data model; `selected(nil)` is nil; `trimmed(selected(tap))` reads the selected signal through the trim. Own `UserDefaults(suiteName:)`; no main-actor mutation in setUp/tearDown. Record the red run.
- [ ] AUD-009-T07 [US1] Implement `Apps/projectM-iOS/Coordinators/ChannelSelectionSetting.swift` (key `settings.analysisChannel.mode`, String, default `mix`) and add the key to `ALLOWED_KEYS` in `scripts/run_device_tests.py` (AUD-009-R6). Evidence: T06 passes `{sim}`; `test_scripts.py` passes.
- [ ] AUD-009-T08 [US1] Wire `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`: own `channelSelection`, remove its key on `-uitestResetNotice`, and compose `trimmedAnalysisTap` = `inputTrim.trimmed(channelSelection.selected(manager.analysisTap))` (contract C4). Evidence: app unit tests (projectM-iOSTests) pass `{sim}`.
- [ ] AUD-009-T09 [US1] Add `Apps/projectM-iOS/Views/ChannelSelectionSection.swift` (segmented Picker "Analysis channel", id `analysisChannelPicker`, segments with spoken-name accessibility labels; readout id `analysisChannelValue`; footer per R7) and pass `channelSelection` from `VisualizerView` into one new optional `SettingsView` parameter rendered right after the input trim section. Evidence: the app builds with no new warnings `{sim}`.
- [ ] AUD-009-T10 [US1] Write `Apps/projectM-iOS/UITests/ChannelSelectionUITests.swift` (one test < 30 s): open Settings, check Mix is selected, choose Left, check the readout, relaunch, check Left is still selected. Evidence: passes on "AUD9 iPhone 17" with InputTrimUITests, SettingsUITests and NativeVisualUITests still passing `{sim}`.

## Phase 5: Polish & cross-cutting

- [ ] AUD-009-T11 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; count PosterBoard reports against T01; delete the "AUD9 iPhone 17" simulator. Evidence: all exit 0; counts recorded.
- [ ] AUD-009-T12 Update the spec's Status line (implemented, device task open). Evidence: `validate_docs.py` OK.
- [ ] AUD-009-T13 {device} On D1 (In-App Playback with a hard-panned track, then the microphone) choose Left, Right, Mid and Side and check the bars follow each definition while playback is unchanged; plug or unplug headphones and take a phone call (interruption): the mode stays and the analysis resumes. Evidence: a device note in `docs/test-reports/` (final roadmap device phase).

## Dependencies

T01 → T02 → T03 → (T04, T05) ; T03 → T06 → T07 → T08 → T09 → T10 → T11 → T12. T13 last (device
phase). US2 is the MVP (the roadmap acceptance); US3 proves the constraint; US1 is the user-facing
control.

## Parallel opportunities

T04 and T05 (different files) after T03; T06 can be written while T04/T05 run.
