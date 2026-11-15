# Tasks: MIDI-010 MIDI Clock Receive

**Input**: `specs/273-midi-010-midi-clock-receive/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-010-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-010-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI10 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; `Build` symlink present; simulator D37F1949 "MIDI10 iPhone 17" (iOS 27.2); PosterBoard reports 30 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-010-T02 [P] `MIDIClockLane` (256 preallocated events, atomic indices, `isEnabled`, drop newest with `dropped`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIClockLane.swift` and the one hook in `MIDIEventRing.push`/`discardAll` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIEventRing.swift` (research MIDI-010-D2; contract C1) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 284 tests, 0 failures, 15.1 s (MIDIClockTests 13/13) `testTheRingCopiesClockEventsToTheLaneInOrderOnlyWhileEnabled`, `testTheLaneDropsTheNewestWhenFull`
- [X] MIDI-010-T03 [P] `TempoOrigin.midiClock`, `TempoSource.updateMIDIClock(_:)` (clock first, then manual, then estimate) and `TempoReadout.midiClock(bpm:)` in `Packages/PerformanceControl/Sources/PerformanceControl/TempoSnapshot.swift`, `TempoSource.swift`, `TempoConfidenceIndicator.swift` (research D7; contract C3) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 284 tests, 0 failures, 15.1 s (MIDIClockTests 13/13) `testALockedClockOutranksTapAndFallsBackToIt`

## Phase 3: User Story 1 - The show follows the clock's tempo (P1) — MVP

**Independent test**: exact 24-PPQN pulses read the BPM within ±0.1; the app snapshot follows a fake clock with the toggle on only.

- [X] MIDI-010-T04 [US1] `MIDIClockTracker`, `MIDIClockRules` (24 PPQN, window 96, lock 24, "20–300 BPM" with 0.1 allowance, timeout 500 ms, change 2 %, outlier < 0.6 period, gap ≥ 4.5 periods restarts, 6 outliers restart), `MIDIClockStatus`, `MIDIClockTempo` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIClockTracker.swift` (research D3–D6; contract C2) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 284 tests, 0 failures, 15.1 s (MIDIClockTests 13/13)
- [X] MIDI-010-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIClockTests.swift`: exact 60/90/120/174.5/300 BPM within ±0.1 (S1), seeded ±1 ms jitter at 120 within ±0.5 (S2), 120 → 140 within 4 beats, dropped and early pulses (S3), out-of-range ignored, lane order and hook, UMP words 0x10F8xxxx/FA/FB/FC/F2 decode, tempo-source priority and fallback — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 284 tests, 0 failures, 15.1 s (MIDIClockTests 13/13) (S1 `testExactPulsesReadTheirTempoWithinATenthOfABPM`, S2 jitter, S3 step and dropped/early pulses, range, lane, UMP words, priority)
- [ ] MIDI-010-T06 [US1] `MIDIClockCoordinator` (key `settings.midi.followClock`, client "midiClock" while following, lane drain per batch, 100 ms tick task cancelled when following is off, status texts) in `Apps/projectM-iOS/Coordinators/MIDIClockCoordinator.swift`; `TempoCoordinator.updateMIDIClock(_:)`, tap notice and readout texts in `Apps/projectM-iOS/Coordinators/TempoCoordinator.swift`; readout switches in `Apps/projectM-iOS/Views/SceneHUD.swift`, `Apps/projectM-iOS/Coordinators/SlideshowCoordinator.swift`, `Apps/projectM-iOS/Coordinators/ShowBeatGridCoordinator.swift`; creation in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] MIDI-010-T07 [US1] App tests `Apps/projectM-iOS/Tests/MIDIClockCoordinatorTests.swift`: scripted MIDI source clock at 120 BPM → `tempo.snapshot` origin `.midiClock`, BPM 120 ± 0.1 with the toggle on; unchanged with it off; tap notice; loss by tick falls back to the tapped tempo (S5)

## Phase 4: User Story 2 - Clock loss and transport (P2)

- [X] MIDI-010-T08 [US2] Package tests in `MIDIClockTests.swift`: Stop and a 0.5 s gap unlock; pulses after Stop do not set the tempo (measurement kept warm); Start resets the position and the anchor falls on pulses 0, 24, 48; Song Position + Continue resumes at 6 × SPP; no Start → no anchor (S4) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 284 tests, 0 failures, 15.1 s (MIDIClockTests 13/13) `testStopAndATimeoutUnlock`, `testStartResetsThePositionAndTheAnchorFollowsEveryTwentyFourthPulse`, `testSongPositionAndContinueResume`

## Phase 5: User Story 3 - See the clock in Settings (P3)

- [ ] MIDI-010-T09 [US3] `Apps/projectM-iOS/Views/MIDIClockSettingsRows.swift` (toggle `midiFollowClockToggle`, status `midiClockStatus`), one line in `Apps/projectM-iOS/Views/MIDISettingsSection.swift`; DEBUG "Fake Clock 120" toggle (`midiFakeClockToggle`) in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift`; UI test `Apps/projectM-iOS/UITests/MIDIClockUITests.swift` reads "MIDI clock: 120.0 BPM" in under 30 s (S6)

## Phase 6: Polish & Cross-Cutting

- [ ] MIDI-010-T10 Key lists: `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (excluded), `Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift` (erased with Settings), `scripts/run_device_tests.py` `ALLOWED_KEYS`, `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`, the `-uitestResetNotice` reset in `AppCoordinator.swift`; run `LibraryBackupAppTests`, `SettingsTests`, the LibraryBackup package tests
- [ ] MIDI-010-T11 Repository checks (compliance, docs, motion policy, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app, PosterBoard count after; delete the simulator and derived data (S7)
- [ ] MIDI-010-T12 {device} On D1 with a hardware or app clock source at 120 and 174 BPM: turn on Follow MIDI clock; the readout shows the BPM within 0.1 and the beat grid follows Start; Stop falls back

## Dependencies

T01 → T02, T03 → T04 → T05 → T06 → T07; T08 after T04; T09 after T06; T10 after T06; T11 last; T12 after integration.
Parallel: T02 and T03; T08 alongside T06.

## Implementation strategy

MVP = Phases 1–3 (the row's acceptance S1 plus the app path). Then loss/transport, the Settings rows and the key lists.
