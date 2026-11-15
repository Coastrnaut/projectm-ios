# Implementation Plan: SHD-005 Gradient Editor

**Branch**: `feature/shd-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/236-shd-005-gradient-editor/spec.md`

## Summary

One gradient model, three users. VisualGenerators gains `GradientRamp` (2…8 stops: position, 8-bit sRGB colour,
alpha; mode Smooth / sRGB / Step) with the CPU reference evaluation (SHD-005-R2) and the shader packing.
SceneFormat's `ColorPalette` gains optional stop detail (`positions` in thousandths, `alphas` 0…255,
`interpolation`), written to `palettes.json` only when not default, with editing operations on `PaletteLibrary`.
The app maps a palette with stop detail to `VisualPalette.custom(PaletteRamp(gradient:))` (colour × alpha on
black) and adds stop rows (Position and Alpha ACC-005 sliders) and an Interpolation picker to the palette editor.
`ProceduralMaterialLayer` accepts an optional `GradientRamp`; `mat_gradient` in the reviewed module shader constant
evaluates it from a 272-byte uniform block at fragment buffer 1 (count 0 = the old two-colour picture).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0), Xcode 27.2 (CI also Xcode 26)
**Primary Dependencies**: VisualGenerators (VIS-001, UIX-011 `PaletteRamp`), SceneFormat (UIX-011 palettes), ProceduralMaterials (SHD-001), SwiftUI (app), Metal
**Storage**: `palettes.json` (three optional per-palette fields, no version bump); no UserDefaults keys
**Testing**: XCTest — `GradientRampTests` (CPU, Linux shape), `ScenePalettesTests` additions (model, file), `MaterialGradientRampTests` (GPU readback at stops per mode, CPU-vs-GPU between stops, golden signature), app unit tests (`PaletteAppTests`), one UI test on "SHD5 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+/macOS 15 packages; Linux for the CPU parts
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: palette evaluation per bar is a ≤ 8-step loop; GPU: one small uniform block per frame, ≤ 8-step loop per pixel
**Constraints**: SHD-011 (no new Metal source file); unchanged pictures without stop detail; Xcode 26 type-check budget; short tests
**Scale/Scope**: 1 model, 3 file fields, 4 library operations, 1 shader helper, 1 editor section

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI `Slider`, `Picker`, `LinearGradient`; Metal `setFragmentBytes`. |
| VI Modular boundaries | Pass: model and reference in VisualGenerators (plain Swift), storage in SceneFormat (plain Swift), GPU in ProceduralMaterials; app maps between them. |
| VII Real-time audio safety | Pass: nothing on audio threads; render packs a fixed-size struct (no allocation). |
| X Evidence-based quality | Pass: GPU readback at every stop for every mode, CPU reference, golden, UI test; device look `{device}`. |
| SHD-011 / ADR-0024 | Pass: evaluation is part of `ProceduralMaterialShaders.source`; `MaterialSourceSafetyTests` unchanged. |
| Accessibility (ACC-005) | Pass: sliders use `.accessibleParameter`; stop rows have spoken labels. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  GradientRamp.swift                 # new: GradientRampStop, GradientInterpolation, GradientRamp (evaluation, shader stops)
  VisualPalette.swift                # PaletteRamp.gradient (optional)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/GradientRampTests.swift
Packages/SceneFormat/Sources/SceneFormat/
  ScenePalettes.swift                # stop detail on ColorPalette, editing ops, file fields
Packages/SceneFormat/Tests/SceneFormatTests/PaletteGradientStopsTests.swift
Packages/Compositor/Package.swift    # ProceduralMaterials depends on VisualGenerators
Packages/Compositor/Sources/ProceduralMaterials/
  ProceduralMaterialShaders.swift    # GradientRampUniforms + mat_ramp helper in mat_gradient
  ProceduralMaterialLayer.swift      # setGradient(_:), bind buffer 1
Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialGradientRampTests.swift
Apps/projectM-iOS/Coordinators/PaletteCoordinator.swift   # ramp mapping, stop edit forwarding
Apps/projectM-iOS/Views/PaletteGradientStops.swift        # new: stop rows, interpolation picker
Apps/projectM-iOS/Views/PaletteViews.swift                # strip honours positions/alpha; section added
Apps/projectM-iOS/Tests/PaletteAppTests.swift, UITests/PaletteGradientEditorUITests.swift
```

**Structure Decision**: extend existing targets; no new package or target.

## Complexity Tracking

None.
