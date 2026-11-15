# Tasks: OUT-013 Frame Pacing per Output

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/output-pacing.md](contracts/output-pacing.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap acceptance (OUT-013-S1 to S4). Budgets (owner rule 7): unit tests ≤ 10 s, package
suite < 1 min, single xcodebuild run < 10 min; no wall-clock assertion in the model.

## Phase 1: Setup

- [X] OUT-013-T01 Create simulator "OUT13 iPhone 17" (iOS 27.2), run `xcodegen generate` in the worktree, confirm `Build` and the preset submodules are present — Verified 2026-11-14: simulator 069E0B99 created, xcodegen generate OK, Build symlink and presets present

## Phase 2: Foundational (the pure gate)

- [X] OUT-013-T02 Implement `OutputPacingPolicy` (`maxFramesInFlight` default 2, "clamped to 1…3"; `slowWaitFraction` 0.5), `OutputPacingCounts` and the lock-free `OutputFrameGate` (`tryBegin`, `complete`, `abandon`, `noteDrawableWait`, `counts`; "Never blocks, never allocates after init") in Packages/Compositor/Sources/FrameTiming/OutputFrameGate.swift (contract C1) — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter OutputFramePacingTests` (8 passed)
- [X] OUT-013-T03 Gate unit tests (bound, abandon, complete never below 0, back-off one tick, counts invariant `begun + droppedInFlight + droppedBackOff == ticks`) in Packages/Compositor/Tests/FrameTimingTests/OutputFramePacingTests.swift — Verified 2026-11-14: same run: bound, abandon, stray completions, back-off, clamp, 2,000 concurrent begin/complete

## Phase 3: User Story 1 — the device stays responsive (P1) 🎯 MVP

**Independent test**: the simulation (S1-S3) and the app test (S4).

- [X] OUT-013-T04 [US1] Simulation in Packages/Compositor/Tests/FrameTimingTests/OutputFramePacingTests.swift: 120 Hz device ticks, 60 Hz output link, 100 ms output, 1 ms encode, 10 simulated s: no device tick late > 1 ms, in flight ≤ 2, max depth after 1 s == after 10 s, every drop counted; the blocking control is late ≥ 50 ms (S1-S3) — Verified 2026-11-14: same run: `testASlowExternalOutputDoesNotDelayTheDeviceLoop` (lateness ≤ 1 ms, in flight ≤ 2, constant depth, drops counted), blocking control ≥ 50 ms late
- [ ] OUT-013-T05 [US1] `MetalOutputPacing` (gate, timed `nextDrawable`, completion tracking, DEBUG held completions) and the explicit drawable policy (`maximumDrawableCount = 3`, `allowsNextDrawableTimeout = true`) in Apps/projectM-iOS/Visuals/MetalOutputPacing.swift (contract C4)
- [ ] OUT-013-T06 [US1] Use it in the five Metal hosts before `nextDrawable` and before `commit`: Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, CameraVisualHost.swift, PhotoVisualHost.swift, VideoVisualHost.swift, TextVisualHost.swift
- [ ] OUT-013-T07 [US1] ANGLE fences: CANGLE helpers `PMANGLEFenceInsert`, `PMANGLEFenceSignaled`, `PMANGLEFenceDelete` (GL ES 3.0 sync objects through `eglGetProcAddress`) in Packages/ANGLERendering/Sources/CANGLE/include/CANGLE.h and CANGLE.c; `ANGLEFrameFences` (fixed capacity, zero-timeout poll, DEBUG hold) in Packages/ANGLERendering/Sources/ANGLERendering/ANGLEFrameFences.swift; gate + fences + layer policy in ANGLERenderer.swift (contract C3)
- [ ] OUT-013-T08 [US1] ANGLE test with held fences: after 2 presented frames further ticks are dropped and counted, releasing resumes, in flight ≤ 2, in Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLEOutputPacingTests.swift
- [ ] OUT-013-T09 [US1] App test: a native host in the external stand-in slot with held completions (a "slow output") and a main-actor display-link probe: probe keeps ticking (no gap > 0.25 s), in flight ≤ 2, drops counted and growing, nothing else grows; releasing resumes frames, in Apps/projectM-iOS/Tests/OutputFramePacingAppTests.swift (S4)

## Phase 4: User Story 2 — each output keeps its own rate (P2)

**Independent test**: the link follows the view's screen and keeps range and pause state.

- [ ] OUT-013-T10 [US2] `ScreenDisplayLink` (scene link on iOS 27 behind `#if compiler(>=6.4)`, screen link on iOS 26, main link without a window; `follow(_:)`) in Packages/ANGLERendering/Sources/ANGLERendering/ScreenDisplayLink.swift (contract C2); adopt it in ANGLERenderer.swift and the five hosts (`NativeSpectrumLayerView` reports window changes)
- [ ] OUT-013-T11 [US2] App test: a host moved between two windows keeps one link that follows the window's screen with the same frame-rate range and pause state, in Apps/projectM-iOS/Tests/OutputFramePacingAppTests.swift

## Phase 5: Polish

- [ ] OUT-013-T12 {device} D1 with a real external display (USB-C HDMI adapter) and a deliberately heavy preset at the display's native resolution: the device's controls and HUD stay smooth; the external drop counts rise (S5)
- [ ] OUT-013-T13 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`, privacy manifest and network symbols on the Debug app), type-check budget, PosterBoard counts; delete the simulator and derived data

## Dependencies

T01 → T02 → T03/T04 (model) → T05 → T06; T02 → T07 → T08; T10 before T06/T07 edits land in the same files (do T10's
link swap together with T06/T07); T09 and T11 after T06 and T10; T13 last. US2 has no dependency on US1's tests.

## Parallel examples

T03 and T04 are one file (sequential). T05 (app) and T07 (ANGLE package) touch different files and can proceed in
parallel once T02 exists.

## Implementation strategy

MVP = Phase 2 + US1 (the bound and the drops: the acceptance criterion). US2 (per-screen pacing) removes the rate
mismatch at the source; both land in this branch.
