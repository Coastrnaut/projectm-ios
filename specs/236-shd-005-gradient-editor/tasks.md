# Tasks: SHD-005 Gradient Editor

**Input**: Design documents from `specs/236-shd-005-gradient-editor/`
**Tests**: requested by the spec (acceptance is test-proven: GPU readback at stops, CPU reference, golden, UI test).

## Phase 1: Setup

- [ ] SHD-005-T01 Create simulator "SHD5 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm `Build` symlink and preset submodules in the worktree

## Phase 2: Foundational (blocks all stories)

- [ ] SHD-005-T02 `GradientRampStop`, `GradientInterpolation`, `GradientRamp` (init 2…8 stops, stable sort, `color(at:)` per contract G2, `shaderStops`) in `Packages/VisualGenerators/Sources/VisualGenerators/GradientRamp.swift`
- [ ] SHD-005-T03 [P] CPU tests: exact colour and alpha at every stop for each mode, equal positions (later wins), outside the ends, Step holds, sRGB vs Smooth midpoints, 2…8 limits, in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/GradientRampTests.swift`

## Phase 3: User Story 2 - The drawn gradient honours the stored stops (P1) 🎯 acceptance

**Goal**: GPU and CPU agree and are exact at stops. **Independent test**: `MaterialGradientRampTests`.

- [ ] SHD-005-T04 [US2] `ProceduralMaterials` depends on VisualGenerators (`Packages/Compositor/Package.swift`); `GradientRampUniforms` (272 bytes) and the ramp evaluation inside `mat_gradient` (count 0 = old picture) in `ProceduralMaterialShaders.swift`; `ProceduralMaterialLayer.setGradient(_:)` binding buffer 1 every frame
- [ ] SHD-005-T05 [US2] GPU tests in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialGradientRampTests.swift`: 500 × 500 picture, phase 0, 4 stops on pixel centres with alphas < 1; for each mode every stop's pixel equals the stored sRGB colour and alpha within 1/255; between stops GPU vs `GradientRamp.color(at:)` within 2/255; golden signature of one ramp; existing Gradient Field golden unchanged without a ramp

## Phase 4: User Story 1 - Shape a gradient (P1)

**Goal**: stop detail stored and editable. **Independent test**: SceneFormat tests, app unit tests, UI test.

- [ ] SHD-005-T06 [US1] `ColorPalette` stop detail (`positions`, `alphas`, `interpolation`, `stopPositions`, `stopAlphas`, `hasStopDetail`), validation, `PaletteLibrary.setStopPosition/setStopAlpha/setInterpolation`, add/remove/duplicate keep detail, file fields in `Packages/SceneFormat/Sources/SceneFormat/ScenePalettes.swift`
- [ ] SHD-005-T07 [P] [US1] Tests in `Packages/SceneFormat/Tests/SceneFormatTests/PaletteGradientStopsTests.swift`: palettes without detail encode byte-identically; detail round trip; invalid detail drops the entry; neighbour clamping; add/remove; built-in refused
- [ ] SHD-005-T08 [US1] `PaletteRamp.gradient` in `VisualPalette.swift` (colour × alpha, opaque); `PaletteCoordinator.gradientRamp(for:)`, `visualPalette(for:)` uses it only with detail; edit forwarding (`setStopPosition`, `setStopAlpha`, `setInterpolation`)
- [ ] SHD-005-T09 [US1] Editor UI: `Apps/projectM-iOS/Views/PaletteGradientStops.swift` (Interpolation picker, per-stop Position and Alpha sliders with ACC-005 `.accessibleParameter`, stop labels) shown for gradient-style user palettes; `PaletteStrip` draws positions, alpha (over black) and Step bands
- [ ] SHD-005-T10 [P] [US1] App unit tests in `Apps/projectM-iOS/Tests/PaletteAppTests.swift`: ramp mapping exact at stops, palettes without detail map as before, coordinator edits save
- [ ] SHD-005-T11 [US1][US3] UI test `Apps/projectM-iOS/UITests/PaletteGradientEditorUITests.swift`: new palette, Stop 2 position adjusted, value read back, Step chosen (under 30 s)

## Phase 5: Polish

- [ ] SHD-005-T12 Linux shape (VisualGenerators `-DVISUAL_NO_METAL`, Compositor `-DCOMPOSITOR_NO_METAL`), package suites, type-check budget, repo checks (compliance, docs, motion, permission catalog, status events, scripts), privacy manifest and network symbols on the Debug app, `LibraryBackupAppTests` keys test; spec status
- [ ] SHD-005-T13 {device} Look at a gradient palette with moved stops, alpha and Step on D1
