# Tasks: VIS-016 Starfield Flight

**Input**: `specs/287-vis-016-starfield-flight/` (spec, plan, research, data-model, contracts/starfield.md)

## Phase 1: Foundational - model (VIS-016-R2 to R6)

- [X] VIS-016-T01 `StarfieldSpeed`, `StarfieldConfiguration` (clamps, `activeCount`, constants) in `Packages/VisualGenerators/Sources/VisualGenerators/StarfieldConfiguration.swift`. — Verified 2026-11-15: swift test --filter Starfield (configuration clamps and speeds asserted in StarfieldSimulationTests; host and -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape)
- [X] VIS-016-T02 `StarfieldSimulation` (2000-star pool allocated once, SplitMix64 draws in fixed order, fixed 1/240 s steps from the anchor, ≤ 240 steps per advance, respawn, bass smoothing, `reset()`) in `StarfieldSimulation.swift`. — Verified 2026-11-15: StarfieldSimulationTests 4 passed on the host, the Linux shape and VIS16 iPhone 17 (iOS 27.2)

## Phase 2: User Stories 2 + 3 - density limit and deterministic reset (VIS-016-R2 to R4; S1, S2)

- [X] VIS-016-T03 [US2] [US3] `StarfieldSimulationTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/StarfieldSimulationTests.swift`): 5000 requested → exactly 2000 active; never above over a 5 s run, storage address and size constant; reset → initial positions bit for bit; 60 Hz vs jittery frame times bit-identical at shared times; another seed differs; respawn at far with depth decreasing; Reduce Motion half; speed cap; Linux shape. — Verified 2026-11-15: StarfieldSimulationTests 4 passed (0.48 s host): 5000 and Int.max → exactly 2000 active, never more over 5 s with a second over-cap request mid-run, pool address and size unchanged; reset restores every star bit for bit (and a seed change, and back); 60 Hz vs 4-40 ms jittery frames bit-identical at six shared times, seed 7 differs; respawn at the far plane; caps; 1 s stall bound

## Phase 3: User Stories 1 + 4 - layout and safety (VIS-016-R5, R7; S4)

- [X] VIS-016-T04 [US1] `StarfieldLayout` (perspective squares, side and alpha bounds, fades, culling, total-light bound, flash regions, tessellation) in `StarfieldLayout.swift`. — Verified 2026-11-15: StarfieldFlashTests and StarfieldRenderTests (layout squares, bound, culling)
- [X] VIS-016-T05 [US1] [US4] `StarfieldFlashTests` (`StarfieldFlashTests.swift`): size and alpha never decrease as a star approaches (away from the fades); mean light ≤ 0.05 at 2000 stars, Fast, full bass; densest, fastest field with bass bursts within the envelope's transition budget in all 17 areas, Reduce flashing on and off (with the strongest glow). — Verified 2026-11-15: StarfieldFlashTests 3 passed (1.09 s host): size and alpha monotone between the fades, bounded; mean light ≤ 0.05 at 390×844 (largest 0.0025) and 24×16 (bound exercised); 2000 stars, Fast, bass bursts for 1.5 s: worst 0 transitions per window, Reduce flashing on (limit 4) and off (limit 6), portrait and landscape with glow

## Phase 4: User Story 1 - the picture on Metal (VIS-016-R1, R9, R12; S3)

- [X] VIS-016-T06 [US1] `StarfieldGenerator` on `FlatShapePass` (bands → low group → bass; advance; layout; envelope gain; tessellate) in `StarfieldGenerator.swift`. — Verified 2026-11-15: build plus StarfieldRenderTests on the host GPU and VIS16 iPhone 17
- [X] VIS-016-T07 [US1] `StarfieldRenderTests` (GPU, `StarfieldRenderTests.swift`): two renders identical; every lit pixel inside a laid-out square; restart gives the first frame again. — Verified 2026-11-15: StarfieldRenderTests passed (0.15 s host, 0.19 s simulator): two generators identical bytes, every lit pixel inside a laid-out square, restart replays the first frame byte for byte
- [X] VIS-016-T08 [US1] `StarfieldGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry. — Verified 2026-11-15: RenderGoldens StarfieldGolden recorded on the host and on VIS16 iPhone 17, then identical (SSIM 1.0) on both; integrity passed; RenderGoldens --filter Starfield|ParticleOrbitGolden|GoldenIntegrity 24 passed

## Phase 5: User Story 5 - the app (VIS-016-R8, R10, R11; S5)

- [X] VIS-016-T09 [US5] Visual choice `starfield`, keys `settings.starfield.speed` and `settings.starfield.density` (in `allKeys`, `ALLOWED_KEYS`, FILE-005 policy), `StarfieldOptions` (picker, stepper), host style `.starfield(speed:density:)` built and updated in place (`NativeSpectrumHost+Starfield.swift`), palette and Reduce Motion, accessibility value, scene capture as no layer. — Verified 2026-11-15: xcodebuild build-for-testing on VIS16 iPhone 17 with the type-check flags: no warning in a touched file (the warnings seen, 284-348 ms, are all in untouched files under a loaded machine)
- [X] VIS-016-T10 [P] [US5] `StarfieldAppTests` (setting persists and falls back; host names itself, applies speed and density in place, palette and Reduce Motion; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` updated and passing. — Verified 2026-11-15: xcodebuild test-without-building: StarfieldAppTests 4, SettingsTests, CameraVisualTests, LibraryBackupAppTests, TunnelAppTests (29 passed, 2.1 s)
- [X] VIS-016-T11 [P] [US5] `StarfieldUITests`: choose Starfield, Speed and Stars offered, Bars not, change speed, value updates, source started once (< 30 s). — Verified 2026-11-15: StarfieldUITests passed in 27.3 s warm on VIS16 iPhone 17 (32.6 s on the first, cold run)

## Phase 6: Polish

- [X] VIS-016-T12 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts. — Verified 2026-11-15: VisualGenerators swift test 374 passed (99.8 s on a loaded machine; the Starfield suites add 1.8 s); Linux shape 305 passed; LibraryBackup 87 passed; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 179 OK; check_privacy_manifest OK; check_network_symbols OK (19 images); PosterBoard reports 25 before and after
- [ ] VIS-016-T13 {device} On D1 with music, Starfield at 2000 stars and Fast holds the display's frame rate on the PERF-001/007 overlay, and looks calm with Reduce Motion.

## Dependencies

T01 → T02 → T03; T02 → T04 → T05, T06; T06 → T07, T08, T09 → T10, T11; all → T12. T13 needs a device.

## Parallel examples

T03 and T05 (different test files) after T04; T10 and T11 after T09.

## Implementation strategy

MVP = T01-T03 (the acceptance: density limit and deterministic reset, proven by pure simulation tests); then the
picture (T04-T08), then the app (T09-T11).

## Analyze notes (speckit-analyze, 2026-11-15)

- Coverage: R1 T06; R2-R4, R6 T02-T03; R5, R7 T04-T05; R8, R10, R11 T09-T11; R9 T08; R12 T12. S1, S2 T03; S3 T07-T08;
  S4 T05; S5 T10-T11; S6 T12. No constitution conflict (no shader, no dependency, no networking, nothing reaches
  projectM).
- Fix applied (inconsistency): US1 scenario 1 said brightness never decreases as a star approaches, but the
  clarified near-plane fade-out lowers it just before a respawn; the scenario now excludes both fades, as T05 does.
- Fix applied (coverage): US2 scenario 3 (speed change in place, no restart) is asserted in T10.
