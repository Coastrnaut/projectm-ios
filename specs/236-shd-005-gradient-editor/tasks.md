# Tasks: SHD-005 Gradient Editor

**Input**: Design documents from `specs/236-shd-005-gradient-editor/`
**Tests**: requested by the spec (acceptance is test-proven: GPU readback at stops, CPU reference, golden, UI test).

## Phase 1: Setup

- [X] SHD-005-T01 Create simulator "SHD5 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm `Build` symlink and preset submodules in the worktree — Verified 2026-11-14: simulator SHD5 iPhone 17 (iOS 27.2) created, xcodegen generate, Build symlink present, preset submodules initialised

## Phase 2: Foundational (blocks all stories)

- [X] SHD-005-T02 `GradientRampStop`, `GradientInterpolation`, `GradientRamp` (init 2…8 stops, stable sort, `color(at:)` per contract G2, `shaderStops`) in `Packages/VisualGenerators/Sources/VisualGenerators/GradientRamp.swift` — Verified 2026-11-14: `swift test --filter GradientRampTests` (VisualGenerators, 7 tests)
- [X] SHD-005-T03 [P] CPU tests: exact colour and alpha at every stop for each mode, equal positions (later wins), outside the ends, Step holds, sRGB vs Smooth midpoints, 2…8 limits, in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/GradientRampTests.swift` — Verified 2026-11-14: `GradientRampTests` 7 tests pass in 0.003 s on the host; also under `-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` (Linux shape)

## Phase 3: User Story 2 - The drawn gradient honours the stored stops (P1) 🎯 acceptance

**Goal**: GPU and CPU agree and are exact at stops. **Independent test**: `MaterialGradientRampTests`.

- [X] SHD-005-T04 [US2] `ProceduralMaterials` depends on VisualGenerators (`Packages/Compositor/Package.swift`); `GradientRampUniforms` (272 bytes) and the ramp evaluation inside `mat_gradient` (count 0 = old picture) in `ProceduralMaterialShaders.swift`; `ProceduralMaterialLayer.setGradient(_:)` binding buffer 1 every frame — Verified 2026-11-14: `MaterialGradientRampTests` on the host GPU; `MaterialRenderTests.testGoldenSignatures` (Gradient Field without a ramp) and the SHD-003 slot check still pass; check_compliance OK
- [X] SHD-005-T05 [US2] GPU tests in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialGradientRampTests.swift`: 512 × 512 picture, phase 0, 4 stops on pixel centres with alphas < 1; for each mode every stop's pixel equals the stored sRGB colour and alpha within 1/255; between stops GPU vs `GradientRamp.color(at:)` within 2/255; golden signature of one ramp; existing Gradient Field golden unchanged without a ramp — Verified 2026-11-14: `MaterialGradientRampTests` 4 tests pass on the Mac Studio host GPU: every stop of every mode within 1/255 (colour and alpha), Step holds before the next stop, GPU vs CPU within 2/255, golden signature, clear restores the old picture; ProceduralMaterialsTests 50 pass in 4.0 s

## Phase 4: User Story 1 - Shape a gradient (P1)

**Goal**: stop detail stored and editable. **Independent test**: SceneFormat tests, app unit tests, UI test.

- [X] SHD-005-T06 [US1] `ColorPalette` stop detail (`positions`, `alphas`, `interpolation`, `stopPositions`, `stopAlphas`, `hasStopDetail`), validation, `PaletteLibrary.setStopPosition/setStopAlpha/setInterpolation`, add/remove/duplicate keep detail, file fields in `Packages/SceneFormat/Sources/SceneFormat/ScenePalettes.swift` — Verified 2026-11-14: `PaletteGradientStopsTests` 5 tests; SceneFormat 195 tests and LibraryBackup 83 tests pass
- [X] SHD-005-T07 [P] [US1] Tests in `Packages/SceneFormat/Tests/SceneFormatTests/PaletteGradientStopsTests.swift`: palettes without detail encode byte-identically; detail round trip; invalid detail drops the entry; neighbour clamping; add/remove; built-in refused — Verified 2026-11-14: `PaletteGradientStopsTests` 5 tests pass in 0.004 s (UIX-011 bytes unchanged, round trip, 7 malformed entries dropped, clamping, add/remove/duplicate)
- [X] SHD-005-T08 [US1] `PaletteRamp.gradient` in `VisualPalette.swift` (colour × alpha, opaque); `PaletteCoordinator.gradientRamp(for:)`, `visualPalette(for:)` uses it only with detail; edit forwarding (`setStopPosition`, `setStopAlpha`, `setInterpolation`) — Verified 2026-11-14: `PaletteAppTests.testStopEditsSaveAndTheVisualDrawsTheStoredStops` on SHD5 iPhone 17 (iOS 27.2)
- [X] SHD-005-T09 [US1] Editor UI: `Apps/projectM-iOS/Views/PaletteGradientStops.swift` (Interpolation picker, per-stop Position and Alpha sliders with ACC-005 `.accessibleParameter`, stop labels) shown for gradient-style user palettes; `PaletteStrip` draws positions, alpha (over black) and Step bands — Verified 2026-11-14: app builds with the type-check flags (no warnings in the touched files); `PaletteGradientEditorUITests` on SHD5 iPhone 17
- [X] SHD-005-T10 [P] [US1] App unit tests in `Apps/projectM-iOS/Tests/PaletteAppTests.swift`: ramp mapping exact at stops, palettes without detail map as before, coordinator edits save — Verified 2026-11-14: `PaletteAppTests` 5 tests and `LibraryBackupAppTests` 5 tests pass on SHD5 iPhone 17
- [X] SHD-005-T11 [US1][US3] UI test `Apps/projectM-iOS/UITests/PaletteGradientEditorUITests.swift`: new palette, Stop 2 position adjusted, value read back, Step chosen (under 30 s) — Verified 2026-11-14: `PaletteGradientEditorUITests.testMoveAStopAndChooseStep` passed in 25.3 s; `PalettePickerUITests` still passes (23.7 s)

## Phase 5: Polish

- [X] SHD-005-T12 Linux shape (VisualGenerators `-DVISUAL_NO_METAL`, Compositor `-DCOMPOSITOR_NO_METAL`), package suites, type-check budget, repo checks (compliance, docs, motion, permission catalog, status events, scripts), privacy manifest and network symbols on the Debug app, `LibraryBackupAppTests` keys test; spec status — Verified 2026-11-14: Linux shape builds (VisualGenerators, Compositor); VisualGenerators 260 tests (37.6 s), Compositor targets all pass (ProceduralMaterials 50 in 4.0 s); compliance, validate_docs, motion policy, permission catalog, status events OK; test_scripts 177 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app; no new UserDefaults keys
- [ ] SHD-005-T13 {device} Look at a gradient palette with moved stops, alpha and Step on D1

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R2 → T02-T03, T05; R3-R4 → T06-T07; R5 → T08, T10; R6 → T04-T05; R7 → T09, T11; R8 → T12.
S1-S2 → T05; S3 → T05 (Gradient Field golden), T07 (bytes), T10 (mapping); S4 → T11; S5 → T12. Fix applied: T05
also checks the Step mode's sample just before the next stop equals the held stop (spec edge case "Step exactly at a
stop"). No constitution conflicts; no unmapped tasks.
