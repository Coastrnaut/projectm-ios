# Tasks: AUD-011 Input Noise Gate

**Input**: Design documents in `specs/091-aud-011-input-noise-gate/` (spec.md, plan.md, research.md,
data-model.md, contracts/noise-gate.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s), each package suite under 1 minute, a UI test under 30 s; representative
cases only; timing is measured on the sample clock (frame counts), never the wall clock.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the feature's own iOS 27.2 simulator "AUD11 iPhone 17" (created for
this row, deleted afterwards). Inside descriptions "T03" is short for `AUD-011-T03`. A task is
ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>" appended.
Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] AUD-011-T01 Record the baseline: `swift test --package-path Packages/AudioCore` on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard report count. Evidence: counts recorded here.

## Phase 2: User Story 1 - quiet room, still visuals (P1, the roadmap acceptance)

**Goal**: the gate's law and the pass-through reader (contracts C1-C4). **Independent test**:
`NoiseGateTests` (AudioCore).

- [ ] AUD-011-T02 [US1] Write `Packages/AudioCore/Tests/AudioCoreTests/NoiseGateTests.swift`, reading in 512-frame buffers through `NoiseGateReader` over a fixture reader with an active control (enabled, microphone): (a) acceptance, silence: 1 s digital silence then 1 s of seeded uniform noise at −70 dBFS RMS gives every output sample exactly 0 (S1); (b) acceptance, opening: a 1 kHz tone at −80 dBFS for 0.5 s then −30 dBFS: the processor's gain is ≥ 10^(−1/20) no later than attackFrames + 512 frames after the step, and the gate was closed before it (S2), the measured frame count recorded; (c) hold and release: after the −30 dBFS tone stops, the gain stays 1 for fallFrames + holdFrames − 512 frames and is 0 by fallFrames + holdFrames + releaseFrames + 512, where fallFrames = 1,320 is the detector's fall from −30 to −56 dBFS (S3); the measured closing time recorded; (d) hysteresis: a tone at −53 dBFS (between −56 and −50) keeps a closed gate closed (all zeros) and, after a −30 dBFS burst opens it, keeps it open with zero transitions over 2 s (S4); (e) configured parameters: attack 20 ms and threshold −40 dBFS change the opening time and threshold accordingly; (f) off, and enabled with a non-microphone source: output bit-identical (`bitPattern`, NaN and > 1 included) (S5); (g) parameter clamping and NaN; (h) a new session generation and re-activation start closed; (i) composition: `NoiseGateReader(InputTrimReader(ChannelSelectionReader(tap)))` at +12 dB lifts a −58 dBFS tone over a −50 dBFS gate (the gate sees post-trim levels); (j) seam: projectM's ring stays bit-identical with selection (Side), trim (+24 dB) and a closed gate on the tap while the analysis copy is all zeros (S6). Record the red run.
- [ ] AUD-011-T03 [US1] Implement `Packages/AudioCore/Sources/AudioCore/NoiseGate.swift` (contracts C1-C4; R11: no allocation, lock or log in `read`; `powf` only on a threshold change). Evidence: T02 passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`; the full AudioCore suite passes with the T01 tests unchanged.

## Phase 3: User Story 3 - nothing outside the analysis changes (P1)

- [ ] AUD-011-T04 [US3] The seam proof is T02 (j); additionally confirm by reading the diff that no file under `Packages/CaptureKit`, the classifier or the ring changed. Evidence: `git diff --stat` against the T01 commit.

## Phase 4: User Story 2 - turn it on and set the threshold (P1)

- [ ] AUD-011-T05 [P] [US2] Write `Apps/projectM-iOS/Tests/NoiseGateSettingTests.swift`: defaults (off, −50) on empty defaults; stored values restored by a new store on the same defaults (relaunch persistence); non-Bool / NaN / out-of-range values validated; changes update the control; `text(for:)` ("−50 dBFS" with U+2212, "−20 dBFS"); `gated(nil)` is nil; `gated(reader)` mutes a quiet fixture only while the microphone flag is set. Own `UserDefaults(suiteName:)`; no main-actor mutation in setUp/tearDown. Record the red run.
- [ ] AUD-011-T06 [US2] Implement `Apps/projectM-iOS/Coordinators/NoiseGateSetting.swift` and add both keys to `ALLOWED_KEYS` in `scripts/run_device_tests.py` (R8). Evidence: T05 passes `{sim}`; `test_scripts.py` passes.
- [ ] AUD-011-T07 [US2] Wire `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (contract C5): own `noiseGate`, clear both keys on `-uitestResetNotice`, compose the gate after the trim in `trimmedAnalysisTap`, set the microphone flag in `start(_:)` and clear it in `stop()`. Evidence: projectM-iOSTests pass `{sim}`.
- [ ] AUD-011-T08 [US2] Add `Apps/projectM-iOS/Views/NoiseGateSection.swift` (contract C6, R7, R10) and pass `noiseGate` from `VisualizerView` into one new optional `SettingsView` parameter rendered after the channel section. Evidence: the app builds with no new warnings `{sim}`.
- [ ] AUD-011-T09 [US2] Write `Apps/projectM-iOS/UITests/NoiseGateUITests.swift` (one test < 30 s): open Settings, the toggle is off, the slider is disabled and reads "−50 dBFS"; turn the toggle on; the slider is enabled; adjust it and check the readout changed. Evidence: passes on "AUD11 iPhone 17" with InputTrimUITests and ChannelSelectionUITests `{sim}`.

## Phase 5: Polish & cross-cutting

- [ ] AUD-011-T10 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; count PosterBoard reports against T01; delete the "AUD11 iPhone 17" simulator. Evidence: all exit 0; counts recorded.
- [ ] AUD-011-T11 Update the spec's Status line (implemented, device task open). Evidence: `validate_docs.py` OK.
- [ ] AUD-011-T12 {device} On D1 with the Microphone source in a quiet room: gate on, the bars stay still; music opens it at once and it closes about 0.25 s after the music stops; plug or unplug headphones and take a phone call (interruption): the gate keeps working after resume; In-App Playback is unaffected. Evidence: a device note in `docs/test-reports/` (final roadmap device phase).

## Dependencies

T01 → T02 → T03 → T04 ; T03 → T05 → T06 → T07 → T08 → T09 → T10 → T11. T12 last (device phase).
US1 is the MVP (the roadmap acceptance); US3 proves the constraint; US2 is the user-facing control.

## Parallel opportunities

T05 can be written while T03 runs (different files).

## Analysis (speckit-analyze, 2026-11-13)

- F1 (fixed): S3 and US1 scenario 3 ignored the detector's 10 ms release: after a −30 dBFS tone
  stops, the envelope needs 1,320 frames to fall below −56 dBFS before the hold starts. S3, the
  scenario and T02 (c) now measure from that point.
- Coverage: R1, R2 → T02 (i, j), T07; R3 → T02 (f), T05, T07; R4, R5 → T02 (a-d); R6 → T02 (e, g);
  R7, R10 → T08, T09; R8 → T05, T06, T07; R9 → T02 (h), T05; R11 → T03 (diff). Every S has a test.
- Constitution: no conflict (plan's check). No ADR needed.
