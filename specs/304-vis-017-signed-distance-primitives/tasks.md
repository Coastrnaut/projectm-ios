# Tasks: VIS-017 Signed-Distance Primitives

**Input**: `specs/304-vis-017-signed-distance-primitives/` (spec, plan, research, data-model, contracts/signed-distance.md)

## Phase 1: Foundational - model (VIS-017-R2 to R6)

- [X] VIS-017-T01 `SignedDistanceQuality`, `SignedDistanceSettings`, `SignedDistanceScene` (constants, primitives, scene distance, bounded march, normals, shading, CPU mirror of one pixel) and `SignedDistanceShader` (MSL text, same operations) in `Packages/VisualGenerators/Sources/VisualGenerators/SignedDistanceScene.swift`. — Verified 2026-11-15: swift test --filter SignedDistanceSceneTests 7 passed (0.21 s host; 0.20 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape)
- [X] VIS-017-T02 `SignedDistanceDrive` and `SignedDistancePose` (swell, spin, angle, brightness on the injected clock; Reduce Motion; sanitizing) in `SignedDistanceDrive.swift`. — Verified 2026-11-15: swift test --filter SignedDistanceSceneTests 7 passed (0.21 s host; 0.20 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape)
- [X] VIS-017-T03 `NoiseFieldConfiguration.signedDistance` (+ factory, `clamped()` turns the other modes off) in `NoiseFieldConfiguration.swift`. — Verified 2026-11-15: swift test --filter SignedDistanceSceneTests 7 passed (0.21 s host; 0.20 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape)

## Phase 2: User Stories 2 + 3 - step caps and finiteness on the CPU (R3 to R5; S1, S2)

- [X] VIS-017-T04 [US2] [US3] `SignedDistanceSceneTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/SignedDistanceSceneTests.swift`): caps ordered and ≤ 128; over a 64 × 48 ray grid plus grazing rays every march ≤ its cap, the High grid reaches more steps than the Low cap; misses take 0 steps; every primitive lies inside the bounding sphere for any pose (scene distance at radius 2 ≥ 0); every primitive is hit somewhere; extreme poses (NaN, ±inf, huge) give finite colours in 0…1; drive bounds (radius, spin, brightness, angle wrap, Reduce Motion half, time backwards, long gap). Runs in the Linux shape. — Verified 2026-11-15: swift test --filter SignedDistanceSceneTests 7 passed (0.21 s host; 0.20 s in the -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE Linux shape)

## Phase 3: User Story 1 + 4 - the picture on Metal and its safety (R1, R6, R7, R9, R12; S2 to S4)

- [X] VIS-017-T05 [US1] Mode `.signedDistance` in `NoiseFieldGenerator` (pipeline, drive, flash sampling, SDF uniform block, entry points `vis_sdf_fragment` and test-only `vis_sdf_steps_fragment`, restart) and `NoiseFieldFlashAreas.sampleSignedDistance`. — Verified 2026-11-15: swift build and SignedDistanceRenderTests on the host GPU (the mode draws through vis_sdf_fragment; restart and re-entry asserted)
- [X] VIS-017-T06 [US1] [US2] [US3] `SignedDistanceRenderTests` (GPU): per preset the step-count render's maximum ≤ cap and High > Low cap; a rgba16Float render with extreme bands and time is finite and in 0…1; two renders identical; CPU mirror and GPU agree on hit/miss at sample points away from silhouettes; quality change in place; entering the mode and a loop restart reset the pose. — Verified 2026-11-15: SignedDistanceRenderTests 4 passed (0.32 s host): GPU step-count maxima low 24/24, medium 48/48, high 68/96; NaN/±inf/1e6 bands with a 10⁹ s jump render finite in 0…1; two renders identical; GPU and CPU hit/miss agree at > 500 interior pixels; quality in place; re-entry equals a fresh generator
- [X] VIS-017-T07 [US4] `SignedDistanceFlashTests`: bass bursts alternating with silence stay within the transition budget in all 17 areas, Reduce flashing on and off; sample colours ≤ 0.8. — Verified 2026-11-15: swift test --filter SignedDistanceFlashTests 2 passed (0.28 s host): samples ≤ 0.8 luminance; bursts every 0.1 s for 2 s worst 2 (portrait) / 3 (landscape, strongest glow) transitions per window, limit 4 (Reduce flashing on) and 6 (off)
- [ ] VIS-017-T08 [US1] `SignedDistanceGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 4: User Story 5 - the app (R8, R10, R11; S5)

- [ ] VIS-017-T09 [US5] Visual choice `signedDistance` ("SDF Shapes"), key `settings.signedDistance.quality` (in `allKeys`, `ALLOWED_KEYS`, FILE-005 policy), `SignedDistanceOptions` (segmented picker), host style `.signedDistance(quality:)` built and updated in place (`SignedDistanceHostSupport.swift`), accessibility value, scene capture as no layer, onChange in a small new chain.
- [ ] VIS-017-T10 [P] [US5] `SignedDistanceAppTests` (setting persists and falls back; keys in every list; host names itself, applies quality in place; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` updated and passing.
- [ ] VIS-017-T11 [P] [US5] `SignedDistanceUITests`: choose SDF Shapes, Quality offered at Medium, Bars not, choose High, value updates, source started once (< 30 s).

## Phase 5: Polish

- [ ] VIS-017-T12 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-017-T13 {device} On D1 with music, SDF Shapes at each quality: frame rate on the PERF-001/007 overlay, look, Reduce Motion calm; binary archive hit on second launch (PERF-009).

## Dependencies

T01, T02 → T03 → T04; T03 → T05 → T06, T07, T08, T09 → T10, T11; all → T12. T13 needs a device.

## Implementation strategy

MVP = T01-T04 (the acceptance proven on the CPU mirror), then the GPU proof (T05-T08), then the app (T09-T11).

## Analyze notes (speckit-analyze, 2026-11-15)

- Coverage: R1 T05; R2 T01, T04; R3-R5 T01, T04, T06; R6 T02, T04; R7 T07; R8, R10, R11 T09-T11; R9 T08; R12 T12.
  S1 T04, T06; S2 T04, T06; S3 T06, T08; S4 T07; S5 T10, T11; S6 T12. No constitution conflict (no new compile site,
  no dependency, no networking, nothing reaches projectM).
- Fix applied (coverage): US1 scenario 2 ("the whole scene stays inside its bounding volume") had no explicit
  assertion; T04 now checks the scene distance on the bounding sphere for extreme poses.
- Fix applied (coverage): the edge case "switching to and from the other noise-field modes starts from the initial
  pose" is asserted in T06 (restart and re-entry reset the drive) and T10 (in-place host switch).
