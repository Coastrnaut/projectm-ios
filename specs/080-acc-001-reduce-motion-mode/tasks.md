# Tasks: ACC-001 Reduce Motion Mode

**Input**: Design documents from `specs/080-acc-001-reduce-motion-mode/` (spec, plan, research,
data-model, contracts/motion-policy.md, quickstart)

**Tests**: requested by the roadmap row ("accessibility unit/UI + device LAST stage"). Budgets (owner
rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] ACC-001-T01 Confirm the worktree builds: `git submodule update --init --depth 1 Vendor/presets/*`, `xcodegen generate`, own simulator "ACC1 iPhone 17" (iOS 27.2); count PosterBoard reports before — Verified 2026-11-13: preset submodules initialized, `xcodegen generate`, own simulator ACC1 iPhone 17 (iOS 27.2) created; PosterBoard reports 32 before

## Phase 2: Foundational (blocks every story)

- [X] ACC-001-T02 `MotionPolicy` (decoration, seconds, controls animation and seconds, safetyFade) and `View.reduceMotionAware(_:value:)` in Apps/projectM-iOS/Views/MotionPolicy.swift (contract C1; R2, R4, R7) — Verified 2026-11-13: build-for-testing on ACC1 iPhone 17 succeeded with no new warnings; MotionPolicyTests 5/5
- [X] ACC-001-T03 [P] Unit tests Apps/projectM-iOS/Tests/MotionPolicyTests.swift: reduce on → nil animation and 0 s; off → the animation and 0.2 s; safetyFade unaffected either way; the coordinator's `motion` follows `systemReduceMotionChanged` at once and Reduce flashing still follows when set to "Follow system" (S1, S2, S3) — Verified 2026-11-13: MotionPolicyTests 5/5 (0.008 s total) on ACC1 iPhone 17

## Phase 3: User Stories 1 + 2 — Controls without motion; system change applies at once (P1)

**Goal**: the controls and badges transition instantly with Reduce Motion on; a system change applies to the next transition.
**Independent test**: ReduceMotionUITests.

- [X] ACC-001-T04 [US1] [US2] Apps/projectM-iOS/Coordinators/AppCoordinator.swift: `motion`, `currentSystemReduceMotion()` (DEBUG override `-uitestReduceMotion`), re-read on activation, DEBUG `lastControlsTransitionSeconds` recorded when `controlsVisible` changes, DEBUG `simulateSystemReduceMotionToggle()` (R1, R3, R9) — Verified 2026-11-13: ReduceMotionUITests 1/1 (18.2 s): probe follows the simulated toggle through `syncSystemReduceMotion`; build clean
- [X] ACC-001-T05 [US1] [US2] Apps/projectM-iOS/Views/VisualizerView.swift: overlay stack through `reduceMotionAware`; remove the visualizer-only observer; DEBUG `motionProbe` and `simulateReduceMotionToggle`; Apps/projectM-iOS/ProjectMApp.swift: root observer (R2, R3, R8, R9) — Verified 2026-11-13: ReduceMotionUITests 1/1 (18.2 s); `python3 scripts/check_motion_policy.py` OK (overlay goes through `reduceMotionAware`)
- [X] ACC-001-T06 [US1] [US2] UI test Apps/projectM-iOS/UITests/ReduceMotionUITests.swift: launch with Reduce Motion on; show/hide controls → `controls=0.00`; open and close Settings; simulate the system toggle → `reduce=off`, next transition `controls=0.20`; toggle back → `0.00`; `visualRunning` stays yes; the controls' identifiers (`settings`, `stop`, `pauseResume`) exist in both states (S1, S2, S4, R8; < 30 s) — Verified 2026-11-13: ReduceMotionUITests 1/1 (18.2 s) on ACC1 iPhone 17
- [X] ACC-001-T07 [US2] Try the real simulator path (`xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool YES` with the app running, read `motionProbe`); record the result in research D5 — Verified 2026-11-13: real `simctl spawn … defaults write com.apple.Accessibility ReduceMotionEnabled` flipped the running app's probe both ways at once (screenshots); recorded in research D5

## Phase 4: User Story 3 — Safety fades and the visualization stay (P2)

- [X] ACC-001-T08 [US3] Apps/projectM-iOS/Visuals/RenderPlaceholder.swift: mark the 0.5 s fade with `MotionPolicy.safetyFade`; confirm OUT-010's restore fade reads only Reduce flashing (R4, R5) — Verified 2026-11-13: MotionPolicyTests.testSafetyFadeIsNeverShortened; OUT-010's restore fade reads only `reduceFlashing` (AppCoordinator `externalDisplay.reduceFlashing`, unchanged)
- [X] ACC-001-T09 [P] Static check scripts/check_motion_policy.py and `MotionPolicyCheckTests` in scripts/test_scripts.py (flags a bare `withAnimation`/`.animation(`/`UIView.animate`; passes policy and safety lines, comments, tests; the real tree is clean) (R7, S5) — Verified 2026-11-13: `python3 scripts/test_scripts.py` 138 tests OK (MotionPolicyCheckTests 4/4, 0.019 s); `python3 scripts/check_motion_policy.py` OK

## Phase 5: Polish

- [X] ACC-001-T10 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` — Verified 2026-11-13: check_compliance OK, validate_docs OK, test_scripts 138 OK (1 skipped), check_motion_policy OK
- [X] ACC-001-T11 Run projectM-iOSTests, ReduceMotionUITests, NativeVisualUITests, SettingsUITests, EmergencyBlackoutUITests, GuidedFirstSceneUITests on the own simulator; count PosterBoard reports after; delete the simulator; record results in spec Status — Verified 2026-11-13: one xcodebuild test run on ACC1 iPhone 17 (281 s): projectM-iOSTests 351/351 (14.1 s), ReduceMotionUITests 1/1 (9.1 s), NativeVisualUITests 4/4 (8.9-17.7 s), SettingsUITests 4/4 (13.9-27.3 s), EmergencyBlackoutUITests 2/2 (14.0, 14.4 s), GuidedFirstSceneUITests 4/4 (11.5-21.2 s); PosterBoard reports 32 after; simulator deleted
- [ ] ACC-001-T12 {device} On D1: toggle Reduce Motion while the app runs; controls transition changes at once; VoiceOver behavior unchanged (quickstart Scenario 3; S6) — open, needs the owner

## Dependencies

T01 → T02 → (T03, T04) → T05 → T06, T07; T08 and T09 after T02; T10, T11 last; T12 after integration.

## Analysis (speckit-analyze, 2026-11-13)

| ID | Severity | Finding | Fix |
|---|---|---|---|
| AN1 | Medium | research D6 and contract C1 stated the check's pass rule differently (`MotionPolicy.safetyFade(` vs `MotionPolicy.`) and D6 omitted `UIView.animate`. | D6 now cites C1's rule. |
| AN2 | Medium | R8 (identical text and identifiers) had no test. | T06 asserts the controls' identifiers in both states. |
| AN3 | Low | R6 (system presentations unchanged) has no implementation task. | Intended: it requires no change; T06 opens and closes the Settings sheet as before and the static check keeps custom presentation animation out. |
| AN4 | Low | R5 (content keeps running) relies on `visualRunning`. | T06 checks it before and after the toggle. |

Coverage: R1 T04; R2 T02 T05 T06; R3 T04 T05 T06 T07; R4 T03 T08; R5 T06 T08; R6 AN3; R7 T02 T09;
R8 T06; R9 T04 T05 T06. S1-S5 T03 T06 T09; S6 T12. No constitution conflicts; no unmapped tasks.
