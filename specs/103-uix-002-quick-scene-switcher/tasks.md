# Tasks: UIX-002 Quick Scene Switcher

**Input**: `specs/103-uix-002-quick-scene-switcher/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (UIX-002-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), UI tests under 30 s each, any single xcodebuild run under 10 minutes. Simulator results
are never device evidence. Never use the Simulator panel tool (owner rule 8).

## Phase 1: Setup

- [ ] UIX-002-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "UIX2 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] UIX-002-T02 [P] `SceneSwitcherEntry` (`cueID`, `number`, `label`, `sceneName` "nil when unreadable or equal to the label", `isActive`, `isMissing`; `entries(list:sceneNames:unreadable:)` in show order) and `SceneSwitcherFilter` (`fold` with case, diacritic and width insensitivity, `nil` locale; trimmed query; empty → all in show order; contains on label or scene name; rank 0 for a prefix or word-start match, rank 1 otherwise; stable by number) in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift`
- [ ] UIX-002-T03 [P] `SceneSwitchLatencyProbe` (injected `now: () -> Double`; `budget` 0.250 s; `begin(sceneID:cueID:now:)` replaces a pending one; `finish(_:now:)` → nil without pending; outcomes `applied`, `repairShown`, `failed`) and `SceneSwitchMeasurement` (`milliseconds` rounded to 0.1, `withinBudget` = seconds ≤ budget, `probeText` "<outcome>|<sceneID>|<ms>|<ok|over>" with POSIX formatting) in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift`
- [ ] UIX-002-T04 `SceneSwitcherModel` (`@MainActor @Observable`: `isOpen`, `query`, `highlightedCueID`, `abandonedQuery`, `focusReturnRevision`, `probe`; `open`, `queryChanged`, `moveHighlight(by:)` clamped without wrap, `close(chose:)` per data-model transitions and UIX-002-R5, R6) in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift`
- [ ] UIX-002-T05 Unit tests in `Apps/projectM-iOS/Tests/SceneSwitcherTests.swift`: filter case ("DRO"/"dro"), diacritics ("Café" by "cafe", "Ünder" by "under"), width, empty and whitespace query, scene-name match, ordering (prefix and word-start before contains; show order within a rank), entries (name equal to label → nil, missing, active); highlight rules (open on active, kept while matching, first when not, nil when none, clamped moves); reopen (abandoned query restored, cleared after a choice, revision bumped); probe with a fake clock (applied 0.120 s → "applied|…|120.0|ok", over budget → "over", finish without begin → nil, a second begin replaces); 256-entry filter < 5 ms on the monotonic clock (UIX-002-S4, S6)

## Phase 3: User Story 1 - Find and recall a scene by typing (P1) — MVP

**Independent test**: seeded show; open, type "dr", Return; `showAppliedScene` shows scene 3 and the probe reads `applied|…|ok`.

- [ ] UIX-002-T06 [US1] `AnnouncementKind.search`, `sceneSwitcherCountText(_:)` ("1 scene", "N scenes", "No matching scenes") and `sceneChosenText(_:)` ("Scene: <label>") in `Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift`
- [ ] UIX-002-T07 [US1] `let sceneSwitcher = SceneSwitcherModel()` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; `AppCoordinator+SceneSwitcher.swift` with `sceneSwitcherEntries`, `openSceneSwitcher()`, `closeSceneSwitcher()`, `toggleSceneSwitcher()`, `switcherQueryChanged()`, `moveSwitcherHighlight(by:)`, `chooseSwitcherScene(_:)` and `chooseHighlightedSwitcherScene()` per contract C3; a close without a choice also calls `showControls()` (UIX-002-R11); open is a no-op without cues or while Settings is shown (spec Edge Cases) in `Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSwitcher.swift`
- [ ] UIX-002-T08 [US1] Probe end points in `connectShow()` (`applyScene` → `finish(.applied)` after `applyShowScene`; `requestRepair` → `finish(.repairShown)` before `present`) in `Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift`
- [ ] UIX-002-T09 [US1] The card per contract C1 (backdrop, header, field with `@FocusState`, `.onKeyPress` Up/Down/Escape, `.onSubmit`, count, lazy entry list in a `ScrollViewReader`, max width 480, DEBUG `sceneSwitcherProbe`) in `Apps/projectM-iOS/Views/SceneSwitcherView.swift`
- [ ] UIX-002-T10 [US1] Scenes button in `ShowCueRow`, ⌘K in `ShowKeyCommands` and its arrow and Page keys off while open, in `Apps/projectM-iOS/Views/ShowControls.swift`; the overlay in the visualizer's `ZStack` and `SceneHistoryKeyCommands` off while open in `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] UIX-002-T11 [US1] UI test `testTypeFilterAndRecallWithinBudget` in `Apps/projectM-iOS/UITests/SceneSwitcherUITests.swift` (`-uitestShowSeed`): open with the Scenes button, field `hasKeyboardFocus`, all five entries, entry 1 (active) selected; Down Arrow selects entry 2 with the field still focused (US1 scenario 4); type "dr": one entry "Drop", focus kept; Down Arrow keeps it; Return → switcher gone, `showAppliedScene` = scene 3 | circularSpectrum, `sceneSwitcherProbe` starts with `applied|<scene 3>|` and ends `|ok` (UIX-002-S1, S2)

## Phase 4: User Story 2 - Search keeps its focus state (P1)

**Independent test**: type, narrow, widen; focus and text after every change; Escape; ⌘K reopens with the query.

- [ ] UIX-002-T12 [US2] UI test `testTypingKeepsFocusTextAndRestoresAnAbandonedQuery` in `Apps/projectM-iOS/UITests/SceneSwitcherUITests.swift`: ⌘K opens; type "b" (Build, Break), "r" (both), "e" (Break only), delete (both again): after each change the field has keyboard focus and its value equals the typed text, the count matches; Escape closes; ⌘K reopens with "br" and focus; a choice by tap on "Build" applies scene 2; ⌘K reopens empty (UIX-002-S3)

## Phase 5: User Story 3 - Problem scenes still show the repair report (P1)

- [ ] UIX-002-T13 [US3] UI test `testAProblemSceneShowsTheRepairReport` in `Apps/projectM-iOS/UITests/SceneSwitcherUITests.swift` (`-uitestShowRepairSeed`): open, type "brok", Return → switcher gone, `sceneRepairStatus` "Opens with problems", `showAppliedScene` still scene 1, probe `repairShown|<scene 2>|…|ok`; Close leaves scene 1 (UIX-002-S5)

## Phase 6: User Story 4 - Accessible switcher (P2)

- [ ] UIX-002-T14 [US4] Count announcement (kind `search`) on each query change, "Scene: <label>" (kind `cue`) after an applied choice, entry labels, values and the Selected trait, VoiceOver focus back to the Scenes button after a close without a choice (`@AccessibilityFocusState` on `focusReturnRevision`) in `Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSwitcher.swift`, `Apps/projectM-iOS/Views/SceneSwitcherView.swift`, `Apps/projectM-iOS/Views/ShowControls.swift`; unit test of the announcements with a recording announcer in `Apps/projectM-iOS/Tests/SceneSwitcherTests.swift`
- [ ] UIX-002-T15 [US4] UI test `testLargestTextSizeKeepsTheCardUsable` in `Apps/projectM-iOS/UITests/SceneSwitcherUITests.swift` (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`): the card, field and Close lie inside the window, the entry for "Finale" can be revealed and chosen; after typing "b" `announcementProbe` reads `search|2 scenes` (no announcement on open, research UIX-002-D6) (UIX-002-R9, R10)

## Phase 7: Polish & Cross-Cutting

- [ ] UIX-002-T16 Add `Views/SceneSwitcherView.swift` to `CHECKED` in `scripts/check_status_events.py`; confirm no new stored keys (`AppSettings.allKeys` unchanged, UIX-002-R12); run `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` and `test_scripts`
- [ ] UIX-002-T17 Run `projectM-iOSTests`, `SceneSwitcherUITests`, `ShowCueUITests` and `SceneRepairUITests` on "UIX2 iPhone 17"; record counts and durations; count PosterBoard reports after; delete the simulator
- [ ] UIX-002-T18 Spec status, tasks ticked with evidence, the measured simulator latencies recorded in `specs/103-uix-002-quick-scene-switcher/spec.md`

## Dependencies

- T01 → all. T02, T03 in parallel → T04 → T05.
- US1 (T06-T11) needs Phase 2. US2 (T12) and US3 (T13) need US1's UI. US4 (T14-T15) needs US1.
- Polish after all stories.

## Parallel examples

- T02 and T03 (separate types in one new file, written in one pass).
- T11, T12, T13, T15 live in one UI test file but are independent tests.

## Implementation strategy

MVP = Phase 2 + US1 (open, filter, recall with a measured latency). US2's focus rules and US3's
repair path are verified on top of the same code; US4 adds announcements and the large-text check.
