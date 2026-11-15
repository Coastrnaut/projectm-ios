# Tasks: OUT-011 Output Connection Diagnostics

**Input**: design documents in `specs/275-out-011-output-diagnostics/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance: pure, app, UI tests). Budgets: owner rule 7.

## Phase 1: Setup

- [X] OUT-011-T01 Create simulator "OUT11 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree — Verified 2026-11-14: simulator 14CB335A created; `xcodegen generate` OK

## Phase 2: Foundational (C1)

- [X] OUT-011-T02 Add `OutputReadings`, `OutputDiagnostics`, `OutputDiagnosticsRow` (sanitising: "nil when not ≥ 1 / ≤ 0 / non-finite / unspecified", formats per spec Clarifications) in Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputDiagnostics.swift — Verified 2026-11-14: `swift test` PresentationLifecycle 114 tests pass (0.13 s)
- [X] OUT-011-T03 [P] Pure tests (full readings format, missing values read "Not available", zero/non-finite sanitised, disconnected rows/text/summary) in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputDiagnosticsTests.swift — Verified 2026-11-14: OutputDiagnosticsTests 5/5 pass on the Mac host

## Phase 3: User Story 1 + 2 — values while connected, nothing stale after unplug (P1)

**Independent test**: connect the stand-in, read the values; disconnect, `.disconnected`; reconnect at another size, new values.

- [X] OUT-011-T04 [US1] `OutputScreenReader.readings(screen:)` (the only UIKit reader) in Apps/projectM-iOS/ExternalDisplay/OutputScreenReader.swift — Verified 2026-11-14: OutputDiagnosticsAppTests.testRealSlotReadsItsOwnScreen (native resolution and Hz equal the scene screen)
- [X] OUT-011-T05 [US1] `VisualSlotView.standInReadings` in Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift — Verified 2026-11-14: OutputDiagnosticsAppTests (stand-in readings used)
- [X] OUT-011-T06 [US2] `ExternalDisplayCoordinator.outputDiagnostics`, computed at read time from the first settled display's live slot, else `.disconnected` (OUT-011-R4) in Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift — Verified 2026-11-14: OutputDiagnosticsAppTests 3/3 pass on iOS 27.2 simulator (disconnect → `.disconnected` inside the call)
- [X] OUT-011-T07 [US1] `OutputDiagnosticsSection` (rows as labelled accessibility elements, 1 s TimelineView, observes `hasExternalDisplay`) in Apps/projectM-iOS/Views/OutputDiagnosticsSection.swift; add it after ExternalDisplaySection in Apps/projectM-iOS/Views/SettingsView.swift — Verified 2026-11-14: OutputDiagnosticsUITests reads the rows in Settings; type-check warnings none in new code
- [X] OUT-011-T08 [US2] DEBUG fake: stand-in readings, `uitestConnectExternalSmall` (1280 × 720), probe `externalDiagnostics` in Apps/projectM-iOS/Debug/UITestExternalDisplay.swift — Verified 2026-11-14: OutputDiagnosticsUITests (probe `externalDiagnostics`); ext+720 used by the app test path via `standInReadings(width:height:)`
- [X] OUT-011-T09 [US2] App acceptance test (connect → values; disconnect → `.disconnected`, no old value in rows, text or summary; reconnect 1280 × 720 → new values; settling connection reads disconnected; drawable reads "Not available" while the visual is on the device (OUT-011-R2, R4, R5)) in Apps/projectM-iOS/Tests/OutputDiagnosticsAppTests.swift — Verified 2026-11-14: OutputDiagnosticsAppTests 3/3 pass (0.03 s total)
- [X] OUT-011-T10 [US2] UI test (connect, read the panel, disconnect, "No external display connected"; asserts each row's accessibility label is its title and value its value (OUT-011-R7); under 30 s) in Apps/projectM-iOS/UITests/OutputDiagnosticsUITests.swift — Verified 2026-11-14: OutputDiagnosticsUITests 1/1 pass in 24.8 s on iOS 27.2 simulator

## Phase 4: User Story 3 — copy (P3)

- [X] OUT-011-T11 [US3] "Copy diagnostics" (only while connected; `UIPasteboard.general.setItems(..., options: [.localOnly: true])`) in Apps/projectM-iOS/Views/OutputDiagnosticsSection.swift; covered by the text test in T03 — Verified 2026-11-14: UI test asserts the copy button shows only while connected; copy text covered by OutputDiagnosticsTests (`text`)

## Phase 5: Polish

- [ ] OUT-011-T12 {device} On D1 with a real HDMI display: values against the display's specification; unplug with the panel open shows "No external display connected" at once; replug shows fresh values (quickstart B)
- [X] OUT-011-T13 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app; delete the simulator and derived data — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest and check_network_symbols OK on the Debug app

## Dependencies

T01 → T02 → T03; T02 → T04-T08 → T09, T10; T07 → T11; all → T13. T12 needs a person and a display.

## Parallel examples

T03 alongside T04/T05 (different files). T09 and T10 build once, run separately.

## Implementation strategy

MVP = Phases 2-3 (the roadmap acceptance). US3 is a small addition in the same view.

## Analyze (2026-11-14)

speckit-analyze: 0 critical; applied: C1 R7 VoiceOver assertion added to T10; C2 edge cases (settling, drawable while the visual is on the device) added to T09; A1 R6a renumbered R11. Coverage R1-R11: 100 %.
