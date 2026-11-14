# Tasks: QA-006 Render Soak Test

**Input**: Design documents from `specs/155-qa-006-render-soak/` (spec, plan, research, data-model,
contracts/render-soak.md, quickstart)

**Tests**: requested by the spec (acceptance soak, negative controls, verdict unit tests).

Format: `- [ ] QA-006-Tnn [P?] [Story] Description`. `{device}` = needs a physical device (left open).

## Phase 1: Setup

- [X] QA-006-T01 Create the QA6 iOS 27.2 simulator, check `Build/` xcframeworks and the projectM submodule in the worktree, count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` — Verified 2026-11-14: QA6 iPhone 17 (iOS 27.2, F25F71E4) created; `Build` symlink, ProjectM and ANGLE xcframeworks and 38 test presets present; PosterBoard reports before: 25

## Phase 2: Foundational (verdict logic, blocks every story)

- [X] QA-006-T02 Implement `RenderSoakTolerance` (warm-up 2, minimum measured 3, slope ε = max(64 KiB, 0.5 %), bound max(2 MiB, 10 %), live scenes at dwell end 1), `RenderSoakCycleSample`, `RenderSoakDwellSample`, `RenderSoakError`, `RenderSoakRule`, `RenderSoakVerdict`, `RenderSoakRecorder` (least-squares slope, rules of contract S7) and Codable `RenderSoakReport` in `Packages/Compositor/Sources/Compositor/RenderSoak.swift` (plain Swift, no Metal) — Verified 2026-11-14: built by the T03 tests on the host and the Linux shape
- [X] QA-006-T03 [P] Verdict unit tests (flat, noisy, ramp → `memorySlope`, step → `memoryBound`, too few cycles → inconclusive, errors, baseline drift, live objects, release not empty, slope helper) in `Packages/Compositor/Tests/CompositorTests/RenderSoakVerdictTests.swift`; run on the host and the Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL`) — Verified 2026-11-14: `swift test --filter RenderSoakVerdictTests` 9/9 on the host and 9/9 with `-Xswiftc -DCOMPOSITOR_NO_METAL` (each test < 0.01 s)

## Phase 3: User Story 1 — short soak proves no leak and no render error (P1) MVP

**Independent test**: `swift test --package-path Packages/RenderGoldens --filter RenderSoakTests/testDefaultSoakIsBoundedAndErrorFree` passes and writes a report.

- [ ] QA-006-T04 [US1] Extract `GoldenSceneRenderer.buildScene(run:document:texturePool:allowEffectWarnings:)` (registry, live state, store, layers, compositor with the given pool, stack, effects) from `render` with no behaviour change in `Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift`; QA-002 golden tests still pass
- [ ] QA-006-T05 [US1] Implement `RenderSoakScene`, `RenderSoakConfiguration` (128 × 96, 1,800 frames, dwell 30, transition 0.25 s, cut every 3rd switch, 1/60 s clock, seed), `RenderSoakLeak` and `RenderSoakDriver.run` (contract S1-S6: bus + shared pool, seeded fixture bands, per-frame `currentAllocatedSize` with pool fallback, dwell and cycle samples, weak-reference live counts, error counting, release record, JSON report to `QA006_REPORT_DIR` or the temporary folder) in `Packages/RenderGoldens/Sources/SceneRenderHarness/RenderSoakDriver.swift`
- [ ] QA-006-T06 [US1] Acceptance test `testDefaultSoakIsBoundedAndErrorFree` (6 scenes, 30 s simulated, 60 switches: zero errors, slope ≤ ε, bound held, pool baselines, live ≤ 1, release empty; report attached) in `Packages/RenderGoldens/Tests/RenderGoldensTests/RenderSoakTests.swift`; run on the host
- [ ] QA-006-T07 [US1] Run the RenderGoldens soak tests on the QA6 simulator (`build-for-testing`, `test-without-building -only-testing:RenderGoldensTests/RenderSoakTests`)
- [ ] QA-006-T07a [US1] If any soak run finds a real leak or render error, fix it in the rendering code, report it, and add a regression test next to the leaking code (QA-006-R12); otherwise record "no leak found" with the run's figures in `docs/test-reports/render-soak.md`

## Phase 4: User Story 2 — the detector catches a leak (P1)

**Independent test**: the two negative-control tests pass because the soak fails with the named rules.

- [ ] QA-006-T08 [US2] Negative controls `testPooledLeakFailsTheSoak` (expects `poolBaseline` and `memorySlope`) and `testDeviceLeakFailsTheSoak` (expects `memorySlope`), 3 scenes, 6 cycles, in `Packages/RenderGoldens/Tests/RenderGoldensTests/RenderSoakTests.swift`; host and QA6 simulator

## Phase 5: User Story 3 — projectM preset switching soaks too (P2)

**Independent test**: `-only-testing:ANGLERenderingTests/ProjectMPresetSoakTests` passes on QA6.

- [ ] QA-006-T09 [US3] `ProjectMPresetSoakTests` (one `ProjectMLayerSource` in a `Compositor` at 64 × 64, 5 test presets switched every 40 frames, 110 + 440 Hz AUD-016 sine into the PCM ring every frame, 1,200 frames; `RenderSoakRecorder` verdict passes; honours `QA006_SOAK_SECONDS`; writes its report) in `Packages/ANGLERendering/Tests/ANGLERenderingTests/ProjectMPresetSoakTests.swift`; run on QA6

## Phase 6: User Story 4 — long soak on demand (P2)

- [ ] QA-006-T10 [US4] Bench test `RenderSoakBenchTests` (skipped unless `QA006_SOAK_SECONDS` is a positive number) in `Packages/RenderGoldens/Tests/RenderGoldensTests/RenderSoakTests.swift`
- [ ] QA-006-T11 [P] [US4] `scripts/run_render_soak.py` (`--seconds`, `--simulator`, `--angle`, `--report-dir`, `--dry-run`; host `swift test --filter`, simulator `xcodebuild` with `TEST_RUNNER_QA006_*`; reads reports, prints verdicts, exit 1 on failure) and its tests in `scripts/test_scripts.py`
- [ ] QA-006-T12 [US4] Run a short on-demand soak through the script on the host (`--seconds 40`) and check the report
- [ ] QA-006-T13 {device} [US4] Long soak (≥ 600 s simulated) on D1 in the final QA phase (QA-006-S6)

## Phase 7: Polish

- [ ] QA-006-T14 [P] Soak section in `Packages/RenderGoldens/README.md` (what runs, rule, report, bench, script)
- [ ] QA-006-T15 Type-check budget (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) for the changed packages, Linux shape of Compositor and RenderGoldens, repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), PosterBoard count, delete QA6 and derived data; update spec status

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06 → T07 → T07a; T05 → T08; T02 → T09; T05 → T10 → T11 → T12;
T14, T15 last. T13 open (`{device}`).

## Parallel opportunities

T03 with T04; T09 (ANGLERendering) with T05-T08 (RenderGoldens); T11 with T09.

## Implementation strategy

MVP = Phases 1-3 (verdict + short scene soak). Then the negative controls (they prove the MVP
meaningful), the projectM soak, the bench and script, polish.
