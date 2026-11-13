# Tasks: ACC-001 Reduce Motion Mode

**Input**: Design documents from `specs/080-acc-001-reduce-motion-mode/` (spec, plan, research,
data-model, contracts/motion-policy.md, quickstart)

**Tests**: requested by the roadmap row ("accessibility unit/UI + device LAST stage"). Budgets (owner
rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] ACC-001-T01 Confirm the worktree builds: `git submodule update --init --depth 1 Vendor/presets/*`, `xcodegen generate`, own simulator "ACC1 iPhone 17" (iOS 27.2); count PosterBoard reports before

## Phase 2: Foundational (blocks every story)

- [ ] ACC-001-T02 `MotionPolicy` (decoration, seconds, controls animation and seconds, safetyFade) and `View.reduceMotionAware(_:value:)` in Apps/projectM-iOS/Views/MotionPolicy.swift (contract C1; R2, R4, R7)
- [ ] ACC-001-T03 [P] Unit tests Apps/projectM-iOS/Tests/MotionPolicyTests.swift: reduce on → nil animation and 0 s; off → the animation and 0.2 s; safetyFade unaffected either way; the coordinator's `motion` follows `systemReduceMotionChanged` at once and Reduce flashing still follows when set to "Follow system" (S1, S2, S3)

## Phase 3: User Stories 1 + 2 — Controls without motion; system change applies at once (P1)

**Goal**: the controls and badges transition instantly with Reduce Motion on; a system change applies to the next transition.
**Independent test**: ReduceMotionUITests.

- [ ] ACC-001-T04 [US1] [US2] Apps/projectM-iOS/Coordinators/AppCoordinator.swift: `motion`, `currentSystemReduceMotion()` (DEBUG override `-uitestReduceMotion`), re-read on activation, DEBUG `lastControlsTransitionSeconds` recorded when `controlsVisible` changes, DEBUG `simulateSystemReduceMotionToggle()` (R1, R3, R9)
- [ ] ACC-001-T05 [US1] [US2] Apps/projectM-iOS/Views/VisualizerView.swift: overlay stack through `reduceMotionAware`; remove the visualizer-only observer; DEBUG `motionProbe` and `simulateReduceMotionToggle`; Apps/projectM-iOS/ProjectMApp.swift: root observer (R2, R3, R8, R9)
- [ ] ACC-001-T06 [US1] [US2] UI test Apps/projectM-iOS/UITests/ReduceMotionUITests.swift: launch with Reduce Motion on; show/hide controls → `controls=0.00`; open and close Settings; simulate the system toggle → `reduce=off`, next transition `controls=0.20`; toggle back → `0.00`; `visualRunning` stays yes (S1, S2, S4; < 30 s)
- [ ] ACC-001-T07 [US2] Try the real simulator path (`xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool YES` with the app running, read `motionProbe`); record the result in research D5

## Phase 4: User Story 3 — Safety fades and the visualization stay (P2)

- [ ] ACC-001-T08 [US3] Apps/projectM-iOS/Visuals/RenderPlaceholder.swift: mark the 0.5 s fade with `MotionPolicy.safetyFade`; confirm OUT-010's restore fade reads only Reduce flashing (R4, R5)
- [ ] ACC-001-T09 [P] Static check scripts/check_motion_policy.py and `MotionPolicyCheckTests` in scripts/test_scripts.py (flags a bare `withAnimation`/`.animation(`/`UIView.animate`; passes policy and safety lines, comments, tests; the real tree is clean) (R7, S5)

## Phase 5: Polish

- [ ] ACC-001-T10 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`
- [ ] ACC-001-T11 Run projectM-iOSTests, ReduceMotionUITests, NativeVisualUITests, SettingsUITests, EmergencyBlackoutUITests, GuidedFirstSceneUITests on the own simulator; count PosterBoard reports after; delete the simulator; record results in spec Status
- [ ] ACC-001-T12 {device} On D1: toggle Reduce Motion while the app runs; controls transition changes at once; VoiceOver behavior unchanged (quickstart Scenario 3; S6) — open, needs the owner

## Dependencies

T01 → T02 → (T03, T04) → T05 → T06, T07; T08 and T09 after T02; T10, T11 last; T12 after integration.
