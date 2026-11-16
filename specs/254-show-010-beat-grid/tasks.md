# Tasks: SHOW-010 Beat Grid

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/beat-grid.md](contracts/beat-grid.md), [quickstart.md](quickstart.md). Tests are requested (roadmap
acceptance; owner rule 7 budgets).

## Phase 1: Setup

- [X] SHOW-010-T01 Create simulator "SHOW10 iPhone 17" (iOS 27.2), run `xcodegen generate`, record the PosterBoard report count before runs — Verified 2026-11-14: simulator 6B12C60C ("SHOW10 iPhone 17", iOS 27.2) created, `xcodegen generate`, preset submodules initialised; PosterBoard reports 26 before runs

## Phase 2: Foundational (grid model)

- [X] SHOW-010-T02 Add `BeatGridTempo` (`init?` fails for period ≤ 0 or non-finite BPM), `BeatGridTick`, `BeatGridPosition`, `BeatGridMark` and `BeatGrid` (`ticks` G1 with the 512 bound, `stride` G2, `marks` G3, `position`, `nearestBeat`, `readoutText`, `accessibilityValue` G4) in Packages/ShowControl/Sources/ShowControl/BeatGrid.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (154 tests, 1.3 s; 8 new in BeatGridTests); Foundation only
- [X] SHOW-010-T03 [P] Package tests: 120 BPM ticks exactly 500,000,000 ns apart over 0–10 s (21 ticks), bars at 0, 2 … 10 s; anchor 0.25 s shifts every tick; window before the anchor; no tempo → none; 512 bound and stride choice; positions (bar 3 beat 2 at 4.5 s; 0:00 in bar 1 with an offset anchor); nearest beat; texts; marks for a 20 s timeline 300 points wide (x within 0.01 point, SHOW-010-S3) in Packages/ShowControl/Tests/ShowControlTests/BeatGridTests.swift — Verified 2026-11-14: `BeatGridTests` 8/8 (21 ticks exactly 500,000,000 ns apart, bars at 0…10 s; 0.25 s anchor shift; before the anchor; no tempo; 512 bound and strides 1/4/16; positions; texts; 41 marks within 0.01 point)

## Phase 3: User Story 1 — See the beats on the show timeline (P1) MVP

**Independent test**: BeatGridTests plus the app acceptance test with a seeded 120 BPM tempo.

- [X] SHOW-010-T04 [US1] `ShowBeatGridCoordinator` (tempo and tempo-clock closures; placement while playing, kept while paused/Standby, 0 without anchor; `gridTempo()`, `marks(width:inset:)`, `readout()`) in Apps/projectM-iOS/Coordinators/ShowBeatGridCoordinator.swift; lazy `beatGrid` in Apps/projectM-iOS/Coordinators/ShowTransportCoordinator.swift; tempo wiring in Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift — Verified 2026-11-14: `ShowBeatGridAcceptanceTests` placement (0.2 s from a tap 0.3 s before 4.0 s), kept while paused, 0:00 without an anchor; app build-for-testing on "SHOW10 iPhone 17" with no new type-check warnings
- [X] SHOW-010-T05 [US1] Draw ticks under the thumb in `ShowScrubBar` (Apps/projectM-iOS/Views/ShowBeatGridTicks.swift, Apps/projectM-iOS/Views/ShowTimelineRow.swift); the scrub gesture unchanged — Verified 2026-11-14: `ShowBeatGridUITests` probe reports drawn ticks; simulator screenshot shows bar ticks across the 2:30 track; `ShowTimelineUITests` (scrub release seeks into cue 3) still passes
- [X] SHOW-010-T06 [US1] App acceptance tests (placement, kept while paused, 0:00 without phase, marks at expected x for 120 BPM (within 0.01 point), no tempo → no marks) in Apps/projectM-iOS/Tests/ShowBeatGridAcceptanceTests.swift — Verified 2026-11-14: `ShowBeatGridAcceptanceTests` 4/4 (0.04 s): 41 marks at 14 + i × 6.8 points within 0.01, bars every 4th; no tempo → no marks

## Phase 4: User Story 2 — Hear the position with VoiceOver (P1)

- [X] SHOW-010-T07 [US2] Readout `showBeatGridReadout` (visible "Bar B · Beat b · N BPM" / "No tempo", VoiceOver label "Beat grid" and value per G4 at the displayed time) and the DEBUG `-uitestBeatGridProbe` text in Apps/projectM-iOS/Views/ShowTimelineRow.swift — Verified 2026-11-14: `ShowBeatGridUITests`: readout label "Beat grid", value "120 BPM, detected, bar …"; probe present only with `-uitestBeatGridProbe`
- [X] SHOW-010-T08 [US2] Readout tests ("120 BPM, tap tempo, bar 3 beat 2" at 4.5 s; "detected" for an estimate) in Apps/projectM-iOS/Tests/ShowBeatGridAcceptanceTests.swift — Verified 2026-11-14: `ShowBeatGridAcceptanceTests`: "120 BPM, tap tempo, bar 3 beat 4" at 4.0 s, "120 BPM, detected, bar 3 beat 2" at 4.5 s, "120 BPM" at Standby, "No tempo" below the floor
- [X] SHOW-010-T09 [US2] UI test (< 30 s): timeline seed + `-uitestTempoEstimate 120:0.9` + probe → readout value starts "120 BPM, detected, bar", probe reports ticks, in Apps/projectM-iOS/UITests/ShowBeatGridUITests.swift — Verified 2026-11-14: `ShowBeatGridUITests` 1/1 (11.7–13.4 s)

## Phase 5: Polish

- [X] SHOW-010-T10 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, ShowControl Linux shape (Foundation only) — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK (1 skipped); check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; no function body over 300 ms or expression over 150 ms in the touched files; BeatGrid.swift imports Foundation only
- [X] SHOW-010-T11 Spec status, PosterBoard counts, delete the simulator and derived data — Verified 2026-11-14: PosterBoard reports 26 before, 27 after (one report at 20:32 during the UI-test window; its simulator is not named in the report); simulator "SHOW10 iPhone 17" and derived data deleted
- [ ] SHOW-010-T12 {device} On D1, tap tempo with a 120 BPM track and play a timed show: ticks every half second, readout counts bars with the music D1 partly automated 2026-11-15 (docs/test-reports/qa-011/acceptance/D1-B02.md): ShowBeatGridUITests, the timeline shows a 120 BPM grid. Open: ticks and bar readout against a 120 BPM track.

## Dependencies

T01 → T02 → T03; T02 → T04 → T05, T06; T04 → T07 → T08, T09; all → T10 → T11. T12 needs a person and a device.

## Parallel opportunities

T03 alongside T04 (different files). T06 and T08 share a file (same writer, sequential).

## Implementation strategy

MVP is US1 (model + ticks). US2 adds the readout; both are P1 and ship together.
