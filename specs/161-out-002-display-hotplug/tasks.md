# Tasks: OUT-002 Display Connect Handling

**Input**: Design documents from `specs/161-out-002-display-hotplug/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/hot-plug.md, quickstart.md

Tests are part of this feature (the row's acceptance is a fixture). Budgets (owner rule 7): unit
tests ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (blocking)

- [X] OUT-002-T01 [P] Add `HotPlugSettle` (pending connections with a token per connect, `connect`, `update`, `cancel`, `settle(token)`, `cancelled` count; "a repeat connect replaces the entry") and `ExternalDisplayRouting.effectiveTarget(held:)` in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/HotPlugSettle.swift` — Verified 2026-11-14: HotPlugSettleTests (9 pass, host)
- [X] OUT-002-T02 [P] Package tests for T01 in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/HotPlugSettleTests.swift` (settle, stale token, cancel, update while pending, held target valid / gone / not visualizing) — Verified 2026-11-14: swift test --filter HotPlugSettleTests, 9 pass in 0.002 s
- [X] OUT-002-T03 Add the `ExternalDisplayEventSink` protocol (contract C1) and adopt it in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`; drive the DEBUG fake through it in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift` — Verified 2026-11-14: build-for-testing (iOS 27.2 sim); HotPlugAcceptanceTests drive the coordinator through the protocol

## Phase 2: User Story 1 - Plug and unplug without losing the show (P1) MVP

**Independent test**: `HotPlugAcceptanceTests` fixture.

- [X] OUT-002-T04 [US1] Settle connects in `ExternalDisplayCoordinator` (`connectSettle`, injected `scheduleSettle`; `.shared` uses 0.3 s, `init()` defaults to 0 so OUT-001's in-call tests keep their meaning); cancel on disconnect; `externalResources` counters; slots released on disconnect — Verified 2026-11-14: HotPlugAcceptanceTests (7 pass, 1.3 s) and ExternalDisplayCoordinatorTests (9 pass) on the iOS 27.2 simulator
- [X] OUT-002-T05 [US1] Placement hold (`holdsPlacement`, `place()` uses `effectiveTarget(held:)`; release re-places) in `ExternalDisplayCoordinator.swift`; `onStateChange` hook in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`; wiring in new `Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift` (one call from `AppCoordinator.init`) — Verified 2026-11-14: HotPlugAcceptanceTests testConnectDisconnectFixture… and testAHeldConnectionMovesWhenTheRecordingEnds; VideoRecordingAppTests 18 pass
- [X] OUT-002-T06 [US1] Acceptance fixture in `Apps/projectM-iOS/Tests/HotPlugAcceptanceTests.swift`: fake display connector, a render session (view + recording source) ticked by an injected clock, a scene witness, a real `VideoRecordingCoordinator`; connect, disconnect, connect, disconnect; asserts same session, frames increasing, scene unchanged, no trails reset (no size change), zero external resources, recording still running (OUT-002-S1); plus a run without recording (moves happen, trails reset only on a size change) and a held connect that moves when the recording ends — Verified 2026-11-14: HotPlugAcceptanceTests, 3 fixture tests pass on the iOS 27.2 simulator

## Phase 3: User Story 2 - A flaky connection does not thrash (P2)

- [X] OUT-002-T07 [US2] Debounce and leak tests in `HotPlugAcceptanceTests.swift`: connect then disconnect before settle → no move, no announcement, stale timer ignored; 20 bounce cycles and 20 settled cycles → zero resources, every slot deallocated (OUT-002-S2) — Verified 2026-11-14: HotPlugAcceptanceTests testAConnectionThatDrops… and testTwentyBouncesAndTwentyCycles… pass

## Phase 4: User Story 3 - Blackout and announcements (P2)

- [X] OUT-002-T08 [US3] Status events X27/X28 and the `display` lane in `Apps/projectM-iOS/Coordinators/StatusEvents.swift` and `AccessibilityAnnouncer.swift`; `onConnectionChange` posts them (T05's wiring file); rows added to `specs/100-acc-011-captioned-status-events/contracts/status-events.md` — Verified 2026-11-14: StatusEventsTests 8 pass, check_status_events OK, validate_docs OK
- [X] OUT-002-T09 [US3] Tests: blacked-out connect is black before the call returns and after settle (OUT-002-S3); X27/X28 texts and lanes; one change per settled connect / disconnect, in `HotPlugAcceptanceTests.swift` — Verified 2026-11-14: HotPlugAcceptanceTests testADisplayConnectingWhileBlackedOut… and testConnectionChanges… pass
- [X] OUT-002-T10 [US3] UI test `Apps/projectM-iOS/UITests/HotPlugUITests.swift` with the DEBUG fake: bounce button (`uitestBounceExternal`) and resource probe (`externalResources`) in `UITestExternalDisplay.swift`; a bounce moves nothing and leaves nothing, a blacked-out connect is black, the source starts once — Verified 2026-11-14: HotPlugUITests passes in 7.3 s on the iOS 27.2 simulator (OUT2)

## Phase 5: Polish

- [X] OUT-002-T11 Regression: `ExternalDisplayCoordinatorTests`, `OutputBlackoutCoordinatorTests`, `StatusEventsTests`, `ExternalDisplayUITests`, `OutputBlackoutUITests`; repo checks (compliance: public APIs only, OUT-002-R9; no new UserDefaults key), iOS 26.5 simulator build, type-check budget (OUT-002-S4) — Verified 2026-11-14: 67 app unit tests (HotPlugAcceptance 7, ExternalDisplayCoordinator 9, OutputBlackoutCoordinator 7, StatusEvents 8, AccessibilityAnnouncer 8, VideoRecordingApp 18, EmergencyBlackout, ShowCoordinator) and ExternalDisplayUITests, OutputBlackoutUITests pass on iOS 27.2; PresentationLifecycle 60 tests; compliance, docs, motion, permission, status-event checks, 153 script tests, privacy manifest and network symbols OK; no new type-check warnings in changed files. The Xcode 26 / iOS SDK 26.5 compile runs in CI only (pending CI)
- [ ] OUT-002-T12 {device} Quickstart B on D1, D2, D3 (cable and AirPlay hot-plug, recording hold, blackout, quick wiggle)

## Analysis (speckit-analyze, 2026-11-14)

No critical issues. Fixed: R3 now says the 0.3 s settle applies in the app (tests may use 0); R9 is mapped to T11. Coverage: R1, R2 → T05, T06; R3 → T04, T07; R4 → T05, T06; R5 → T09; R6 → T08, T09; R7 → T03, T06; R8 → T04, T07; R9 → T11. 12 tasks, 100 % of requirements covered.

## Dependencies

T01 → T04, T05 · T03 → T04, T06 · T04, T05 → T06, T07 · T08 → T09 · T04 → T10 · all → T11.
US2 and US3 depend on US1's coordinator changes; T01/T02 and T08 can run in parallel.

## Implementation strategy

MVP = Phase 1 + US1 (the row's acceptance). Then US2's tests, US3's announcements and UI test, then the regression pass.
