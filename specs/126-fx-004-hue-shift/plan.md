# Implementation Plan: FX-004 Hue Shift

**Branch**: `feature/fx-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add hue rotation as a sixth operator of FX-003's colour grade, after saturation and before FX-002's tone map
(research FX-004-D4). The operator rotates the colour's chroma differences (r − g, b − g) with the 2 × 2 matrix
of a rotation about the grey axis (Rodrigues, equal-energy opponent plane, so +120° maps red's hue to green's),
then rebuilds the colour around its own Rec. 709 luminance (D1). Greys have zero differences, so they come out
bit-for-bit unchanged (D2); luminance is kept exactly in real arithmetic. A result that would need a negative
channel is pulled toward its grey just far enough (hue and luminance kept, D3). The CPU derives the four matrix
coefficients once per change (Double, rounded to Float) and passes them in FX-003's coefficient block, which
grows from 48 to 64 bytes (one `float4`), with flag bit 5 (D5). Hue 0 leaves the flag off, so every FX-003
output, and the neutral bypass, is unchanged bit for bit. The flash guard already samples through
`cmp_display`, so it measures the shifted colour (D8).

The value joins `ColorGrade` (`hue`, degrees −180…180), the MOD-001 catalog (`effect.colorGrade.hue`), the
app setting (`settings.colorGrade.hue`, FILE-005 backup, privacy allow-list, UI-test reset; FILE-011's erase
uses `ColorGradeSetting.allKeys`), and Settings → Color (a "Hue" slider, spoken "plus 30 degrees", in "Reset
to neutral"). ADR-0050 is amended (D9).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing output and flash-guard pipelines; `setFragmentBytes` / `setBytes`);
ParameterGraph (MOD-001); SwiftUI (Settings)
**Storage**: one more UserDefaults Double `settings.colorGrade.hue` (absent → 0)
**Testing**: XCTest. Compositor: `HueShiftReferenceTests` (CPU, Linux shape: reference table, grey fixed
points, luminance, composition), `HueShiftOutputTests` (GPU acceptance: grey ramp and red patch, hue-0
identity, flash guard), FX-003's suites and `ColorGradeCatalogTests` (updated). App: `ColorGradeSettingTests`
(hue persistence, readout), `ColorGradeUITests` (Hue slider present, reset). Regressions: RenderGoldens,
LibraryBackup, script tests
**Target Platform**: iPhone and iPad; the Mac host for package tests; Linux for the reference
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: no new pass, texture, buffer or per-frame allocation; about 15 ALU ops per pixel when
active; one uniform branch when off
**Constraints**: hue 0 bit-identical to FX-003; explicit closure types, matrix maths in typed steps; small
shared-file edits (MED-004 and MIDI-002 run in parallel); SwiftUI bodies small
(`-warn-long-function-bodies=300`, `-warn-long-expression-type-checking=150`)
**Scale/Scope**: ~8 edited source files, 2 new test files, ADR-0050 amended

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Existing Metal encoders and run-time source compile; SwiftUI | Pass |
| VI Modular boundaries | Maths and shader in `Packages/Compositor`; catalog in `ColorGradeParameters`; app sets a value | Pass |
| VII Real-time safety | GPU only; coefficients derived on change; `setBytes` copies 64 bytes | Pass |
| VIII Upstream fidelity | Hue 0 is bit-identical; projectM untouched | Pass |
| X Evidence | Shader and reference unit tests on the Mac; device GPU check is `{device}` | Pass |
| Sensory safety (FX-019, ACC-012) | Guard measures the shifted colour; luminance kept | Pass |
| Privacy | One numeric setting on the device; allow-listed; nothing sent | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

```text
specs/126-fx-004-hue-shift/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/hue-shift.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/ColorGrade.swift                  (hue field, range, coefficients, reference)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift           (CMPGrade.hue, cmp_grade step 6, GradeBlock)
Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift (effect.colorGrade.hue)
Packages/Compositor/Tests/CompositorTests/HueShiftReferenceTests.swift   (new, CPU)
Packages/Compositor/Tests/CompositorTests/HueShiftOutputTests.swift      (new, GPU)
Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift (six descriptors)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (key)
Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift                   (hue key, readout)
Apps/projectM-iOS/Views/ColorGradeSection.swift, Views/AccessibleParameter.swift (Hue row, signed degrees)
Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift, UITests/ColorGradeUITests.swift
docs/adr/0050-output-color-grade.md                                      (amended)
```

**Structure Decision**: everything extends FX-003's files; no new target. The UI-test reset and FILE-011's erase
already iterate `ColorGradeSetting.allKeys`, so adding the key there covers both.

## Complexity Tracking

None.
