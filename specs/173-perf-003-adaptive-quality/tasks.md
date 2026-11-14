# Tasks: PERF-003 Adaptive effect quality

**Input**: Design documents from `specs/173-perf-003-adaptive-quality/` (spec, plan, research, data-model,
contracts/effect-quality-ladder.md, quickstart)

**Tests**: Requested by the roadmap acceptance and the brief (ladder order, encode counts, strobe fixture,
hysteresis, smoothing, nominal identity, overlay text, Linux shape). Budgets: owner rule 7.

## Phase 1: Setup

- [ ] PERF-003-T01 Confirm the worktree builds as is: `xcodegen generate`, the `Build` symlink and preset submodules present; create the feature simulator "PERF3 iPhone 17" (iOS 27.2)

## Phase 2: Foundational (blocks every story)

- [ ] PERF-003-T02 Add `EffectQualityLevel`, `EffectThermalState`, `EffectBudgetSignal`, `EffectQualityReason`, `EffectQualityPolicy` (3 s, 10 s, 0.4 s; invalid → defaults) and `EffectQualityLadder` (contract C1; data-model transitions 1-5, `start`, `overlayLine`) in Packages/VisualGenerators/Sources/VisualEffects/EffectQuality.swift — pure Swift, no Metal, no allocation in `step`

## Phase 3: User Story 1 — simplify the glow before dropping frames (P1)

**Goal**: Thermal stress and a sustained over-budget verdict lower the glow's cost in order, before the frame-rate cap.
**Independent test**: inject nominal → serious → critical with an injected clock; levels Full → Reduced → Minimal; governor cap 60, 60, 30.

- [ ] PERF-003-T03 [US1] Ladder tests in Packages/VisualGenerators/Tests/VisualGeneratorsTests/EffectQualityLadderTests.swift: thermal order, Low Power floor, 3 s budget step-down (and not at 2.9 s), unavailable clears the timer, 10 s one-step recovery (Minimal → Full in two steps, S4), fade out/switch/fade in timing and reversal mid-fade, start without fade, ignored backwards/non-finite time, overlay lines, determinism
- [ ] PERF-003-T04 [US1] `BloomPlan(parameters:width:height:quality:)` (research D2; `.full` identical; Reduced ⌈R/2⌉ taps, coarser image only when E' ≤ E; `blurWork`) in Packages/VisualGenerators/Sources/VisualEffects/BloomPlan.swift
- [ ] PERF-003-T05 [US1] `BloomEffect.quality` (plan rebuilt only on change; `.minimal` pass-through) and `encodedPassCount` in Packages/VisualGenerators/Sources/VisualEffects/BloomEffect.swift
- [ ] PERF-003-T06 [US1] Bloom tests in Packages/VisualGenerators/Tests/VisualGeneratorsTests/EffectQualityBloomTests.swift: Full plan equals today's for representative radii and sizes; Reduced halves taps, lowers `blurWork`, never widens the halo (radius range × 3 sizes); Metal: encoded passes 4 per frame at Full and Reduced, 0 at Minimal through an `EffectChain`; Full output bit-identical to a bloom with no quality set (S5)
- [ ] PERF-003-T07 [US1] `QualityGovernor.settings(thermal:lowPower:adaptiveEffects:)` in Packages/Rendering/Sources/Rendering/QualityGovernor.swift, with tests in Packages/Rendering/Tests/RenderingTests/QualityGovernorTests.swift (false = today's table for every input; true: serious 60 fps, critical 30 fps × 0.75, Low Power 30)
- [ ] PERF-003-T08 [US1] Native host wiring in Apps/projectM-iOS/Visuals/NativeSpectrumHost+EffectQuality.swift and small hooks in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift: one ladder; thermal/Low Power inputs (DEBUG `-uitestThermalState`); started with the loop; stepped per frame with the display-link time; level → `bloom.quality`; weight × clamped glow intensity in `resolveEffectiveGlow` (only when it changed); governor with `adaptiveEffects = glow.enabled && chain exists`; `effectBudget`, `effectQualityLine`
- [ ] PERF-003-T09 [US1] App tests in Apps/projectM-iOS/Tests/EffectQualityAppTests.swift: serious → Reduced at 60 fps cap, critical → Minimal at 30 fps; glow off → today's governor; budget over 3 s steps down; the bloom's effective intensity never exceeds the clamped glow during a fade

## Phase 4: User Story 2 — safety never degrades (P1)

**Goal**: The FX-019 envelope, Reduce flashing and the ACC-012 clamp are identical at every level; level changes make no flash.
**Independent test**: strobe fixture through the limiter at every level and across level changes; rise ≤ bound, same envelope configuration.

- [ ] PERF-003-T10 [US2] Strobe tests in Packages/VisualGenerators/Tests/VisualGeneratorsTests/EffectQualitySafetyTests.swift: bands alternating 0/1 through `FlashSafetyLimiter` + layout + `BloomLuminanceModel` of the ladder-weighted glow at Full, Reduced, Minimal and while the ladder steps (with Reduce flashing on and off); rise ≤ bound; envelope configuration equal; weighted intensity ≤ ACC-012-limited intensity at every step

## Phase 5: User Story 3 — see and export the level (P2)

- [ ] PERF-003-T11 [US3] Diagnostics `FrameTimings.effectQuality` (level enum, optional reason) and exporter line in Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift and DiagnosticsExporter.swift; schema in specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json and its test copy; tests in Packages/Diagnostics/Tests/DiagnosticsTests/FrameTimingsExportTests.swift (round trip, absent = unchanged, schema-valid)
- [ ] PERF-003-T12 [US3] Coordinator: budget verdict → `nativeVisual.effectBudget` (any flag → over; overlay off → unavailable), overlay line appended, `exportTimings(..., effectQuality:)` in Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift; perf001 export in Apps/projectM-iOS/Automation/AutomationRunner.swift
- [ ] PERF-003-T13 [US3] UI test Apps/projectM-iOS/UITests/EffectQualityOverlayUITests.swift (< 30 s): `-uitestThermalState serious`, circular spectrum with glow on, overlay on → `effect quality reduced (thermal)`

## Phase 6: Polish

- [ ] PERF-003-T14 Linux shape (`swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL --filter EffectQuality`), type-check budget build, repo checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols), PosterBoard counts; spec status
- [ ] PERF-003-T15 {device} D1 with the glow on under sustained load: the overlay shows Reduced at serious with the 60 fps cap kept, Minimal and 30 fps only at critical; `perf001` export carries the level

## Dependencies

T01 → T02 → (T03, T04 → T05 → T06, T07) → T08 → T09; T10 needs T02, T04; T11 independent after T02; T12 needs T08, T11; T13 needs T12; T14 last.
Parallel: T03, T04, T07, T11 touch different files.

## Implementation strategy

MVP = Phases 2-3 (ladder, Reduced plan, governor, host). Then safety proof (US2), then visibility (US3).
