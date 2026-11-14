# Tasks: XFADE Cue Transitions On Screen

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Compositor

- [X] XFADE-T01 `FrozenOutputFrame`, `OutputTransitionPass` and the `Compositor` freeze, begin, end and output hook (XFADE-R2, R3, R4, R5, R6, R7) — Verified 2026-11-14: Compositor `swift test` 518 tests, 7 skipped (pre-existing), 0 failures, 71 s; Linux shape `swift build -Xswiftc -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` OK
- [X] XFADE-T02 GPU acceptance: red/blue 1 s linear crossfade at 0, 0.5 and 1 s; easeIn; dip to black (XFADE-S1) — Verified 2026-11-14: `OutputTransitionTests.testCrossfadeFromAFrozenFrameReachesExactStartMidpointAndEnd` (t = 0 A byte for byte, 0.5 s (0.5, 0, 0.5, 1) ± 0.002, 1 s B byte for byte, 59 blends), `testEaseInCurveShapesTheMix`, `testDipToBlackPassesThroughBlackAtTheMidpoint`
- [X] XFADE-T03 GPU tests: cut byte-identical, Reduce Motion, restart from the blended frame, 20 transitions without leaks, flash guard on strobing transitions, capture and recording output see the blend, freeze across compositors (XFADE-S2, S3, S4) — Verified 2026-11-14: `OutputTransitionTests` 9 tests, 0.72 s (cut and Reduce Motion byte-identical; restart from the blend; 20 transitions: idle 2, peak 4, after 2; strobe minimum gain 0.095; `encodeOutput` shows the blend; the acceptance freezes on a second queue). Frame capture uses the same shown texture (not separately tested)

## Phase 2: App

- [X] XFADE-T04 `CompositorVisualHost` on the four compositor hosts; `CueTransitionStage` replaces the recorder; AppCoordinator wiring (XFADE-R1, R8) — Verified 2026-11-14: build-for-testing on XFADE (iOS 27.2) exit 0, no type-check warnings in touched app files; ShowCoordinatorTests 8, CueTransitionAcceptanceTests 3 pass
- [X] XFADE-T05 App test: a cue with a stored 1 s crossfade through ShowCoordinator drives the incoming compositor for 59 blended frames at 60 Hz; cut and unsupported outcomes (XFADE-S5) — Verified 2026-11-14: `CueTransitionStageTests` 2 tests on XFADE (0.12 s): 59 blends, 60 transition frames, textures released; Reduce Motion cut takes no texture; unsupported returns the frozen frame
- [X] XFADE-T06 DEBUG seed and probe; UI test under 30 s (XFADE-R9, S6) — Verified 2026-11-14: `CueTransitionUITests.testACueCrossfadeShowsOnScreen` on XFADE, 7.5 s and 9.5 s; regressions `testACueTransitionPersistsAcrossARelaunch`, `ShowCueUITests` (2), `TextOverlayUITests` pass

## Phase 3: Polish

- [X] XFADE-T07 Repo checks, type-check budget, privacy manifest and network symbols — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK; check_network_symbols OK
- [X] XFADE-T08 Spec status, SCN-007 follow-up note, PosterBoard counts — Verified 2026-11-14: spec Status and the SCN-007 status note updated; PosterBoard reports 25 before, 25 after

## Dependencies

T01 → T02, T03, T04. T04 → T05, T06. All → T07 → T08.
