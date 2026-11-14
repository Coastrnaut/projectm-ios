# Tasks: PERF-008 Battery saver profile

**Input**: Design documents from `specs/201-perf-008-battery-saver/`
**Tests**: requested by the brief (budgets, governor composition, acceptance with a real `CaptureManager`, persistence, one UI test). Budgets per owner rule 7.

## Phase 1: Setup

- [X] PERF-008-T01 Confirm the baseline: QualityGovernorTests pass before changes; `Build` symlink present; simulator "PERF8 iPhone 17" (iOS 27.2) created — Verified 2026-11-14: xcodebuild test Rendering-Package on "PERF8 iPhone 17", QualityGovernorTests 8/8 before changes (the package does not build for the macOS host: ProjectM.xcframework has no macOS slice, as in CI); Build symlink present; simulator created

## Phase 2: Foundational (budgets in the governor)

- [X] PERF-008-T02 `PowerProfile` (`standard`, `followLowPowerMode`, `batterySaver`; unknown → `standard`), `PowerBudget` (standard = 60, 1.0, true; batterySaver = 30, 0.75, false), `PowerProfileState` (lock, `didChangeNotification` posted on main) in Packages/Rendering/Sources/Rendering/PowerProfile.swift — Verified 2026-11-14: Rendering-Package on "PERF8 iPhone 17": PowerProfileTests 5/5 and QualityGovernorTests 8/8 (13 tests, 0.02 s)
- [X] PERF-008-T03 `QualityGovernor.settings(thermal:lowPower:adaptiveEffects:budget:)` (fps = max(30, min(thermal fps, budget fps)); scale = min(thermal scale, budget scale)), `changeNotifications`, `current()` reads the state, in Packages/Rendering/Sources/Rendering/QualityGovernor.swift — Verified 2026-11-14: Rendering-Package on "PERF8 iPhone 17": PowerProfileTests 5/5 and QualityGovernorTests 8/8 (13 tests, 0.02 s)
- [X] PERF-008-T04 [P] Tests in Packages/Rendering/Tests/RenderingTests/PowerProfileTests.swift: budgets per profile and Low Power; composition over every thermal level × Low Power × adaptiveEffects for standard (equals today's table) and batterySaver (never above 30 / 0.75, never below 30); state change posts once and not for the same value — Verified 2026-11-14: Rendering-Package on "PERF8 iPhone 17": PowerProfileTests 5/5 and QualityGovernorTests 8/8 (13 tests, 0.02 s)

## Phase 3: User Story 1 - Choose battery saver (P1)

- [X] PERF-008-T05 [US1] Frame loops observe `QualityGovernor.changeNotifications`: Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift, Packages/Rendering/Sources/Rendering/GLESRenderer.swift, Apps/projectM-iOS/Visuals/{NativeSpectrumHost,PhotoVisualHost,TextVisualHost,VideoVisualHost,CameraVisualHost}.swift; the native host's `governedQuality` passes the budget (Apps/projectM-iOS/Visuals/NativeSpectrumHost+EffectQuality.swift) — Verified 2026-11-14: app build-for-testing on "PERF8 iPhone 17" (TEST BUILD SUCCEEDED, no type-check warning in a touched function) and PowerProfileAppTests.testNativeHostFollowsTheProfileWithoutRestarting; ANGLE/GLES/host observers read `QualityGovernor.changeNotifications` or the profile name (diff read)
- [X] PERF-008-T06 [US1] Background warm-up budget: `MediaPrewarmCoordinator.update(thermal:lowPower:budget:)` keeps only the next cue when the budget disallows warm-up and observes the profile notification; `RendererPresetLoader.prewarm` skips the SC-104 warm-up (Apps/projectM-iOS/Coordinators/MediaPrewarmCoordinator.swift, AppCoordinator.swift) — Verified 2026-11-14: app build-for-testing on "PERF8 iPhone 17" (TEST BUILD SUCCEEDED, no type-check warning in a touched function) and PowerProfileAppTests.testProfileChangesBudgetsWithoutChangingAudioSourceState (scheduler.lowPower, allowsWarmUp); MediaPrewarmAppTests 1/1 unchanged
- [X] PERF-008-T07 [US1] `PowerProfileSetting` (key `settings.performance.powerProfile`, `-uitestResetNotice` removes it, didSet stores, sets `PowerProfileState.current`, emits `DiagnosticsLog.powerProfile`) in Apps/projectM-iOS/Coordinators/PowerProfileSetting.swift; signpost in Packages/Diagnostics/Sources/Diagnostics/Logging.swift; created in `AppCoordinator.init` — Verified 2026-11-14: PowerProfileAppTests.testProfilePersistsAndUnknownFallsBack; signpost via `DiagnosticsLog.powerProfile` (Diagnostics 24 host tests pass)
- [X] PERF-008-T08 [US1] Settings rows `PowerProfileSection` (identifiers `powerProfile.<raw>`, section id `powerProfile`) in Apps/projectM-iOS/Views/PowerProfileSection.swift, added after `performanceSection`'s toggle in SettingsView.swift, passed from VisualizerView.swift — Verified 2026-11-14: PowerProfileUITests.testPickingBatterySaverSelectsItWithoutRestartingTheSource (17.1 s)
- [X] PERF-008-T09 [US1] Recording render limit `Reason.batterySaver` ("Battery saver limits the visual to 30 fps.") in Packages/Compositor/Sources/FrameRecording/RecordingFrameRate.swift; `RecordingQualitySetting.renderLimit(thermal:lowPower:budget:)` — Verified 2026-11-14: swift test Compositor RecordingFrameRateTests 11/11 (new reason text); PowerProfileAppTests.testRecordingRenderLimitReason; RecordingFrameRateAppTests 5/5
- [X] PERF-008-T10 [US1] Overlay line `power <title lowercased> <fps> fps <scale>x` when the budget is not standard, in Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift — Verified 2026-11-14: PowerProfileAppTests.testFollowLowPowerModeSwitchesWithLowPower (overlay line text); line appended after PERF-007 lines (diff read)
- [X] PERF-008-T11 [US1] Keys: `settings.performance.powerProfile` in `ALLOWED_KEYS` (scripts/run_device_tests.py) and `LibrarySettingsPolicy.includedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) — Verified 2026-11-14: swift test LibraryBackup 77+5 tests pass; scripts/test_scripts.py 159 OK
- [X] PERF-008-T12 [US1] Acceptance in Apps/projectM-iOS/Tests/PowerProfileAppTests.swift: a real `CaptureManager` with a fake source running; switching Standard → Battery saver → Standard changes the governor's budgets (60/1.0 → 30/0.75 → 60/1.0 at nominal), the prewarm scheduler's next-cue limit and the native host's quality, while the manager's mode, state, pause, switching, configuration and the source's start/stop counts are identical; the recording limit reason; persistence and unknown value; the frame loop is not restarted (the native host's display link object is the same before and after, PERF-008-R4) — Verified 2026-11-14: PowerProfileAppTests 5/5 on "PERF8 iPhone 17" (0.04 s total)
- [X] PERF-008-T13 [US1] UI test Apps/projectM-iOS/UITests/PowerProfileUITests.swift: pick Battery saver, it is selected; the source's start count is unchanged (under 30 s) — Verified 2026-11-14: PowerProfileUITests 1/1 (17.1 s; persistence is proven by the unit test, no relaunch)

## Phase 4: User Story 2 - Follow Low Power Mode (P2)

- [X] PERF-008-T14 [US2] Follow Low Power Mode budgets: covered in PowerProfileTests (Low Power off = standard, on = batterySaver) and the app test with injected Low Power — Verified 2026-11-14: PowerProfileTests.testBudgetsPerProfileAndLowPower; PowerProfileAppTests.testFollowLowPowerModeSwitchesWithLowPower

## Phase 5: Polish

- [X] PERF-008-T15 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; confirm no scene, show or preset format gained a profile field (PERF-008-R10, `grep -r powerProfile Packages/SceneFormat Packages/ShowControl` empty); type-check budget flags; PosterBoard counts — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; scene/show grep empty; PosterBoard reports 25 before and 25 after
- [ ] PERF-008-T16 {device} D1: 5 min Standard vs 5 min Battery saver (same preset, In-App Playback), Instruments Energy Log + Metal System Trace with the "Power profile" signpost; record frame time and energy per minute in docs/test-reports/performance.md (PERF-008-S3)

## Dependencies

T02 → T03 → T04/T05/T06/T09; T07 → T08, T10, T12; T12, T13 after T05-T11. T16 last.

## Implementation strategy

MVP = Phase 2 + US1 (T02-T13). US2 adds no code beyond the budget mapping.

## Analysis (speckit-analyze, 2026-11-14)

No CRITICAL or HIGH findings; coverage 10/10 requirements, S1-S2 by T04/T12, S3 by T16 `{device}`. Applied: R10
had no task (added the check to T15); R4 "without restarting" had no assertion (added to T12). Remaining LOW: the
background edge case relies on the notification path (no separate test).
