# Implementation Plan: FX-005 Contrast Curves

**Branch**: `feature/fx-005` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add a contrast curve as the seventh (last) operator of FX-003's colour grade, after FX-004's hue (research
FX-005-D1). The operator first brings the colour into display range with FX-002's tone map step (luminance and hue
kept; identity for in-range colours), then applies one monotone curve to each channel (D2): S-curve, a two-sided
power curve around mid-grey 0.18 with slope 1 + strength at the pivot (D3), or Filmic, a fixed toe ∘ shoulder curve
(x²(1 + τ)/(x + τ), then y(1 + σ)/(y + σ), τ = 0.1, σ = 0.5) blended with the identity by strength (D4). Both map
0 → 0 and 1 → 1 exactly and are clamped to 0…1 (D5). Linear or strength 0 leaves the operator's flag off, so every
earlier output, and the neutral bypass, is unchanged bit for bit. The CPU passes four coefficients in a new
`float4 contrast` appended to FX-003's block (64 → 80 bytes) with FX-005's own flag bits 256 (S-curve) and 512
(Filmic), chosen apart from the next free bits so parallel FX rows do not collide (D6). The flash guard and FX-020's
grade pass already call `cmp_grade`, so the curve is measured and applied exactly once (D7).

The values join `ColorGrade` (`contrast`: `ContrastCurve`, `contrastStrength` 0…1, default 0.5; new file
`ContrastCurve.swift` holds the enum and the reference curves), the MOD-001 catalog (`effect.colorGrade.contrast`
enumeration, `effect.colorGrade.contrastStrength`), the scene's `fx.grade` entry (`contrast` string,
`contrastStrength` number; D8), the app setting (`settings.colorGrade.contrast`, `settings.colorGrade.contrastStrength`:
FILE-005 backup, privacy allow-list, UI-test reset, FILE-011 erase via `ColorGradeSetting.allKeys`) and Settings →
Color (a "Contrast" picker and a strength slider shown while a curve is chosen; D9). ADR-0050 is amended (D10).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009) in the
reviewed compile site `CompositorShaders.displaySource` (no user-authored shader)
**Primary Dependencies**: Metal (existing output, grade-pass and flash-guard pipelines); ParameterGraph (MOD-001);
SceneFormat (FX-020 entry); SwiftUI (Settings)
**Storage**: UserDefaults String `settings.colorGrade.contrast` (absent/unknown → linear) and Double
`settings.colorGrade.contrastStrength` (absent → 0.5)
**Testing**: XCTest. Compositor: `ContrastCurveReferenceTests` (CPU, Linux shape: identity sweep, monotone, endpoints,
bounds, extremes, order), `ContrastCurveOutputTests` (GPU: each preset vs reference, Linear bit-identical, flash
guard), `ColorGradeOutputTests` (block layout), `ColorGradeCatalogTests`. SceneFormat: effect chain round-trip and
old documents. App: `ColorGradeSettingTests`, `LibraryBackupAppTests`, `SettingsTests`; `ColorGradeUITests` (picker).
Regressions: RenderGoldens, script tests
**Target Platform**: iPhone and iPad; the Mac host for package tests; Linux for the reference
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: no new pass, texture, buffer or per-frame allocation; about 20 ALU ops per pixel when active
**Constraints**: Linear bit-identical to the grade without it; typed steps; small shared-file edits (FX-006 and later
FX rows edit the same files in parallel: own function, own flag bits, own block field appended at the end)
**Scale/Scope**: ~12 edited source files, 1 new source file, 2 new test files, ADR-0050 amended

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Existing Metal encoders and run-time source compile; SwiftUI | Pass |
| VI Modular boundaries | Maths and shader in `Packages/Compositor`; catalog in `ColorGradeParameters`; scene field in SceneFormat; app sets values | Pass |
| VII Real-time safety | GPU only; coefficients derived on change; `setBytes` copies 80 bytes | Pass |
| VIII Upstream fidelity | Linear is bit-identical; projectM untouched | Pass |
| X Evidence | Reference and shader unit tests on the Mac; device GPU check is `{device}` | Pass |
| Sensory safety (FX-019, ACC-012) | Guard measures the curved colour; white stays white (no brightness above the display maximum) | Pass |
| Privacy | Two values on the device; allow-listed; nothing sent | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

```text
specs/292-fx-005-contrast-curves/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/contrast-curves.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/ContrastCurve.swift               (new: enum, constants, reference curves)
Packages/Compositor/Sources/Compositor/ColorGrade.swift                  (fields, clamp, coefficients, step 7)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift           (CMPGrade.contrast, cmp_contrast, GradeBlock)
Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift (two descriptors)
Packages/Compositor/Tests/CompositorTests/ContrastCurveReferenceTests.swift (new, CPU)
Packages/Compositor/Tests/CompositorTests/ContrastCurveOutputTests.swift    (new, GPU)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift          (contrast fields in fx.grade)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (keys)
Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift, SceneAutosaveCapture.swift
Apps/projectM-iOS/Views/ColorGradeSection.swift
Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift, UITests/ColorGradeUITests.swift
docs/adr/0050-output-color-grade.md                                      (amended)
```

**Structure Decision**: extends FX-003's files with clearly marked FX-005 sections; one new source file keeps the
curve maths apart from the shared grade code.

## Complexity Tracking

None.
