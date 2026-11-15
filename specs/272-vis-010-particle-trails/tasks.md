# Tasks: VIS-010 Particle Trails

**Input**: `specs/272-vis-010-particle-trails/` (spec, plan, research, data-model, contracts/particle-trails.md, quickstart)

Tests are requested by the spec (acceptance fixture, goldens, UI test). `{device}` marks work the Mac cannot finish.

## Phase 1: Setup

- [X] VIS-010-T01 Create simulator "VIS10 iPhone 17" (iOS 27.2), init preset submodules, `xcodegen generate` in the worktree — Verified 2026-11-14: simulator created (2D6F1CE8…), presets initialised, xcodegen generate exit 0

## Phase 2: Foundational (CPU model, every platform)

- [X] VIS-010-T02 `ParticleTrailLength`, half-life (Short 0.1 s, Long 0.3 s; × 0.5 Reduce Motion; ≤ 0.25 s Reduce flashing), `ParticleTrails.decay` (`min(0.5^(Δt/h), 0.99)`, Δt clamped 0…0.1 s), cap 0.8, cut 1/512, `accumulate` pixel reference, `ParticleTrailFlashBound`, `ParticleTrailModel` in Packages/VisualGenerators/Sources/VisualGenerators/ParticleTrails.swift — Verified 2026-11-14: swift build (host and -DVISUAL_NO_METAL) and ParticleTrailModelTests
- [X] VIS-010-T03 [P] Model tests: frame-rate independence (30 vs 120 fps within 0.01 at 0.5 s), cap under continuous emission, cut to exact 0, Reduce Motion/flashing half-lives, flash bound recurrence, fixed storage over a 36 000-frame CPU fixture in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleTrailModelTests.swift — Verified 2026-11-14: ParticleTrailModelTests 6/6 on the macOS host (1.3 s)

## Phase 3: US1 + US2 Streaks with constant memory (P1)

- [X] VIS-010-T04 [US1] `FlatShapePass`: keep `library`, `buffer(_:)`, `markRead`, optional underlay closure in `draw`; append `ParticleTrailShader.functions` to `shaderSource` in Packages/VisualGenerators/Sources/VisualGenerators/FlatShapePass.swift — Verified 2026-11-14: VisualGenerators suite 330/330 on the macOS host (archive and spectra tests unchanged)
- [X] VIS-010-T05 [US1] `ParticleTrailPass` (two private 512² `rgba16Float` textures made once, decay/accumulate/present pipelines via `NativePipelineArchive`, reset rule, `encode`) and `ParticleTrailShader` in Packages/VisualGenerators/Sources/VisualGenerators/ParticleTrailPass.swift — Verified 2026-11-14: ParticleTrailRenderTests 5/5 on the macOS host
- [X] VIS-010-T06 [US1] `trails` property and trail branch in Packages/VisualGenerators/Sources/VisualGenerators/ParticleFountainGenerator.swift and ParticleOrbitGenerator.swift (Off path unchanged) — Verified 2026-11-14: ParticleTrailRenderTests (fountain fixture, orbit resize/restart/off) and the full suite 330/330
- [X] VIS-010-T07 [US2] GPU tests: 10-minute fixture (36 000 frames at 60 Hz, resizes, setting changes) asserting texture count, identities and total `allocatedSize` constant; Off allocates nothing; GPU streak matches CPU reference; cap holds on readback in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleTrailRenderTests.swift — Verified 2026-11-14: ParticleTrailRenderTests 5/5 on the macOS host; fixture 6.9 s, 3 694 of 36 000 frames encoded, 2 textures, 4 227 072 bytes constant
- [X] VIS-010-T08 [US1] Golden of the seeded fountain with Long trails at 0.6 s, macOS host and iOS Simulator, in Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleTrailGoldenTests.swift (+ GeneratorGoldens/ParticleTrails/); existing fountain/orbit goldens unchanged — Verified 2026-11-14: ParticleTrailGoldenTests recorded and re-compared on the macOS host and the iOS 27.2 simulator (identical); ParticleFountain and ParticleOrbit goldens identical on both; trail tests also pass on the simulator (allocatedSize reads 0 there, sizes and identities asserted)

## Phase 4: US3 Safe brightness (P1)

- [X] VIS-010-T09 [US3] Flash tests: envelope sees the trail bound, gain scales the trail, Reduce flashing budget held with strobing bursts, bound ≥ measured trail luminance in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleTrailFlashTests.swift — Verified 2026-11-14: ParticleTrailFlashTests and ParticleTrailBoundRenderTests on the macOS host (worst transitions 1/4 Reduce flashing on, 6/6 off)

## Phase 5: US4 Choose it (P2)

- [X] VIS-010-T10 [US4] App setting `settings.particleTrails` (`ParticleTrailSetting`, unknown → Off) in Apps/projectM-iOS/Coordinators/AppSettings.swift; key in scripts/run_device_tests.py `ALLOWED_KEYS` and Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift `includedKeys` — Verified 2026-11-14: ParticleTrailAppTests (default, persistence, unknown → Off, key lists) and LibraryBackupAppTests 5/5 on the iOS 27.2 simulator
- [X] VIS-010-T11 [US4] `NativeSpectrumHost.particleTrails` applied to fountain/orbit (also after a rebuild), accessibility value suffix, coordinator wiring and `onChange` in Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Coordinators/AppCoordinator.swift, Views/VisualizerView.swift — Verified 2026-11-14: ParticleTrailAppTests.testHostAppliesTrailsToFountainAndOrbit and ParticleTrailUITests (value "…, Trails Long") on the iOS 27.2 simulator
- [X] VIS-010-T12 [US4] "Trails" picker (`particleTrailsPicker`) in both particle options in Apps/projectM-iOS/Views/SettingsView.swift — Verified 2026-11-14: ParticleTrailUITests on the iOS 27.2 simulator (picker offered, Off selected, Long chosen)
- [X] VIS-010-T13 [US4] App tests (persistence, unknown → Off, key lists, host applies to generator) in Apps/projectM-iOS/Tests/ParticleTrailAppTests.swift; SettingsTests `testOnlyTheSettingsKeysAreWritten`; LibraryBackupAppTests — Verified 2026-11-14: ParticleTrailAppTests 3/3, SettingsTests 9/9 (testOnlyTheSettingsKeysAreWritten), LibraryBackupAppTests 5/5, ParticleFountainAppTests and ParticleOrbitAppTests on the iOS 27.2 simulator
- [X] VIS-010-T14 [US4] UI test (≤ 30 s): choose Particle Fountain, set Trails Long in Apps/projectM-iOS/UITests/ParticleTrailUITests.swift — Verified 2026-11-14: ParticleTrailUITests passed in 20.4 s on "VIS10 iPhone 17" (iOS 27.2); ParticleFountainUITests still passes (13.3 s)

## Phase 6: Polish

- [X] VIS-010-T15 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), Linux shape build, type-check budget, privacy manifest and network symbols on the Debug app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; Linux shape (-DVISUAL_NO_METAL) builds and its 7 CPU trail tests pass; LibraryBackup 87/87; type-check warnings only in files this feature does not touch (SettingsView:294 pre-existing)
- [ ] VIS-010-T16 {device} (open: needs D1 and a person) D1: Particle Fountain and Particle Orbit with Trails Short/Long; streaks fade, frame rate unchanged within noise, no flashing with Reduce flashing

## Dependencies

T02 → T03, T04 → T05 → T06 → T07, T08, T09; T10 → T11 → T12 → T13, T14; T15 last. US4 depends on T06.

## Parallel examples

T03 alongside T04; T08 and T09 after T06; T10 alongside T07.

## Implementation strategy

MVP = T02-T07 (the acceptance fixture). Then safety (T09), golden (T08), app (T10-T14).
