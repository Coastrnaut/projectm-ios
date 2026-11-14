# Tasks: CMP-014 Compositor Transition Bus

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/transition-bus.md](contracts/transition-bus.md), [quickstart.md](quickstart.md)

Task IDs carry the roadmap ID (`CMP-014-T01…`). Tests are requested by the row (unit tests, snapshots,
GPU performance). Budgets (owner rule 7): a unit test about 1–2 s and at most 10 s; package suite under
1 minute.

## Phase 1: Setup

- [X] CMP-014-T01 Confirm the baseline: `swift test --package-path Packages/Compositor` passes before any change (log in `.autonomous/logs/CMP-014/`). — Verified 2026-11-14: `swift test --package-path Packages/Compositor` 359 tests, 6 skipped, 0 failures before any change

## Phase 2: Foundational

- [X] CMP-014-T02 Add the plain-Swift model in `Packages/Compositor/Sources/Compositor/SceneTransition.swift`: `SceneTransitionStyle` (cut, crossfade, dipToBlack), `SceneTransitionEasing` (linear, easeInOut "t²(3 − 2t)", exact ends), `SceneTransitionSpec` ("finite, 0…10" seconds, `cut`, `defaultCrossfade` = crossfade 1 s ease in-out, `isInstant`, `resolved(reduceMotion:)`, validated Codable), `SceneTransitionClock` (integer nanoseconds, frame durations clamped to 0.1 s, first frame after start or `pause()` adds 0, exactly 1 at or after the duration), `SceneTransitionMix.weights(style:eased:)`. — Verified 2026-11-14: SceneTransitionModelTests (10 tests) on the Mac host and in the Linux shape
- [X] CMP-014-T03 [P] Model tests in `Packages/Compositor/Tests/CompositorTests/SceneTransitionModelTests.swift` (no Metal; also run in the Linux shape): clock from injected times, exact end, pause, clamp, zero duration, easing ends and monotonicity, weights, spec validation and Codable round trip, Reduce Motion → cut. — Verified 2026-11-14: 10 model tests pass on the Mac host and in the Linux shape (199 tests, 0 failures)
- [X] CMP-014-T04 Split `Compositor.composite(into:…)` in `Packages/Compositor/Sources/Compositor/Compositor.swift` into a shared private frame routine plus the existing guard/output closure, and add `encodeScene(width:height:commandBuffer:presentationTimeNanoseconds:contentScale:reduceFlashing:audio:) -> MTLTexture?` (contract). No behaviour change for `composite(into:)`. — Verified 2026-11-14: full Compositor suite 379 tests, 0 failures; RenderGoldens 39 tests, goldens identical

## Phase 3: User Story 1 — A crossfade starts and ends exactly (P1) 🎯 MVP

**Independent test**: red → blue crossfade; progress 0 and ≥ 1 byte-identical to each scene alone, midpoint within 0.002 of the reference blend, pool checked-out count equal before and after.

- [X] CMP-014-T05 [US1] Implement `SceneTransitionBus` in `Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift`: show, transition (snap-then-start on interruption), cancel, finish now, pause/resume, `encodeFrame`, `encodeOutput`, the mix shader, one flash guard, the pooled blend target returned at the end, on cancel, interruption, size change and deinit. — Verified 2026-11-14: SceneTransitionBusTests (10 tests) pass
- [X] CMP-014-T06 [US1] Acceptance tests in `Packages/Compositor/Tests/CompositorTests/SceneTransitionBusTests.swift`: exact start, midpoint, exact end and after, pool counts; repeated with cancel and with a mid-transition interruption; dip to black midpoint is black; `encodeOutput` gives the shown frame (R9); an output size change mid-transition leaks nothing. — Verified 2026-11-14: testCrossfadeReachesExactStartAndEndWithNoLeakedTextures, testCancel…, testInterruption…, testDipToBlack…, testSizeChange… (pool 2 / 5 / 2)

## Phase 4: User Story 2 — One clock drives every transition (P1)

- [X] CMP-014-T07 [US2] Bus clock tests in `SceneTransitionBusTests.swift`: progress follows injected frame times, holds across `pause()` and a long gap, ends exactly at the duration. — Verified 2026-11-14: testBusClockPausesAndEndsAtTheDuration and the model clock tests

## Phase 5: User Story 3 — Safety and accessibility rules hold (P1)

- [X] CMP-014-T08 [US3] Reduce Motion: `transition(to:spec:reduceMotion: true)` is an instant switch (0 blended frames) in `SceneTransitionBusTests.swift`. — Verified 2026-11-14: testReduceMotionGivesAnInstantSwitch (0 blended frames, byte-identical to B alone)
- [X] CMP-014-T09 [US3] CMP-013: with two static (cacheable) scenes whose compositors report `compositeReused`, every blended frame differs from the previous one (`SceneTransitionBusTests.swift`). — Verified 2026-11-14: testRenderCachingNeverFreezesATransition (both scenes reuse, 3 of 3 blended frames differ)
- [X] CMP-014-T10 [US3] Flash: a fast dip to black between two white scenes with Reduce flashing drives the bus guard's gain below 1 (`SceneTransitionBusTests.swift`). — Verified 2026-11-14: testFlashGuardLimitsTransitionFrames (23 blended frames, lowest gain 0.0125)
- [X] CMP-014-T11 [P] [US3] App: `MotionPolicy.sceneTransition(_:)` in `Apps/projectM-iOS/Views/MotionPolicy.swift` and its test in `Apps/projectM-iOS/Tests/MotionPolicyTests.swift` (Reduce Motion → cut, otherwise unchanged). — Verified 2026-11-14: MotionPolicyTests.testSceneTransitionIsACutWithReduceMotion; app unit tests 514, 0 failures on the iOS 27.2 simulator; check_motion_policy OK

## Phase 6: User Story 4 — GPU time is recorded (P2)

- [X] CMP-014-T12 [US4] Timing test in `SceneTransitionBusTests.swift`: GPU time (`gpuEndTime − gpuStartTime`) per single-scene frame vs per blended frame at 1920 × 1080, printed as `CMP-014 GPU`, not asserted. — Verified 2026-11-14: testGPUTimeOfTransitionFramesIsRecorded: 0.195 ms single vs 0.275 ms transition (Mac, recorded only)

## Phase 7: Polish & cross-cutting

- [X] CMP-014-T13 [P] ADR `docs/adr/0042-scene-transition-bus.md` (clock, bus, guard placement, interruption, persistence deferral) and the `docs/adr/README.md` index row. — Verified 2026-11-14: docs/adr/0042-scene-transition-bus.md and index row; validate_docs OK
- [X] CMP-014-T14 [P] Report `docs/test-reports/transition-bus.md`; the package header in `Packages/Compositor/Package.swift` and `Compositor.swift` mention CMP-014. — Verified 2026-11-14: docs/test-reports/transition-bus.md; Package.swift and Compositor.swift headers
- [X] CMP-014-T15 Regressions: Compositor (full and Linux shape), RenderGoldens (goldens unchanged), SceneFormat, ShowControl, ImportFuzz, SceneArchive, app unit tests on a private iOS 27.2 simulator, and the six scripts; confirm no file format changed (R13: `git diff` shows no change under `Packages/ShowControl` or `Packages/SceneFormat`). — Verified 2026-11-14: Compositor 379 + Linux shape 199, RenderGoldens 39 (goldens identical), SceneFormat 112, ShowControl 42, ImportFuzz 15, SceneArchive 27, app 514, scripts 153 and the five checks all pass; no change under Packages/ShowControl or Packages/SceneFormat

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06–T10, T12; T11 depends on T02 only; T13–T14 after T06; T15 last.

## Parallel opportunities

T03 with T04; T11 with T05–T10; T13 with T14.

## Implementation strategy

MVP = Phases 1–3 (the acceptance). Then US2, US3, US4, polish.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1–R13 and S1–S8 each map to at least one task (R13 through T15's format check). No
constitution conflict, no placeholder. Fixes applied: the failed-frame edge case now matches the
presentation-time clock (spec); T06 covers R9 and a size change mid-transition; T15 checks R13.
