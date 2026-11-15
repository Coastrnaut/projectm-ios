# Tasks: VIS-018 Geometric Tessellation

**Input**: `specs/307-vis-018-geometric-tessellation/` (spec, plan, research, data-model, contracts/tessellation.md)

## Phase 1: Foundational - model (VIS-018-R2 to R8)

- [X] VIS-018-T01 `TessellationTiling` (5 cases, default `hexagon`), `TessellationPalette` (`spectrum` default, `ice`, `mono`), `TessellationSettings` ("`tiles: Int` 2…16 (default 6), `symmetry: Int` ∈ {1, 2, 3, 4, 6} (default 6), `mirror: Bool` (default false)"; `clamped()`), `TessellationPlacement`, `TessellationCell`, `TessellationLattice` (classify, polygon, inradius, colouring value) and `TessellationShader` (MSL text, same arithmetic) in `Packages/VisualGenerators/Sources/VisualGenerators/TessellationLattice.swift`. — Verified 2026-11-15: swift test --filter "Tessellation(Alignment|Drive)Tests" 13 run, 1 skipped (the on-demand sweep), 0 failures: host 3.4 s for the per-pixel test, 0.9 s A1/A2 (1,036,559 mirrored pairs, 0 failures), 0.24 s A5; Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) 6.6 s
- [X] VIS-018-T02 `TessellationDrive` and `TessellationFrame` (swell, drift, light, brightness on the injected clock; Reduce Motion; sanitizing) in `Packages/VisualGenerators/Sources/VisualGenerators/TessellationDrive.swift`. — Verified 2026-11-15: swift test --filter "Tessellation(Alignment|Drive)Tests" 13 run, 1 skipped (the on-demand sweep), 0 failures: host 3.4 s for the per-pixel test, 0.9 s A1/A2 (1,036,559 mirrored pairs, 0 failures), 0.24 s A5; Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) 6.6 s
- [X] VIS-018-T03 `NoiseFieldConfiguration.tessellation` (+ factory, `clamped()` turns the other modes off, effective palette) in `Packages/VisualGenerators/Sources/VisualGenerators/NoiseFieldConfiguration.swift`. — Verified 2026-11-15: swift test --filter "Tessellation(Alignment|Drive)Tests" 13 run, 1 skipped (the on-demand sweep), 0 failures: host 3.4 s for the per-pixel test, 0.9 s A1/A2 (1,036,559 mirrored pairs, 0 failures), 0.24 s A5; Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) 6.6 s

## Phase 2: User Story 2 - alignment on the CPU (R3, R4; S1) 🎯 acceptance

- [X] VIS-018-T04 [US2] `TessellationAlignmentTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/TessellationAlignmentTests.swift`): for 5 tilings × N 2…16 × 6 aspect ratios at a 48 × 48 sample grid: A1 (mirror pixel → mirrored tile centre ≤ 0.01 px), A2 (tile size = shorter/N; squares: N whole squares across the shorter side, seams on both shorter edges), A5 (same tile at the same normalized offset across aspect ratios); per pixel at quarter scale for N ∈ {2, 7, 16} and two aspect ratios: A3 (bounding boxes of whole tiles of one shape differ ≤ 1 px), A4 (polygon contains the pixel, edge distance agrees, no other neighbouring polygon contains it); points exactly on seams and vertices classify deterministically into one tile; full per-pixel sweep behind `VIS018_ALIGNMENT_SWEEP=1`. Runs in the Linux shape. — Verified 2026-11-15: swift test --filter "Tessellation(Alignment|Drive)Tests" 13 run, 1 skipped (the on-demand sweep), 0 failures: host 3.4 s for the per-pixel test, 0.9 s A1/A2 (1,036,559 mirrored pairs, 0 failures), 0.24 s A5; Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) 6.6 s
- [X] VIS-018-T05 [P] [US3] [US4] `TessellationDriveTests`: symmetry (k-fold rotations and, mirrored, reflections of tile centres give equal colouring values; chiral without mirror), palette resolution, settings clamping, drive bounds (inset 0.08…0.25, speeds capped, Reduce Motion half, time backwards, long gap, NaN bands), finite colours for extreme inputs. — Verified 2026-11-15: swift test --filter "Tessellation(Alignment|Drive)Tests" 13 run, 1 skipped (the on-demand sweep), 0 failures: host 3.4 s for the per-pixel test, 0.9 s A1/A2 (1,036,559 mirrored pairs, 0 failures), 0.24 s A5; Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) 6.6 s

## Phase 3: User Stories 1 + 4 - the picture on Metal and its safety (R1, R7 to R9, R11, R14; S2 to S5)

- [X] VIS-018-T06 [US1] Mode `.tessellation` in `NoiseFieldGenerator` (pipeline, drive, flash sampling, 8-float block at buffer 1, entry points `vis_tess_fragment` and test-only `vis_tess_cells_fragment`, restart) and `NoiseFieldFlashAreas.sampleTessellation`. — Verified 2026-11-15: swift build and TessellationRenderTests on the host GPU (the mode draws through vis_tess_fragment; uniforms, restart and re-entry asserted)
- [X] VIS-018-T07 [US1] [US2] `TessellationRenderTests` (GPU): per tiling × N ∈ {2, 5, 16} × 6 aspect ratios, the cell view (rgba32Float) equals the CPU tile at every pixel more than 0.01 px from a seam (S2); extreme bands and time render finite in 0…1 (S3); two renders identical; A6: the cell view is identical after frames with loud bands, a 10⁹ s time and every symmetry/palette setting (the lattice depends only on size, tiling and N); settings change in place; entering the mode and a loop restart reset the drive. — Verified 2026-11-15: TessellationRenderTests 5 passed (0.96 s host): 1,388,472 pixels equal the CPU lattice over 5 tilings × N 2/5/16 × 6 aspect ratios (15,528 within 0.01 px of a seam skipped), worst edge difference 1.9e-5 px; cell view unchanged after loud frames, a 10⁹ s time and every symmetry/mirror/palette; extreme inputs finite in 0…1; two renders identical; GPU tile colours equal the CPU mirror (≤ 3e-3); in place and re-entry
- [X] VIS-018-T08 [US4] `TessellationFlashTests`: bass bursts alternating with silence within the transition budget in all 17 areas, Reduce flashing on and off; sample luminance ≤ 0.75. — Verified 2026-11-15: TessellationFlashTests 2 passed (0.17 s host): samples ≤ 0.75 luminance; bursts every 0.1 s for 2 s worst 1/1 transitions per window with Reduce flashing on (limit 4), 1 portrait / 6 landscape with the strongest glow off (limit 6)
- [X] VIS-018-T09 [US1] `TessellationGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry. — Verified 2026-11-15: recorded on the macOS host and on VIS18 iPhone 17 (iOS 27.2), then identical (SSIM 1.0) on both; RenderGoldens --filter "TessellationGolden|GoldenIntegrity" 27 passed (1.3 s host); simulator TessellationGolden + integrity 3 passed (5.3 s)

## Phase 4: User Story 5 - the app (R10, R12, R13; S6)

- [X] VIS-018-T10 [US5] Visual choice `tessellation` ("Tessellation"), five keys (`AppSettings.allKeys`, `ALLOWED_KEYS` in `scripts/run_device_tests.py`, FILE-005 `LibrarySettingsPolicy.includedKeys`), `TessellationOptions`, host style `.tessellation(TessellationSettings)` built and updated in place (`Apps/projectM-iOS/Visuals/TessellationHostSupport.swift`), accessibility value, scene capture as no layer, onChange in a small new chain (`withTessellationChanges`). — Verified 2026-11-15: xcodebuild build-for-testing on VIS18 iPhone 17 (iOS 27.2) with the type-check flags: TEST BUILD SUCCEEDED; the only type-check warning is AppCoordinator's untouched initializer (582 ms, also reported by VIS-017)
- [X] VIS-018-T11 [P] [US5] `TessellationAppTests` (settings persist and fall back; keys in every list; host names itself, applies settings in place, the colour-blind-safe palette wins over the tessellation's own (US3 scenario 3); scene capture no layer); `SettingsTests.testOnlyTheSettingsKeysAreWritten`, `CameraVisualTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` updated and passing. — Verified 2026-11-15: xcodebuild test-without-building: TessellationAppTests 4, SettingsTests, CameraVisualTests, LibraryBackupAppTests, LibraryEraseAppTests, SignedDistanceAppTests (32 passed, 2.0 s)
- [X] VIS-018-T12 [P] [US5] `TessellationUITests`: choose Tessellation, options offered at their defaults, Bars not, change Tiles, value updates, source started once (< 30 s). — Verified 2026-11-15: TessellationUITests passed in 25.1 s on VIS18 iPhone 17 (iOS 27.2)

## Phase 5: Polish

- [ ] VIS-018-T13 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-018-T14 {device} On D1, D2 and an external display: Tessellation at N 2 → 16 in portrait and landscape: centre fixed, seams straight; frame rate on the PERF-001/007 overlay; Reduce Motion calm.

## Dependencies

T01, T02 → T03 → T04, T05; T03 → T06 → T07, T08, T09, T10 → T11, T12; all → T13. T14 needs devices.

## Parallel opportunities

T04 and T05 (different test files); T11 and T12 after T10.

## Implementation strategy

MVP = T01-T04 (the acceptance proven on the CPU), then the GPU proof (T06-T09), then the app (T10-T12).

## Analyze notes (speckit-analyze, 2026-11-15)

- Coverage: R1 T06; R2 T01, T04; R3, R4 T04, T07; R5 T05; R6 T03, T05, T11; R7 T02, T05; R8 T05, T07; R9 T08;
  R10, R12, R13 T10-T12; R11 T09; R14 T13. S1 T04; S2 T07; S3 T05, T07; S4 T07, T09; S5 T08; S6 T11, T12; S7 T13.
  No constitution conflict (no new compile site, no dependency, no networking, nothing reaches projectM). 0 critical,
  0 high.
- Fix applied (coverage, MEDIUM): A6's "the lattice depends only on size, tiling and N" had no GPU assertion; T07 now
  compares the cell view across loud bands, a huge time and every symmetry/palette setting.
- Fix applied (coverage, MEDIUM): US3 scenario 3 (colour-blind-safe wins) is asserted in T11.
- Fix applied (edge case, LOW): pixels exactly on a seam classify into exactly one tile (T04).
