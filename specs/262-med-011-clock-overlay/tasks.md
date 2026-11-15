# Tasks: MED-011 Clock Overlay

**Input**: `specs/262-med-011-clock-overlay/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MED-011-S1 to S5). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks stay open until a person
runs them.

## Phase 1: Setup

- [ ] MED-011-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MED11 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MED-011-T02 [P] `ClockSource`, `SystemClockSource`, `FixedClockSource`, `ClockHourCycle`, `ClockFormatter` (fixed patterns, injected locale and time zone), `ClockText` (string only on change), `ClockSchedule.delay(after:)` and `ClockOverlaySettings` (defaults, versioned JSON, `decodeStored`) in `Packages/Compositor/Sources/TextLayer/ClockOverlay.swift` (MED-011-R2, R3, R5, R8; contract C1, C2)
- [ ] MED-011-T03 [P] `LayerKind.clock` in `TextLayerKind.swift`; `TextLayerSource` init `name:` (default "text") and `rasterizationCount` in `TextLayerSource.swift` (R4; contract C3)
- [ ] MED-011-T04 `ClockFormatterTests.swift` in `Packages/Compositor/Tests/TextLayerTests/`: the four exact strings (S1), midnight and both 2026 New York DST transitions (S4), `ClockText` reports only changes, schedule alignment, settings JSON round trip / damaged / newer; also in the Linux shape

## Phase 3: User Story 1 - Show the time over the visual (P1) — MVP

**Independent test**: with a fixed clock, the clock layer's pixels are identical across renders and change one minute later.

- [ ] MED-011-T05 [US1] `ClockLayerTests.swift` (Metal, real compositor, 64 × 64): same clock → identical rendering checksum and read-back pixels on two renders; +1 minute → different (S2); 60 one-second ticks within a minute without seconds → one rasterization and one render (S3) (contract C3)
- [ ] MED-011-T06 [US1] `ClockOverlayStore` (`settings.clock.overlay`) and `ClockOverlayCoordinator` (settings saved on change, `attach(to:)` with `Compositor.attachClock`, `tick()`, aligned tick task while shown and a layer is live, hidden → empty spec) in `Apps/projectM-iOS/Coordinators/` (R1, R5, R6, R8; contract C4)
- [ ] MED-011-T07 [US1] `AppCoordinator`: create the coordinator, attach the clock in the four compositor prepare functions after the logo; DEBUG `-uitestClockFixed` fixture and `clockProbe` in `VisualizerView` (R6)
- [ ] MED-011-T08 [US1] Keys: `settings.clock.overlay` in `AppSettings.allKeys` (UI-test reset), `SettingsTests.testOnlyTheSettingsKeysAreWritten` (written by its own store), `LibrarySettingsPolicy.includedKeys` (backup; erased with Settings), `ALLOWED_KEYS` in `scripts/run_device_tests.py`; `LibraryBackupAppTests` passes via `AppSettings.allKeys` (R9; FILE-011 Settings erase derives from `includedKeys`)

## Phase 4: User Story 2 - Choose the format and position (P2)

- [ ] MED-011-T09 [US2] `ClockSection` (Show Clock, Format, Seconds, Position, Alignment, scope note) in `Apps/projectM-iOS/Views/ClockSection.swift`, added to `SettingsView`'s media sections after the Logo section (R7)
- [ ] MED-011-T10 [US2] `ClockOverlayStoreTests` (defaults off; save and relaunch; damaged removed; newer untouched; coordinator ticks push a spec only on change with a manual clock) (S5)
- [ ] MED-011-T11 [US2] `ClockOverlayUITests` (fixed clock, Text visual, `clockProbe` shows "14:05" drawn; Settings shows the Clock section) under 30 s (S5)

## Phase 5: Polish

- [ ] MED-011-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard count after (R10: no networking API, no permission); report `docs/test-reports/clock-overlay.md`; spec status
- [ ] MED-011-T13 {device} On D1 and D3: Show Clock on the Text and Photo visuals; the clock matches the status bar, changes at the minute, is readable; 12-hour with seconds updates each second; a REC-003 recording contains the clock

## Dependencies

T01 → T02, T03 → T04, T05 → T06 → T07, T08 → T09 → T10, T11 → T12 → T13.
