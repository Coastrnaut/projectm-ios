# Tasks: AUD-013 Source Latency Calibration

**Input**: Design documents in `specs/095-aud-013-source-latency-calibration/` (spec.md, plan.md,
research.md, data-model.md, contracts/latency-delay.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s), each package suite under 1 minute, a UI test under 30 s; representative
cases only; time is the sample clock or an injected clock, never the wall clock.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the feature's own iOS 27.2 simulator "AUD13 iPhone 17" (created for
this row, deleted afterwards). Inside descriptions "T03" is short for `AUD-013-T03`. A task is
ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>" appended.
Logs go to `.build/scratch/`.

## Phase 1: Setup

- [ ] AUD-013-T01 Record the baseline: `swift test --package-path Packages/AudioCore` on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`, `swift test --package-path Packages/AnalysisFeatures`; PosterBoard report count. Evidence: counts recorded here.

## Phase 2: Foundational - the delay reader (blocks every story)

- [ ] AUD-013-T02 Write `Packages/AudioCore/Tests/AudioCoreTests/LatencyOffsetTests.swift` (contract C1-C3), reading 441-frame arrivals (10 ms) from a fixture ring whose samples carry their frame index: (a) steady-state delay: with target 0, 4,410 (100 ms) and 11,025 (250 ms) frames, every released sample's index equals the index arrived `target` frames later, minus target (sample-clock delay, exact); (b) clamping: `validatedMilliseconds` 400 → 250, −50 → 0, NaN → 0, 12.4 → 12; `frames(milliseconds: 100)` = 4,410; the control clamps 99,999 → 11,025 and −5 → 0 (S2); (c) pass-through: at 0 with an empty line the output is bit-identical (`bitPattern`, NaN included) to the wrapped reader and the frame count equals the wrapped count (S6); (d) slew up 0 → 250 ms mid-run: every arrival's released frames are within 75…125 % of the arrival (+1 frame) and the applied delay equals the target within 1.1 s of arrivals; slew down 250 → 0 the same (S4); (e) analysis flush: after a session-generation change the buffered frames are 0, the applied delay equals the target and no frame with an old-session index is released (S5); (f) renderer keep and trim: a generation change keeps the line; with a consumer reading 256 frames per 441 arrived, buffered − applied never exceeds 2,205 and the trimmed frames are counted; (g) overflow: arrivals beyond the line's capacity with no reads drop the oldest and count them; (h) estimate (S3 of US3): (0.160, 0.005) → 165 for In-App Playback and System/App Capture, 0.400 → 250, NaN / −1 → 0, Microphone → 0. Record the red run.
- [ ] AUD-013-T03 Implement `Packages/AudioCore/Sources/AudioCore/LatencyOffset.swift` (`LatencyOffset`, `LatencyOffsetControl`, `LatencyDelayReader`; R3, R5, R6, R7, R13: no allocation, lock or log in `read`). Evidence: T02 passes on the host and with `-DAUDIOCORE_NO_AVFAUDIO`; the full AudioCore suite passes with the T01 tests unchanged.

## Phase 3: User Story 1 - visuals in time with the headphones (P1, the roadmap acceptance)

**Goal**: known pulse and display-frame timestamps show the configured offset. **Independent
test**: `LatencyOffsetAcceptanceTests` (AnalysisFeatures).

- [ ] AUD-013-T04 [US1] Write `Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/LatencyOffsetAcceptanceTests.swift`: a `NormalizedPCMRing` with an analysis tap receives 512-frame buffers at their sample times (1 ms simulation steps) of a pulse train (20 ms bursts of a 200 Hz sine at 0.8, every 500 ms from 300 ms, 4 s); a `LatencyDelayReader(.analysis)` feeds an `AnalysisPipeline` with an injected clock, stepped every 10 ms; display frames at 60 Hz read the subscription's latest frame and record the first frame whose largest band reaches 0.5 after each pulse. For offsets 0, 100 and 250 ms: each pulse's display-frame shift relative to the 0 ms run equals the offset within ±28.3 ms, and the reacting frame's host-time shift likewise (S1); print a table (offset, mean shift, max error). Negative values are not supported (R4): −100 ms clamps to the 0 ms result. Record the red run.
- [ ] AUD-013-T05 [US1] Make T04 pass (fix only `LatencyOffset.swift` if needed). Evidence: T04 passes on the host and in the Linux shape of AnalysisFeatures; the measured table is copied into this task.
- [ ] AUD-013-T06 [P] [US1] Write `Apps/projectM-iOS/Tests/LatencyOffsetSettingTests.swift`: defaults 0 for all three modes; a new store on the same defaults restores stored values (relaunch persistence); NaN / non-number / out-of-range validated; setting one mode never changes the others (S3); `activeMode` selects which value is in the control (frames), nil → 0; an edit of the active mode updates the control at once, of another mode does not; `text(for:)` "0 ms", "180 ms"; `analysisDelayed(nil)` is nil. Own `UserDefaults(suiteName:)`; no main-actor mutation in setUp/tearDown. Record the red run.
- [ ] AUD-013-T07 [US1] Implement `Apps/projectM-iOS/Coordinators/LatencyOffsetSetting.swift` (data model; keys `settings.latencyOffset.microphone`, `.inAppPlayback`, `.systemAppCapture`) and add the three keys to `ALLOWED_KEYS` in `scripts/run_device_tests.py` (R11). Evidence: T06 passes `{sim}`; `test_scripts.py` passes.
- [ ] AUD-013-T08 [US1] Wire `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (contract C4): own `latencyOffset`; clear the three keys on `-uitestResetNotice`; outermost `analysisDelayed` in `trimmedAnalysisTap`; `rendererDelayed(manager.normalizedOutput)` in `prepareRenderer`; set `activeMode` in `start(_:)`, in `manager.onSessionMode`, and nil in `stop()`. Evidence: projectM-iOSTests pass `{sim}`.

## Phase 4: User Story 2 - change the delay while it plays (P1)

- [ ] AUD-013-T09 [US2] The bounded-change proof is T02 (d) on the reader both feeds use; confirm by reading the diff that the app writes only the control (no reader recreated on an edit). Evidence: T02 (d) passes; diff read.

## Phase 5: User Story 3 - estimate and reset (P2)

- [ ] AUD-013-T10 [P] [US3] Add `Packages/CaptureKit/Sources/CaptureKit/Route/SystemOutputLatency.swift` (iOS only: `outputLatency`, `ioBufferDuration` of the shared session) and `LatencyOffsetSetting.estimate(for:latency:)` taking an injected reading; a unit test in T06's file checks 0.160 + 0.005 → 165 ms stored for In-App Playback and 0 for Microphone with an injected reading. Evidence: T06 passes `{sim}`; CaptureKit builds for iOS.
- [ ] AUD-013-T11 [US3] Add `Apps/projectM-iOS/Views/LatencyOffsetSection.swift` (contract C5; R10, R12; strings in typed steps, no `+` chains with ternaries in modifiers) and pass `latencyOffset` from `VisualizerView` into one new optional `SettingsView` parameter rendered after the noise gate section. Evidence: the app builds with no new warnings `{sim}`.
- [ ] AUD-013-T12 [US3] Write `Apps/projectM-iOS/UITests/LatencyOffsetUITests.swift` (one test < 30 s): open Settings, the section shows "0 ms"; pick In-App Playback; adjust the slider and see the readout change; tap Reset and see "0 ms". Persistence is T06. Evidence: passes on "AUD13 iPhone 17" with NativeVisualUITests, SourceSwitchUITests and InputTrimUITests `{sim}`.

## Phase 6: User Story 4 - source switch (P2)

- [ ] AUD-013-T13 [US4] The flush/keep proof is T02 (e, f); T08's `onSessionMode` hook sets the new source's value when a switch begins. Evidence: T02 (e, f) pass; SourceSwitchUITests pass `{sim}` (T12).

## Phase 7: Polish

- [ ] AUD-013-T14 Write `docs/adr/0035-source-latency-delay.md` (next free number at commit time) and add it to `docs/adr/README.md`; run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; count PosterBoard reports; delete the simulator. Evidence: all exit 0; counts recorded.
- [ ] AUD-013-T15 {device} On D1: In-App Playback through the speaker, wired and Bluetooth headphones; record Estimate from Output per route; measure click-to-visual delay with a 240 fps camera at 0 ms and at the estimate (20 clicks, median); confirm the visuals line up within one display frame of the sound at the estimate; then route changes and an interruption with a non-zero delay.

## Dependencies

T01 → T02 → T03 → (T04 → T05) and (T06 → T07 → T08) → T09, T10 → T11 → T12 → T13 → T14. T15 last
(device phase). T06 and T10 can be written in parallel with T04.

## Implementation Strategy

MVP = Phases 1-3 (the reader, the acceptance and the wiring). Settings UI and the estimate follow;
the device measurement stays open until the roadmap's device phase.
