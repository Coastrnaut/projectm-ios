# Tasks: OSC-007 OSC Network Access Switch

**Input**: `specs/038-osc-007-osc-network-access-switch/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first (the row's acceptance is a test). No wall-clock assertions: polls and
expectations with generous ceilings. Unit tests about 1-2 s (≤ 10 s), UI test < 30 s (owner rule 7).
Logs go to `.build/scratch/`. Device-only checks are tagged `{device}` and are not run by this row.

Format: `- [ ] OSC-007-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [ ] OSC-007-T01 Record the baseline before any change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `swift test --package-path Packages/PerformanceControl`; note results here.

## Phase 2: Foundational — the badge rule (tests first)

- [ ] OSC-007-T02 [US1] Write `Apps/projectM-iOS/Tests/OSCNetworkAccessTests.swift` (fake transport, no networking): `OSCReceiverCoordinator.listenerBadgePort(for:)` is the port for `listening(port)` and nil for `off`, `starting`, `stopping`, every `failed` (OSC-007-S3); `badgeText(port: 9000)` is "OSC listening on port 9000"; the coordinator's `badgePort` follows enable (9000), background (nil), foreground (9000), disable (nil).
- [ ] OSC-007-T03 [US1] Implement in `Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift`: `static func listenerBadgePort(for:) -> UInt16?`, `var badgePort: UInt16?`, `static func badgeText(port:) -> String` (contract); T02 passes.

## Phase 3: User Story 1 — see that OSC is listening (P1)

- [ ] OSC-007-T04 [US1] Create `Apps/projectM-iOS/Views/OSCListenerBadge.swift`: shown iff `osc.badgePort != nil`; visible "OSC listening on port N" and a "Stop" button; identifiers `oscListenerBadge`, `oscListenerBadgeText`, `oscStopButton`; label "OSC listening", value "Port N"; Stop label "Stop OSC", hint "Turns off the OSC receiver" (contract, OSC-007-R7).
- [ ] OSC-007-T05 [US1] Show the badge as the first row of the top status stack in `Apps/projectM-iOS/Views/VisualizerView.swift`, independent of `controlsVisible` (OSC-007-R2, R6; CAM-012 merge point noted in a comment), and in the chooser's bottom safe-area inset in `Apps/projectM-iOS/ProjectMApp.swift`. The chooser placement has no UI test (the UI tests autostart past the chooser); it is verified by the build and by reading the diff (analyze finding C3).

## Phase 4: User Story 2 — Stop with one tap (P1)

- [ ] OSC-007-T06 [US2] Add to `OSCNetworkAccessTests`: `stopFromBadge()` while listening → `settings.oscEnabled` false, state reaches `off`, `badgePort` nil, the fake transport logged exactly one stop; a second `stopFromBadge()` changes nothing; the port and test value are unchanged; a foreground cycle afterwards opens nothing (OSC-007-R4, R5; US2 scenario 2).
- [ ] OSC-007-T07 [US2] Implement `stopFromBadge()` (calls `setEnabled(false)`) in `OSCReceiverCoordinator.swift`, wire the badge's Stop to it and post the "OSC off" VoiceOver announcement in `OSCListenerBadge.swift`; T06 passes.

## Phase 5: User Story 3 — fresh install and real socket state (P1)

- [ ] OSC-007-T08 [US3] Add to `OSCNetworkAccessTests`: on an empty defaults suite, construct the coordinator, `sceneBecame(active: false)`, `sceneBecame(active: true)` → the transport factory was called 0 times and the state is `off` (OSC-007-R1, S1).
- [ ] OSC-007-T09 [US3] Add to `OSCNetworkAccessTests` the real-transport test with `OSCReceiver.system()`: port in 49152-65000; `setEnabled(true)` → poll until `listening(port)` (a `failed` state → `XCTSkip`); `setEnabled(false)` → poll until `off`; a second `OSCReceiver.system()` reaches `listening` on the same port, then stops (OSC-007-R8, S2). Ceilings 5 s; no wall-clock assertions.

## Phase 6: UI test and polish

- [ ] OSC-007-T10 Write `Apps/projectM-iOS/UITests/OSCNetworkAccessUITests.swift` (launch like `OSCReceiverUITests`, port 47124, `UITestWaits` polls, `scrollTo` with held drags): enable in Settings, close Settings, the badge reads "OSC listening on port 47124" with the controls shown (its Stop and the controls' `settings` button both hittable, OSC-007-R6) and with the controls hidden; the badge text's label is "OSC listening" and value "Port 47124", the Stop button's label "Stop OSC" (OSC-007-R7); tap Stop; the badge disappears; open Settings: toggle value "0", status "Off" (OSC-007-S4, < 30 s).
- [ ] OSC-007-T11 One sentence on the badge and Stop in `docs/privacy-policy.md` ("OSC control on your local network"); results in `docs/test-reports/osc-network-access.md`; `check_compliance.py`, `validate_docs.py`, PerformanceControl suite; PosterBoard count before/after.
- [ ] OSC-007-T12 `{device}` On D1 over Wi-Fi (quickstart D): the badge shows while listening, Stop ends delivery and Settings shows off (OSC-007-S5). Owner, last stage.

## Dependencies

T01 → T02 → T03 → T04/T05 → T06 → T07; T08, T09 depend only on T03's file existing (same test file: write in order); T10 after T05 and T07; T11 last; T12 after integration, on a device.

## Parallel opportunities

T04 (new view file) and T08/T09 (tests) touch different files and can be written in parallel; T11's privacy sentence is independent.

## Implementation strategy

MVP = US1 + US2 (badge and Stop); US3 adds the acceptance tests. One commit per complete change.
