# Tasks: VIS-018 Geometric Tessellation

**Input**: `specs/307-vis-018-geometric-tessellation/` (spec, plan, research, data-model, contracts/tessellation.md)

## Phase 1: Foundational - model (VIS-018-R2 to R8)

- [ ] VIS-018-T01 `TessellationTiling` (5 cases, default `hexagon`), `TessellationPalette` (`spectrum` default, `ice`, `mono`), `TessellationSettings` ("`tiles: Int` 2…16 (default 6), `symmetry: Int` ∈ {1, 2, 3, 4, 6} (default 6), `mirror: Bool` (default false)"; `clamped()`), `TessellationPlacement`, `TessellationCell`, `TessellationLattice` (classify, polygon, inradius, colouring value) and `TessellationShader` (MSL text, same arithmetic) in `Packages/VisualGenerators/Sources/VisualGenerators/TessellationLattice.swift`.
- [ ] VIS-018-T02 `TessellationDrive` and `TessellationFrame` (swell, drift, light, brightness on the injected clock; Reduce Motion; sanitizing) in `Packages/VisualGenerators/Sources/VisualGenerators/TessellationDrive.swift`.
- [ ] VIS-018-T03 `NoiseFieldConfiguration.tessellation` (+ factory, `clamped()` turns the other modes off, effective palette) in `Packages/VisualGenerators/Sources/VisualGenerators/NoiseFieldConfiguration.swift`.

## Phase 2: User Story 2 - alignment on the CPU (R3, R4; S1) 🎯 acceptance

- [ ] VIS-018-T04 [US2] `TessellationAlignmentTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/TessellationAlignmentTests.swift`): for 5 tilings × N 2…16 × 6 aspect ratios at a 48 × 48 sample grid: A1 (mirror pixel → mirrored tile centre ≤ 0.01 px), A2 (tile size = shorter/N; squares: N whole squares across the shorter side, seams on both shorter edges), A5 (same tile at the same normalized offset across aspect ratios); per pixel at quarter scale for N ∈ {2, 7, 16} and two aspect ratios: A3 (bounding boxes of whole tiles of one shape differ ≤ 1 px), A4 (polygon contains the pixel, edge distance agrees, no other neighbouring polygon contains it); full per-pixel sweep behind `VIS018_ALIGNMENT_SWEEP=1`. Runs in the Linux shape.
- [ ] VIS-018-T05 [P] [US3] [US4] `TessellationDriveTests`: symmetry (k-fold rotations and, mirrored, reflections of tile centres give equal colouring values; chiral without mirror), palette resolution, settings clamping, drive bounds (inset 0.08…0.25, speeds capped, Reduce Motion half, time backwards, long gap, NaN bands), finite colours for extreme inputs.

## Phase 3: User Stories 1 + 4 - the picture on Metal and its safety (R1, R7 to R9, R11, R14; S2 to S5)

- [ ] VIS-018-T06 [US1] Mode `.tessellation` in `NoiseFieldGenerator` (pipeline, drive, flash sampling, 8-float block at buffer 1, entry points `vis_tess_fragment` and test-only `vis_tess_cells_fragment`, restart) and `NoiseFieldFlashAreas.sampleTessellation`.
- [ ] VIS-018-T07 [US1] [US2] `TessellationRenderTests` (GPU): per tiling × N ∈ {2, 5, 16} × 6 aspect ratios, the cell view (rgba32Float) equals the CPU tile at every pixel more than 0.01 px from a seam (S2); extreme bands and time render finite in 0…1 (S3); two renders identical; settings change in place; entering the mode and a loop restart reset the drive.
- [ ] VIS-018-T08 [US4] `TessellationFlashTests`: bass bursts alternating with silence within the transition budget in all 17 areas, Reduce flashing on and off; sample luminance ≤ 0.75.
- [ ] VIS-018-T09 [US1] `TessellationGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 4: User Story 5 - the app (R10, R12, R13; S6)

- [ ] VIS-018-T10 [US5] Visual choice `tessellation` ("Tessellation"), five keys (`AppSettings.allKeys`, `ALLOWED_KEYS` in `scripts/run_device_tests.py`, FILE-005 `LibrarySettingsPolicy.includedKeys`), `TessellationOptions`, host style `.tessellation(TessellationSettings)` built and updated in place (`Apps/projectM-iOS/Visuals/TessellationHostSupport.swift`), accessibility value, scene capture as no layer, onChange in a small new chain (`withTessellationChanges`).
- [ ] VIS-018-T11 [P] [US5] `TessellationAppTests` (settings persist and fall back; keys in every list; host names itself, applies settings in place; scene capture no layer); `SettingsTests.testOnlyTheSettingsKeysAreWritten`, `CameraVisualTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` updated and passing.
- [ ] VIS-018-T12 [P] [US5] `TessellationUITests`: choose Tessellation, options offered at their defaults, Bars not, change Tiles, value updates, source started once (< 30 s).

## Phase 5: Polish

- [ ] VIS-018-T13 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-018-T14 {device} On D1, D2 and an external display: Tessellation at N 2 → 16 in portrait and landscape: centre fixed, seams straight; frame rate on the PERF-001/007 overlay; Reduce Motion calm.

## Dependencies

T01, T02 → T03 → T04, T05; T03 → T06 → T07, T08, T09, T10 → T11, T12; all → T13. T14 needs devices.

## Parallel opportunities

T04 and T05 (different test files); T11 and T12 after T10.

## Implementation strategy

MVP = T01-T04 (the acceptance proven on the CPU), then the GPU proof (T06-T09), then the app (T10-T12).
