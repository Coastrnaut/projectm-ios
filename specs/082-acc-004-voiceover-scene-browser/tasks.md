# Tasks: ACC-004 VoiceOver Scene Browser

**Input**: `specs/082-acc-004-voiceover-scene-browser/` (spec, plan, research, data-model,
contracts/accessibility-tree.md, quickstart)

**Tests**: requested by the roadmap row (accessibility unit/UI, device last).

Format: `- [ ] ACC-004-Tnn [P?] [Story?] description with path`. Budgets (owner rule 7): unit test
≈1-2 s, each UI test < 30 s.

## Phase 1: Setup

- [X] ACC-004-T01 Own simulator "ACC4 iPhone 17" (iOS 27.2), `xcodegen generate`, preset
  submodules, baseline `build-for-testing` into `.autonomous/derived-data-acc-004`; count
  `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-13: own simulator ACC4 iPhone 17 (iOS 27.2), baseline build-for-testing succeeded; PosterBoard reports 32

## Phase 2: Foundational (announcement path)

- [X] ACC-004-T02 `AnnouncementKind`, `AnnouncementGate` (window "1.0" s, identical repeat "2.0" s;
  data-model.md rules 1-2) and `AccessibilityAnnouncer` (poster, monotonic clock, scheduler, DEBUG
  `lastSpoken` as `"<kind>|<text>"`) in `Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift`. — Verified 2026-11-13: AccessibilityAnnouncerTests 8/8 (projectM-iOSTests 376/376)
- [X] ACC-004-T03 [P] Unit tests `Apps/projectM-iOS/Tests/AccessibilityAnnouncerTests.swift`: single
  submission speaks at once; bursts of 2 and 5 inside a window speak at most 2 with the latest last;
  identical repeat within 2.0 s dropped and allowed after; kinds independent; announcer posts through
  an injected poster with an injected clock and manual scheduler (no wall clock). — Verified 2026-11-13: AccessibilityAnnouncerTests 8/8 in 0.006 s, fake clock and manual scheduler

## Phase 3: User Story 2 — state changes without spam (P1)

**Independent test**: unit tests above plus the probe test in ACC-004-T09.

- [X] ACC-004-T04 [US2] `AppCoordinator.announcer`; preset announcements "Preset: <name>" after
  `next()`, `previous()`, `random()`, `choose(_:from:)` only when the shown preset changed; "Visualization
  paused" / "Visualization resumed" in `togglePause()`; show cues through kind `cue`
  (`Apps/projectM-iOS/Coordinators/AppCoordinator.swift`, `AppCoordinator+Show.swift`). — Verified 2026-11-13: AccessibilityScreensUITests.testUserChangesAreAnnounced (Next → preset|Preset: <name>, Pause/Resume → playback|…); the announcement is posted only from announcingPresetChange (no other path announces a preset: R6)
- [X] ACC-004-T05 [US2] `VisualizerView` `.onChange` of `externalDisplay.isBlackoutRequested` ("Output
  blacked out" / "Output restored"), `videoRecording.state` ("Recording started" / "Recording
  stopped") and `videoRecording.notice`; DEBUG probe `announcementProbe` under `-uitestDiagnostics`
  (`Apps/projectM-iOS/Views/VisualizerView.swift`). — Verified 2026-11-13: testUserChangesAreAnnounced (Black out → output|Output blacked out via the probe); recording path by code review only
- [X] ACC-004-T06 [US2] `PresetCoordinator.toggleFavoriteAnnounced(_:)` ("Added to favorites: <name>" /
  "Removed from favorites: <name>") with an injected announce closure set by AppCoordinator
  (`Apps/projectM-iOS/Coordinators/PresetCoordinator.swift`). — Verified 2026-11-13: build and code review (star and rotor action call toggleFavoriteAnnounced); favorite text covered by AccessibilityAnnouncerTests.testTexts; not driven by a UI test

## Phase 4: User Story 1 — labelled scene cards and rows (P1)

**Independent test**: ACC-004-T08 screens show editor and preset browser.

- [X] ACC-004-T07 [US1] `PresetRow`: `.isSelected` on the current preset, hint "Plays this preset"
  ("Opens the unlock sheet" when locked), rotor action "Add to Favorites" / "Remove from Favorites"
  through `toggleFavoriteAnnounced`, the star too (`Views/PresetBrowserView.swift`); show cue row:
  `.isSelected` when active, rotor actions "Move Up" / "Move Down" (`Views/ShowEditorView.swift`);
  controls hints for Previous, Next, Random, Presets, Black out (`Views/ControlsOverlay.swift`). — Verified 2026-11-13: testSettingsAndShowEditorAreLabelledAndPassTheAudit (cue 1 selected, cues 2-3 not), testPresetBrowserAndPackAreLabelledAndPassTheAudit (row label); rotor actions and hints by code review (XCUITest cannot list custom actions; T12)

## Phase 5: User Story 3 — automated check (P1)

- [X] ACC-004-T08 [US3] `Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift`: shared
  `audit(_ screen:)` (types `.sufficientElementDescription`, `.hitRegion`, `.contrast`, `.dynamicType`,
  `.trait`; per-issue `AuditFilter.entries` with reasons) and `requirePrimaryControls(_:)` (contract
  C2: exists, non-empty label, hittable); tests: controls with show seed; preset browser home + first
  pack; collections + My Presets; Settings + show editor. — Verified 2026-11-13: AccessibilityScreensUITests 7/7 (three consecutive green runs)
- [X] ACC-004-T09 [US3] [US2] Announcement probe test in the same suite: Next → `preset|Preset: …`;
  Pause → `playback|Visualization paused`; Black out → `output|Output blacked out`. — Verified 2026-11-13: testUserChangesAreAnnounced passed (7.3 s)
- [X] ACC-004-T10 [US3] Run the audit, triage every issue: fix app issues in the views, filter only
  system-owned ones with a reason; record the outcome in contract C3 and the spec status. — Verified 2026-11-13: audit issues fixed or filtered with reasons (contracts/accessibility-tree.md C3 outcome); zero unfiltered issues in 3 consecutive runs

## Phase 6: Polish

- [X] ACC-004-T11 Run `projectM-iOSTests`, `AccessibilityScreensUITests` and regression suites
  `ShowCueUITests`, `SceneDuplicateUITests`, `ReduceMotionUITests`, `EmergencyBlackoutUITests`,
  `OutputBlackoutUITests`; scripts `check_compliance`, `validate_docs`, `check_motion_policy`,
  `check_permission_catalog`, `test_scripts`; PosterBoard count after; spec status line. — Verified 2026-11-13: projectM-iOSTests 376/376 (10.6 s); AccessibilityScreensUITests 7/7 (controls 17.5 s, showRow 20.0 s, settings+showEditor 24.0 s, browser+pack 20.0 s, collections+myPresets 13.0 s, scale 10.7 s, announcements 7.3 s); regression ShowCue, SceneDuplicate, ReduceMotion, EmergencyBlackout, OutputBlackout, TapTempo, PresetLibrary, PresetCollections, Settings all pass, UserPresets 1 failure (testImportPlayStepAndRelaunch: the pre-existing tapControl race, 88 s) that passed on rerun (101 s; that suite is being shortened elsewhere): 32 tests, 31 + 1 on rerun; scripts: test_scripts 147 OK, compliance, docs, motion policy, permission catalog OK; PosterBoard reports 32 before and after; own simulator deleted
- [ ] ACC-004-T12 `{device}` VoiceOver pass on D1 (quickstart "Device"): every primary control
  reachable and named, cue and preset rotor actions (including the swipe actions iOS exposes, D4),
  C1 announcements without repeats (ACC-004-S6).

## Dependencies

T01 → T02 → (T03 ∥ T04-T06) → T07 → T08-T10 → T11; T12 after T11 (owner).
US2 and US1 touch different files except AppCoordinator (T04 only) and PresetBrowserView (T07 only).

## Parallel examples

T03 with T04; T05 with T06 (different files).

## Implementation strategy

MVP = T02-T08 (announcer, labels, automated check); then probe test, triage, regression.
