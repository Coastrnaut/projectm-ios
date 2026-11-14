# Tasks: ACC-011 Captioned Status Events

**Input**: Design documents from `specs/100-acc-011-captioned-status-events/` (spec, plan, research,
data-model, contracts/status-events.md, quickstart)

**Tests**: requested by the roadmap row (accessibility unit and UI tests) and the spec (S1-S4). Owner rule
7 budgets: unit test ≤ 10 s, UI test < 30 s.

## Phase 1: Setup

- [X] ACC-011-T01 Generate the project and an own simulator: `xcodegen generate`, presets submodules, `xcrun simctl create "ACC11 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2`; count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before runs — Verified 2026-11-14: project generated, presets initialized, own simulator ACC11 iPhone 17 (iOS 27.2) created; PosterBoard reports 25 before

## Phase 2: Foundational (blocks all stories)

- [X] ACC-011-T02 Add kinds `source, route, background, capture, camera, osc, session` to `AnnouncementKind` in `Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift` — Verified 2026-11-14: build-for-testing exit 0; StatusEventsTests.testKindsAreIndependent
- [X] ACC-011-T03 Create `StatusEvent`, `StatusCause`, `StatusPresentation`, `StatusEventCatalog` (rows X1-X26 of contract C1, exhaustive switches, no `default:`; "`announcement` non-empty unless `presentation == .systemPresented`") and `StatusEventRouter` (owns the announcer; `post(_:)`; system rows dropped while inactive; `.caption` → `caption` for 4 s, replaced by a newer one) in `Apps/projectM-iOS/Coordinators/StatusEvents.swift` — Verified 2026-11-14: StatusEventsTests (8/8) incl. testTheTransitionTableWalk over X1-X26 and X14a
- [X] ACC-011-T04 Make `AppCoordinator.announcer` an alias of `statusEvents.announcer`, add `let statusEvents`, and create `Apps/projectM-iOS/Coordinators/AppCoordinator+StatusEvents.swift` (`announceSourceStatus()`, router `isActive` from `appIsActive`, route and repair announce closures) — Verified 2026-11-14: build exit 0; AccessibilityScreensUITests.testUserChangesAreAnnounced passes through the alias; projectM-iOSTests 438/438

## Phase 3: User Story 1 — Hear every change, without spam (P1)

**Goal**: every capture and recording change is announced once through the gate.
**Independent test**: `StatusEventsTests` table walk; `StatusEventsUITests` reads `announcementProbe`.

- [X] ACC-011-T05 [US1] Source: replace the `manager.state` and `manager.stopReason` direct posts in `Apps/projectM-iOS/Views/VisualizerView.swift` with `coordinator.announceSourceStatus()` (X1-X3, one text per change); remove `SourceStatusIndicator.announce` from `Apps/projectM-iOS/Views/SourceStatusIndicator.swift` — Verified 2026-11-14: StatusEventsUITests.testSourceChangesAreSpokenAsShown; StatusUITests 8/8; check_status_events OK
- [X] ACC-011-T06 [US1] Recording and frame capture: post X6-X14 from `VisualizerView` `.onChange`s (recording state, recording notice, frame notice, `frameCapture.offered`, `videoRecording.offered`, `captureShare.notice`) — Verified 2026-11-14: VideoRecordingUITests 2/2, FrameCaptureUITests 2/2; table walk X6-X14a
- [X] ACC-011-T07 [US1] Camera, OSC, background, route, recovery, repair: route the direct posts in `AppCoordinator.swift` (camera stop, camera notice, camera on X16, "Last scene reopened."), `OSCListenerBadge.swift`, `BackgroundNoticeView.swift`, `SessionRecoveryOfferCard.swift`, `RouteCoordinator.swift`, `SceneRepairCoordinator.swift` through the router; add `.onChange(of: osc.badgePort)` (X19) in `Apps/projectM-iOS/ProjectMApp.swift` `RootView` — Verified 2026-11-14: OSCNetworkAccessUITests, CameraPrivacyStatusUITests, BackgroundPolicyUITests, RouteIndicatorUITests, SceneRepairUITests pass; RouteCoordinatorTests 5/5; check_status_events OK
- [X] ACC-011-T08 [US1] Blackout by phase (X21-X23) in `VisualizerView` replacing the `isBlackoutRequested` `.onChange` — Verified 2026-11-14: StatusEventsUITests.testRestoredOutputIsCaptioned; OutputBlackoutUITests pass
- [X] ACC-011-T09 [P] [US1] Unit tests `Apps/projectM-iOS/Tests/StatusEventsTests.swift`: table walk with a fake clock, a fake sink and a manual scheduler (visible text and announcement per transition), burst rule (S3), identical-drop for hold vs status (R5), background suppression (R10) — Verified 2026-11-14: StatusEventsTests 8/8 in 0.03 s

## Phase 4: User Story 2 — See every change as text (P1)

**Goal**: end states without persistent text show a 4 s caption.
**Independent test**: restore the output → `statusCaption` "Output restored".

- [X] ACC-011-T10 [US2] `Apps/projectM-iOS/Views/StatusCaptionView.swift` (static text, identifier `statusCaption`, wraps, no animation) placed in the visualizer's top status stack (`VisualizerView.swift`) and the chooser's top inset (`ProjectMApp.swift`) — Verified 2026-11-14: StatusEventsUITests.testRestoredOutputIsCaptioned reads statusCaption "Output restored" and sees it go
- [X] ACC-011-T11 [US2] Caption tests in `StatusEventsTests` (caption set for C rows, cleared after 4 s on the manual scheduler, replaced by a newer caption, never for P rows) — Verified 2026-11-14: StatusEventsTests.testCaptionsShowForFourSecondsAndANewerOneReplacesThem

## Phase 5: User Story 3 — A new state cannot ship silent (P1)

**Goal**: completeness enforced by compiler, test and script.

- [X] ACC-011-T12 [US3] Completeness test `testEveryStateHasARow` in `StatusEventsTests` over `AudioState.allCases`, an exhaustive `StopReason` list, `VideoRecordingCoordinator.State.allCases`, `RecordingStopReason.allCases`, `RecordingRefusal.allCases`, an exhaustive `RecordingFailure` list, `CameraFeedState.allStatusCases`, `OutputBlackout.Phase` cases — Verified 2026-11-14: StatusEventsTests.testEveryStateHasARow (passes; catalog switches have no default:)
- [X] ACC-011-T13 [P] [US3] `scripts/check_status_events.py` (contract C2) and its tests in `scripts/test_scripts.py` — Verified 2026-11-14: python3 scripts/check_status_events.py OK; test_scripts.py 151 tests OK (StatusEventsCheckTests 4)

## Phase 6: Polish and verification

- [X] ACC-011-T14 UI test `Apps/projectM-iOS/UITests/StatusEventsUITests.swift` (`-uitestFake inAppPlayback`, `-uitestDiagnostics`): waiting → active → interrupted with hold text; Black out → restored with caption; each < 30 s — Verified 2026-11-14: StatusEventsUITests 2/2 (6.8 s, 11.0 s)
- [X] ACC-011-T15 Run the scripts (compliance, docs, motion policy, permission catalog, status events, test_scripts) and the simulator suites: projectM-iOSTests, StatusUITests, AccessibilityScreensUITests, StatusEventsUITests, VideoRecordingUITests, FrameCaptureUITests; PosterBoard count after; delete the simulator; confirm ACC-011-R8 with `git diff --stat main -- Packages/CaptureUI specs/*/contracts/ui-strings*` (empty) — Verified 2026-11-14: scripts all OK; projectM-iOSTests 438/438; 5 UI suites + 7 touched suites pass (2 AccessibilityScreens audit tests failed once on an elementless contrast issue over the live visual and passed 2/2 on rerun); PosterBoard 25 after (no new); simulator deleted; Packages and ui-strings contracts unchanged since 82d23496
- [X] ACC-011-T16 Update the spec status in `spec.md` (results, open device task) and record there that ACC-004's "other features' one-shot announcements still post directly" note is resolved for capture and recording statuses — Verified 2026-11-14: spec.md Status updated
- [ ] ACC-011-T17 `{device}` VoiceOver pass on D1 (quickstart C) — left open, needs a person

## Dependencies

T01 → T02 → T03 → T04 → (T05-T08, T10) → T09, T11, T12 → T14 → T15 → T16. T13 is independent. T17 last.

## Parallel opportunities

T09 and T13 can be written alongside T05-T08 (different files).

## Implementation strategy

MVP is US1 (announcements through the router). US2 and US3 follow in the same branch; all P1.
