# Tasks: UIX-001 Guided First Scene

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/guided-first-scene.md](contracts/guided-first-scene.md)

Budgets (owner rule 7): unit tests about 1-2 s each, UI tests under 30 s each. `{device}` tasks need
the owner's device and stay open until run.

## Phase 1: Foundation

- [X] UIX-001-T01 Pure flow and state `Apps/projectM-iOS/Coordinators/GuidedFirstScene.swift`:
  `GuidedFirstSceneStep` (5 steps), `GuidedVisual`, `GuidedFirstSceneDraft`, `GuidedFirstSceneFlow`
  (next, back, canGoBack, isLast), `GuidedFirstSceneState` (raw values, unknown → absent), the launch
  rule and the DEBUG suppression rule (UIX-001-R1-R4, R7, R13; data-model). — Verified 2026-11-13: GuidedFirstSceneFlowTests 5/5 pass (iOS 27.2 simulator, 0.001 s).
- [X] UIX-001-T02 `GuidedFirstSceneCoordinator` in the same file: UserDefaults store of
  `guide.firstScene`, `noticeAcknowledged()`, `presentAtLaunchIfDue(recoveryPending:)`, `open()`,
  `skip()`, `finish()` (UIX-001-R1, R5-R8; contract G3). — Verified 2026-11-13: GuidedFirstSceneCoordinatorTests 6/6 pass (0.019 s).
- [X] UIX-001-T03 Unit tests `Apps/projectM-iOS/Tests/GuidedFirstSceneTests.swift` for T01-T02: step
  order and bounds, Back keeps the draft, skip and finish write the state and close, pending survives
  a relaunch, finished/skipped never offered, absent never offered, recovery pending blocks, harness
  suppression and `-uitestGuidedFirstScene`, re-open resets the draft, unknown stored value. — Verified 2026-11-13: GuidedFirstSceneFlowTests 5/5 and GuidedFirstSceneCoordinatorTests 6/6 pass.

## Phase 2: US1 + US2 — make a first scene; skip (P1)

- [X] UIX-001-T04 `AppCoordinator`: `guide` property, `-uitestResetNotice` removes the key, the notice
  acknowledgement offers the tutorial, launch offer after PERF-010's decision;
  `AppCoordinator+Guide.swift`: `finishGuidedFirstScene()` (apply visual and look, `commitNow()`,
  reference track only from the chooser) and the static apply used by tests (UIX-001-R1, R5, R9, R10;
  research D4, D5). — Verified 2026-11-13: GuidedFirstSceneUITests testNewUserFinishesOfflineAndTheSceneIsKept passes (sourceStarts 1, visualRunning yes, sceneAutosave committed, osc=off, restored=main after relaunch).
- [X] UIX-001-T05 `Apps/projectM-iOS/Views/GuidedFirstSceneView.swift`: the five steps, identifiers per
  contract G1, headings, labels, selected traits, scrolling content with buttons reachable at
  accessibility sizes, no animation, modal to VoiceOver; RootView overlay (UIX-001-R2-R4, R11, R12;
  research D1, D6). — Verified 2026-11-13: GuidedFirstSceneUITests 4/4 pass (identifiers per G1, Circular preselected with the selected trait, steps in order).
- [X] UIX-001-T06 Unit tests in `GuidedFirstSceneTests` for the apply: each visual maps to its
  `VisualChoice`, glow only for the spectra, the Text message through the sanitizer, nothing else in
  the settings (OSC, Camera) changes. — Verified 2026-11-13: testPlayAppliesOnlyTheVisualAndItsLook passes (visual, glow, sanitized message; OSC, bars, overlay unchanged).
- [X] UIX-001-T07 UI test `Apps/projectM-iOS/UITests/GuidedFirstSceneUITests.swift`
  `testNewUserFinishesOfflineAndTheSceneIsKept` (UIX-001-S1, S2, S6; quickstart B1). — Verified 2026-11-13: passes in 22.1 s.
- [X] UIX-001-T08 UI test `testSkipChangesNothingAndNeverReturns` (UIX-001-S2, S3; quickstart B2). — Verified 2026-11-13: testSkipChangesNothingAndNeverReturns passes in 11.1 s.

## Phase 3: US3 — re-open from Settings (P2)

- [X] UIX-001-T09 Settings row "Guided first scene" (`guidedFirstSceneButton`) and
  `AppCoordinator.openGuidedFirstScene()` (closes Settings, opens the tutorial); finishing over the
  running visualizer keeps the source (UIX-001-R8; contract G3). — Verified 2026-11-13: testReopenFromSettingsKeepsTheRunningSource passes in 25.3 s (linear spectrum shown, sourceStarts stays 1).

## Phase 4: US4 — accessibility (P2)

- [X] UIX-001-T10 UI test `testEveryPrimaryButtonIsReachableAtTheLargestTextSize` at
  `UICTContentSizeCategoryAccessibilityXXXL` (UIX-001-S4; quickstart B3). — Verified 2026-11-13: passes in 17.9 s at UICTContentSizeCategoryAccessibilityXXXL (every step's Next/Play revealed and tapped; Play and Skip hittable).

## Phase 5: Polish and evidence

- [X] UIX-001-T11 Regression: app unit tests and NativeVisualUITests, SessionRecoveryUITests,
  SettingsUITests pass unchanged (UIX-001-S5). — Verified 2026-11-13: projectM-iOSTests 335/335 pass; NativeVisualUITests 4/4, SessionRecoveryUITests 3/3, SettingsUITests 4/4 pass (one run, 5 min 27 s).
- [X] UIX-001-T12 `docs/privacy-policy.md`: the stored tutorial state (UIX-001-R14). — Verified 2026-11-13: docs/privacy-policy.md lists the tutorial state; validate_docs OK.
- [X] UIX-001-T13 Checks: `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py` on the
  built Debug app; PosterBoard report count before and after the simulator runs. — Verified 2026-11-13: check_compliance OK, validate_docs OK (682 files), check_privacy_manifest OK on the Debug simulator app; PosterBoard reports 32 before and 32 after.
- [ ] UIX-001-T14 `{device}` D1, fresh install, Airplane Mode on: finish the tutorial and Play with no
  sign-in, network or permission prompt; VoiceOver pass over all five steps (quickstart D).

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06-T10; T11-T13 after T10; T14 owner.

## Analysis (speckit-analyze, 2026-11-13)

Every requirement maps to a task: R1 T01/T02/T04, R2-R4 T01/T05, R5 T04/T07, R6 T02/T08, R7 T02/T03,
R8 T09, R9-R10 T04/T07, R11-R12 T05/T10, R13 T01/T03, R14 T12; every success criterion to a test
(S1/S2/S6 T07, S3 T08, S4 T10, S5 T11). No constitution conflict, no ADR needed (no default
overridden). Fixed: research D3 no longer states a suite count it did not measure; the S1 tap count
starts after the notice (the notice's own tap is FR-071's, not the tutorial's).
