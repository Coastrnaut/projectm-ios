# Implementation Plan: FX-003 Color Grading

**Branch**: `feature/fx-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add a colour-grading step to the compositor's existing output shader (`cmp_output` in
`Packages/Compositor/Sources/Compositor/CompositorShaders.swift`), in linear light on the finished composite,
before FX-002's tone map: temperature (a luminance-normalised red/blue gain), then lift, gamma and gain (the
classic master formula), then saturation around Rec. 709 luminance (research FX-003-D2). The CPU derives the
operator coefficients from the five values once per change (`ColorGrade.coefficients`, Double, rounded to
Float) and passes them as a 48-byte block with one flag bit per active operator; at neutral the flags are 0
and the shader returns the composite pixel untouched, so the output is bit-identical to bypass for every
pixel (D3). The flash guard's samples go through the same graded-then-tone-mapped function (one Swift string
spliced into both sources), so the limiter judges what is shown (D5). A plain-Swift reference
(`ColorGrade.apply`, Linux-testable) mirrors the shader; GPU tests compare the two.

The five values are MOD-001 parameters (`ColorGradeCatalog` in a new small target `ColorGradeParameters`,
registered in the app's scene registry and the golden renderer's), and one global app setting
(`ColorGradeSetting`, five UserDefaults keys, FILE-005 backup and the privacy allow-list). Settings gets a
"Color" section (five ACC-005 sliders, help, "Reset to neutral"). The four compositor-backed visual hosts
pass the grade to their compositor. Native spectra and projectM are not graded (spec Clarifications).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time with safe math
(ADR-0009 decision 3)
**Primary Dependencies**: Metal (existing output and flash-guard pipelines; `setFragmentBytes` /
`setBytes`, no new buffers); ParameterGraph (MOD-001 descriptors); SwiftUI (Settings section)
**Storage**: five UserDefaults Doubles `settings.colorGrade.temperature|lift|gamma|gain|saturation` (absent →
neutral)
**Testing**: XCTest. Compositor: `ColorGradeReferenceTests` (CPU, Linux shape), `ColorGradeOutputTests` (GPU:
neutral vs bypass on a reference image, operators vs reference, flash guard, GPU timing record),
`ColorGradeCatalogTests`. App: `ColorGradeSettingTests`, `ColorGradeUITests` (Settings section). Regressions:
Compositor, VisualGenerators, RenderGoldens, SceneFormat, ImportFuzz, LibraryBackup, app unit tests on an own
simulator, script tests
**Target Platform**: iPhone and iPad (Apple GPUs); the Mac host for package tests; Linux for the reference
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: no new pass, texture or per-frame allocation; at most ~20 ALU ops per output pixel
when active, one uniform branch when neutral
**Constraints**: neutral bit-identical (goldens unchanged); explicit closure types and typed steps;
`CompositeFlashGuard` edit limited to the sample read and one bound block (ACC-012 edits FX-019 parameters in
parallel); `Compositor.swift` and `SceneTransitionBus.swift` edits limited to a `colorGrade` property and
binding its block; `makeLibrary(source:)` stays in `CompositorShaders.swift` (SHD-011 allow-list); SwiftUI
bodies small (`-warn-long-function-bodies=300`, `-warn-long-expression-type-checking=150`)
**Scale/Scope**: 3 new package source files, 1 new app setting and 1 view, ~6 edited source files, 4 new
test files, ADR-0049 (output pipeline contract extended)

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal render/compute encoders and run-time source compile already allowed; SwiftUI | Pass |
| VI Modular boundaries | Grading maths and shader in `Packages/Compositor`; the catalog in its own target; the app only sets a value | Pass |
| VII Real-time safety | GPU only; coefficients derived on change, not per frame; `setBytes` copies 48 bytes | Pass |
| VIII Upstream fidelity | Neutral bypass is bit-identical; projectM's path untouched | Pass |
| X Evidence | Shader and reference unit tests on the Mac; device GPU check is a `{device}` task | Pass |
| Sensory safety (FX-019, ACC-012) | The limiter measures the graded, tone-mapped colour | Pass |
| Privacy | Five numeric settings on the device; allow-listed; nothing sent | Pass |

Post-design re-check: unchanged, Pass. ADR-0049 records the output pipeline's new stage order (grade → tone
map → × gain) and the flash guard measuring it.

## Project Structure

```text
specs/123-fx-003-color-grading/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/color-grade.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/ColorGrade.swift                 (new: value, ranges, coefficients, reference)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift          (cmp_grade, cmp_display, cmp_output, GradeBlock)
Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift        (samples through cmp_display)
Packages/Compositor/Sources/Compositor/Compositor.swift                 (colorGrade; block bound in output passes and guard)
Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift         (same)
Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift (new: MOD-001 descriptors)
Packages/Compositor/Package.swift                                       (new target + test target)
Packages/Compositor/Tests/CompositorTests/ColorGradeReferenceTests.swift (new, CPU)
Packages/Compositor/Tests/CompositorTests/ColorGradeOutputTests.swift    (new, GPU)
Packages/Compositor/Tests/CompositorTests/OutputPassRig.swift            (grade block argument)
Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift (new)
Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift (registry + catalog)
Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift                  (new)
Apps/projectM-iOS/Views/ColorGradeSection.swift                         (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, SceneArchiveService.swift, Visuals/*VisualHost.swift
Apps/projectM-iOS/Views/SettingsView.swift, ProjectMApp.swift (wiring)
Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift, UITests/ColorGradeUITests.swift (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (keys)
docs/adr/0049-output-color-grade.md (number checked before commit)
```

**Structure Decision**: the value and its reference sit in the `Compositor` target beside `ToneMap` and
`LayerBlend` (CPU references of shaders), so they build on Linux and the GPU tests import them directly. The
MOD-001 descriptors need ParameterGraph, which the `Compositor` target does not depend on (ADR-0013's
boundary); a small `ColorGradeParameters` target (Compositor + ParameterGraph) holds them, as
`ProceduralMaterials` holds the material descriptors. `VisualParameterCatalog` cannot hold them: the
VisualGenerators package cannot depend on Compositor (package cycle).

## Complexity Tracking

None.
