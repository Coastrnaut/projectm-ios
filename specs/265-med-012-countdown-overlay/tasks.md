# Tasks: MED-012 Countdown Overlay

**Input**: `specs/265-med-012-countdown-overlay/` (spec, plan, research, data-model, contracts, quickstart)

Tests are requested by the spec (MED-012-S1 to S5). Budgets (owner rule 7): unit tests ~1-2 s, a
package suite under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [X] MED-012-T01 Audit and spec artifacts in `specs/265-med-012-countdown-overlay/` (spec, plan, research, data-model, contracts, quickstart, tasks) — Verified 2026-11-14: spec, plan, research, data-model, contract, quickstart and tasks committed; `validate_docs.py` OK

## Phase 2: Foundational (shared with MED-011)

- [X] MED-012-T02 Share MED-011's plumbing: `ChangedText` and `StoredOverlayDecodeResult` in `Packages/Compositor/Sources/TextLayer/ClockOverlay.swift` (ClockText and ClockOverlayDecodeResult use them, behaviour unchanged); `LayerKind.countdown` (one per stack) in `TextLayerKind.swift`; app `Apps/projectM-iOS/Coordinators/OverlayTextLayers.swift` with `Compositor.attachOverlay(_:kind:)`, used by `ClockOverlayCoordinator` — Verified 2026-11-14: ClockFormatterTests, ClockLayerTests, ClockOverlayStoreTests and ClockOverlayUITests pass on the shared helpers

## Phase 3: User Story 1 - Run a countdown by hand (P1)

**Independent test**: injected clock; exact strings, zero once, never negative.

- [X] MED-012-T03 [US1] `Packages/Compositor/Sources/TextLayer/CountdownOverlay.swift`: `MonotonicClock`, `ContinuousMonotonicClock`, `FixedMonotonicClock`, `CountdownTimer` (duration "1…5,940 (clamped)", `remaining(at:) = max(0, duration − elapsed)`, `advance(at:)` true exactly once, start/pause/reset), `CountdownFormat` (contract C1), `CountdownSchedule`, `CountdownOverlaySettings` (version 1 JSON; defaults off, 300 s, startsFromCues false, top centre 8 % Menlo bold) — Verified 2026-11-14: CountdownTimerTests 8/8 (host and Linux shape)
- [X] MED-012-T04 [P] [US1] `Packages/Compositor/Tests/TextLayerTests/CountdownTimerTests.swift`: S1 strings, S2 overrun and one finished event across skips, a 10-hour jump and repeated ticks, pause/resume, Reset re-arms, settings JSON (damaged, newer, clamped) — Verified 2026-11-14: CountdownTimerTests 8/8
- [X] MED-012-T05 [P] [US1] `Packages/Compositor/Tests/TextLayerTests/CountdownLayerTests.swift`: S3 through the compositor: one rasterization per second while running, none after zero — Verified 2026-11-14: CountdownLayerTests 1/1 (host, Metal)
- [X] MED-012-T06 [US1] App: `CountdownOverlayStore.swift` (`settings.countdown.overlay`: missing → defaults, damaged → defaults and removed, newer → defaults untouched), `CountdownOverlayCoordinator.swift` (timer, Start/Pause/Reset, tick task while running, finished announcement on the new `.countdown` lane of `AccessibilityAnnouncer.swift`, attach), `AppCoordinator.swift` (create, attach above the clock in the four prepare functions, foreground tick), `AppSettings.swift` (key in `allKeys`) — Verified 2026-11-14: CountdownOverlayTests 3/3 on the iOS 27.2 simulator
- [X] MED-012-T07 [US1] Settings: `Apps/projectM-iOS/Views/CountdownSection.swift` (Show Countdown, Minutes, Seconds, Start/Pause/Resume, Reset, Start From New Cues, Position, Alignment) and one line in `SettingsView.swift` after Clock (`.id("countdown")`, `UITestSettingsSection` list), `VisualizerView.swift` passes it — Verified 2026-11-14: CountdownOverlayUITests 1/1 (Settings › Countdown, Start)
- [X] MED-012-T08 [US1] Keys: `scripts/run_device_tests.py` ALLOWED_KEYS, `LibrarySettingsPolicy.includedKeys`, `SettingsTests.testOnlyTheSettingsKeysAreWritten`; run `LibraryBackupAppTests` and `SettingsTests` — Verified 2026-11-14: SettingsTests 9/9, LibraryBackupAppTests 5/5, LibraryBackup package 87/87, script tests OK
- [X] MED-012-T09 [US1] `Apps/projectM-iOS/Tests/CountdownOverlayTests.swift`: store round trip and damaged value, coordinator with an injected clock (strings pushed once per second, finished once, announcement once, Reset re-arms, duration change resets, MED-012-R7: the `.countdown` entry sits above `.clock` in a compositor stack) — Verified 2026-11-14: CountdownOverlayTests 3/3
- [X] MED-012-T10 [US1] DEBUG `-uitestCountdownFixed` fixture and `countdownProbe`; `Apps/projectM-iOS/UITests/CountdownOverlayUITests.swift` (S5: Show Countdown, Start, "05:00 running" drawn on the Text visual) — Verified 2026-11-14: CountdownOverlayUITests 1/1 (13.0 s)

## Phase 4: User Story 2 - Start it from a cue (P2)

**Independent test**: scene round trip; applying a scene with the field starts the countdown.

- [X] MED-012-T11 [US2] `Packages/SceneFormat/Sources/SceneFormat/SceneCountdown.swift` (`{"durationSeconds": <integer 1…5940>}`, exactly that key, else absent and kept verbatim) and `Packages/SceneFormat/Tests/SceneFormatTests/SceneCountdownTests.swift` (round trip through encode and decode, malformed cases) — Verified 2026-11-14: SceneFormat package 203/203 incl. SceneCountdownTests 2
- [X] MED-012-T12 [US2] `ShowSceneSnapshot.swift` (`ShowLook.countdownSeconds` written, `ShowSceneApply.countdownSeconds` read), `AppCoordinator+Show.swift` (`showLook` records it when Start From New Cues is on; `applyShowScene` starts it); tests in `CountdownOverlayTests.swift` (cue apply starts at "01:30", no field leaves it alone; MED-012-R8: launch restore and reopen never call the start path, checked by reading `SceneAutosaveCapture`'s restored values, which carry no countdown) — Verified 2026-11-14: CountdownOverlayTests.testACueSceneRecordsAndStartsTheCountdown, ShowCoordinatorTests 8/8

## Phase 5: Polish

- [X] MED-012-T13 Repo checks, type-check budget, privacy manifest and network symbols on the Debug app; test report `docs/test-reports/countdown-overlay.md`; spec status — Verified 2026-11-14: repo checks, privacy manifest, network symbols OK; `docs/test-reports/countdown-overlay.md`
- [ ] MED-012-T14 {device} On D1: Text visual, Show Countdown, 0:10, Start: it reaches "00:00" once and holds, VoiceOver says "Countdown finished" once, and a recording contains the countdown

## Dependencies

T01 → T02 → T03 → (T04, T05 in parallel) → T06 → T07 → T08 → T09 → T10; T11 after T02 (independent of US1 UI); T12 after T06 and T11; T13 last; T14 needs a device.

## Implementation strategy

MVP is US1 (manual countdown). US2 adds the cue trigger on the same coordinator.
