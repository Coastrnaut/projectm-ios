# Tasks: AUD-010 Channel Balance

**Input**: Design documents from `specs/138-aud-010-channel-balance/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/playback-balance.md, quickstart.md

Tests are requested by the brief (acceptance, law, availability, persistence, UI).

## Phase 1: Setup

- [X] AUD-010-T01 Create the feature simulator "AUD10 iPhone 17" (iOS 27.2), run `xcodegen generate`, link `Build` to the main checkout's xcframeworks, and record the PosterBoard report count before any simulator run — Verified 2026-11-14: simulator AUD10 iPhone 17 (4726F364) created, xcodegen generate, Build link; PosterBoard count 25 before

## Phase 2: Foundational

- [X] AUD-010-T02 [P] Add `MonitorBalance` (`range` −1…1, `detent` 0.03, `validated`: "NaN → 0; clamp; round to 0.01; |b| ≤ detent → 0", `gains`: "left = min(1, 1 − b), right = min(1, 1 + b)") in Packages/AudioCore/Sources/AudioCore/MonitorBalance.swift — Verified 2026-11-14: MonitorBalanceTests (4 tests) pass
- [X] AUD-010-T03 [P] Law and validation tests at −1, −0.5, 0, 0.5, 1 plus NaN, out of range, detent and rounding in Packages/AudioCore/Tests/AudioCoreTests/MonitorBalanceTests.swift (host and `-DAUDIOCORE_NO_AVFAUDIO`) — Verified 2026-11-14: swift test --filter MonitorBalanceTests, host and -DAUDIOCORE_NO_AVFAUDIO, 4/4 each

## Phase 3: User Story 1 - Balance what I hear without changing the visuals (P2)

**Goal**: the heard output follows the balance; the analysis PCM never does.
**Independent test**: PlaybackBalanceTests in offline manual rendering.

- [X] AUD-010-T04 [US1] Insert `balanceNode` after the main mixer (tap unchanged) and add `monitorBalance` plus a test-only offline render that returns the output buffer in Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackGraph.swift (minimal, commented: REC-004 edits this graph too) — Verified 2026-11-14: swift test --package-path Packages/CaptureKit: 476 tests, 0 failures (53 s), incl. PlaybackBalanceTests 5/5
- [X] AUD-010-T05 [US1] Add `setMonitorBalance(_:)` to `InAppPlaybackBackend` with a default no-op, `InAppPlaybackSource.monitorBalance`, and keep and apply the value in every graph of Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/AVInAppPlaybackBackend.swift and InAppPlaybackSource.swift — Verified 2026-11-14: PlaybackBalanceTests.testBackendAppliesTheBalanceToEveryGraph and testSourceForwardsValidatedBalance pass
- [X] AUD-010-T06 [US1] Acceptance tests in Packages/CaptureKit/Tests/CaptureKitTests/PlaybackBalanceTests.swift: a stereo fixture (440 Hz left, 1 kHz right) at −1, 0, +1 delivers identical sink PCM (within 1e-6) while the output's channel levels follow the law; levels at −0.5 and 0.5; a mid-play change causes no discard and keeps the position; the balance survives a track change, a seek and a media-services rebuild (R5); the backend applies the value to its graph; the source forwards validated values to a scripted backend — Verified 2026-11-14: PlaybackBalanceTests 5/5 on the macOS host (1.6 s): analysis PCM at -1/+1 equals centre within 1e-6, heard RMS within 1 % at -1, -0.5, 0, 0.5, 1, no discard or reschedule on a mid-play change, kept across replaceTrack, seek and mediaServicesReset

## Phase 4: User Story 2 - Set, reset and keep the balance (P2)

**Goal**: a stored, accessible Settings control.
**Independent test**: PlaybackBalanceSettingTests and the UI test.

- [X] AUD-010-T07 [P] [US2] `PlaybackBalanceSetting` (key `settings.playbackBalance.position`, validated, `reset`, `onChange`, `text(for:)` "Centered" / "30% left" / "30% right", `isAvailable(for:)`) in Apps/projectM-iOS/Coordinators/PlaybackBalanceSetting.swift — Verified 2026-11-14: PlaybackBalanceSettingTests 6/6 on AUD10 iPhone 17 (iOS 27.2)
- [X] AUD-010-T08 [US2] `SpokenUnit.balance` ("centered", "30 percent left") and the `playbackBalance` catalog spec (label "Balance", step 0.1) in Apps/projectM-iOS/Views/AccessibleParameter.swift — Verified 2026-11-14: AccessibleParameterTests (catalog, spoken value, table step and persistence) pass on AUD10
- [X] AUD-010-T09 [US2] `PlaybackBalanceSection` (slider with `.accessibleParameter`, double-tap reset, Center button, footer) in Apps/projectM-iOS/Views/PlaybackBalanceSection.swift; add it to `audioSections` in Apps/projectM-iOS/Views/SettingsView.swift and pass it from Apps/projectM-iOS/Views/VisualizerView.swift — Verified 2026-11-14: PlaybackBalanceUITests.testBalanceMovesAndCentresUnderInAppPlayback passes on AUD10
- [X] AUD-010-T10 [US2] Wire the setting in Apps/projectM-iOS/Coordinators/AppCoordinator.swift (create, push to `inAppPlayback.monitorBalance` at launch and on change, UI-test reset `-uitestResetNotice`) — Verified 2026-11-14: app builds; PlaybackBalanceUITests (launch with -uitestResetNotice starts centred) pass
- [X] AUD-010-T11 [P] [US2] Add the key to `ALLOWED_KEYS` in scripts/run_device_tests.py and `LibrarySettingsPolicy.includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift — Verified 2026-11-14: PlaybackBalanceSettingTests.testKeyIsInTheBackupPolicy, LibraryBackupAppTests, LibraryEraseAppTests and test_scripts.py (153 tests, ALLOWED_KEYS check) pass
- [X] AUD-010-T12 [US2] Setting tests (persistence, invalid values, detent, text, spoken value, availability, key lists) in Apps/projectM-iOS/Tests/PlaybackBalanceSettingTests.swift — Verified 2026-11-14: PlaybackBalanceSettingTests 6/6 on AUD10

## Phase 5: User Story 3 - No balance for sources the app does not play (P2)

- [X] AUD-010-T13 [US3] Pass `playbackBalanceAvailable` (`manager.activeMode == .inAppPlayback`) to Settings; the section disables the slider and Center otherwise (covered by T12's availability test) — Verified 2026-11-14: PlaybackBalanceSettingTests.testAvailableForInAppPlaybackOnly and PlaybackBalanceUITests.testBalanceIsDisabledUnderTheMicrophone pass
- [X] AUD-010-T14 [US3] UI test in Apps/projectM-iOS/UITests/PlaybackBalanceUITests.swift: In-App Playback → Balance enabled, adjust moves it off centre, Center resets; Microphone fake source → slider disabled (under 30 s each) — Verified 2026-11-14: PlaybackBalanceUITests 2/2 on AUD10 (22 s and 34 s at load average ~660; launch and reveal dominate)

## Phase 6: Polish

- [X] AUD-010-T15 Run the repo checks, the type-check budget, `check_privacy_manifest.py` and `check_network_symbols` on the Debug app; record PosterBoard counts; delete the simulator, derived data and the `Build` link — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts (153) OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; PlaybackBalanceTests 5/5 also on the iOS 27.2 simulator; PosterBoard 25 before, 25 after; simulator, derived data and Build link removed. Type-check: no new function or expression over budget; AppCoordinator.init measured 398 ms without this change at load average ~500 (pre-existing, load-dominated)
- [ ] AUD-010-T16 {device} On D1 with wired headphones and AirPods: full left silences the right ear, an interruption and a route change keep the balance, the visuals do not change with it

## Dependencies

T02 → T04–T06 → T07–T14 → T15. T03 parallel with T04. T11 parallel with T07. US3 needs US2's section.

## Implementation Strategy

US1 first (the acceptance proof), then the setting and UI (US2, US3), then checks.
