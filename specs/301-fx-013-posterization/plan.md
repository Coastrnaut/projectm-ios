# Implementation Plan: FX-013 Posterization

**Branch**: `feature/fx-013` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add posterization as the eighth (last) operator of FX-003's colour grade, after FX-005's contrast curve (research
FX-013-D1). The operator brings the colour into display range with FX-002's tone map step (identity in range), then
quantises each channel on the sRGB-encoded scale (D2): e = encode(x), k = clamp(⌊e·n + t⌋, 0, n), out = decode(k/n)
with n = L − 1 and threshold t = 0.5 (nearest level) or, with dithering, t = (B[x mod 4, y mod 4] + 0.5)/16 from a
4 × 4 Bayer matrix (D3, D4). The output's FX-002 tone map is then an exact identity, so each channel holds at most L
values (D1). Posterize off leaves the operator's flag off, so every earlier output and the neutral bypass are
unchanged bit for bit. The CPU passes (n, 1/n, 0, 0) in a new `float4 poster` appended to FX-003's block (80 → 96
bytes) with the free flag bits 64 (posterize) and 128 (dither, only with 64; D5). Dithering needs the pixel position:
a new `cmp_grade_at(c, g, p)` / `cmp_display_at` carry it, the existing `cmp_grade` / `cmp_display` stay as
position-(0, 0) wrappers, and the four callers (output, calibrated output, FX-020 grade pass, flash guard) pass their
pixel (D6). The shader keeps its own sRGB helpers because the flash guard's source splices `displaySource` without
`cmp_encode` (D7).

The values join `ColorGrade` (`posterize` Bool, `posterizeLevels` Int 2…32 default 6, `posterizeDither` Bool; new
file `Posterize.swift` with the constants and the reference), the MOD-001 catalog (two booleans and one integer,
hand-chosen), the scene's `fx.grade` entry (`posterize`, `posterizeLevels`, `posterizeDither`; D8), the app setting
(`settings.colorGrade.posterize`, `.posterizeLevels`, `.posterizeDither`: FILE-005 backup, privacy allow-list, UI-test
reset and FILE-011 erase via `ColorGradeSetting.allKeys`) and Settings → Color (a "Posterize" switch, then "Levels"
and "Dither" while on; D9). ADR-0050 is amended (D10).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009) in the
reviewed compile site `CompositorShaders.displaySource` (no user-authored shader, no new compile site)
**Primary Dependencies**: Metal (existing output, grade-pass and flash-guard pipelines); ParameterGraph (MOD-001);
SceneFormat (FX-020 entry); SwiftUI (Settings)
**Storage**: UserDefaults Bool `settings.colorGrade.posterize`, number `settings.colorGrade.posterizeLevels`
(absent → 6), Bool `settings.colorGrade.posterizeDither`
**Testing**: XCTest. Compositor: `PosterizeReferenceTests` (CPU, Linux shape: level counts for L ∈ {2, 3, 6, 16, 32},
off identity, extremes, dither determinism), `PosterizeOutputTests` (GPU: gradient level counts in both formats, GPU vs
CPU, off bit-identical, flash guard), `ColorGradeOutputTests` (block layout), `ColorGradeCatalogTests`. SceneFormat:
`SceneEffectChainTests`. App: `ColorGradeSettingTests`, `LibraryBackupAppTests`, `SettingsTests`; `ColorGradeUITests`
(switch). Regressions: RenderGoldens, FX-005 output tests, script tests
**Target Platform**: iPhone and iPad; the Mac host for package tests; Linux for the reference
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: no new pass, texture, buffer or per-frame allocation; about 30 ALU ops per pixel when active
**Constraints**: off bit-identical; typed steps; small shared-file edits (FX-012 and UIX-012 in parallel: own
function, own flag bits, own block field appended)
**Scale/Scope**: ~12 edited source files, 1 new source file, 2 new test files, ADR-0050 amended

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Existing Metal encoders and run-time source compile; SwiftUI | Pass |
| VI Modular boundaries | Maths and shader in `Packages/Compositor`; catalog in `ColorGradeParameters`; scene field in SceneFormat; app sets values | Pass |
| VII Real-time safety | GPU only; coefficients derived on change; `setBytes` copies 96 bytes | Pass |
| VIII Upstream fidelity | Off is bit-identical; projectM untouched | Pass |
| X Evidence | Reference and shader unit tests on the Mac; device GPU check is `{device}` | Pass |
| Sensory safety (FX-019, ACC-012) | Guard measures the posterized colour at the same pixels; never brighter than display white; dither pattern static | Pass |
| Privacy | Three values on the device; allow-listed; nothing sent | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

```text
specs/301-fx-013-posterization/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/posterize.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/Posterize.swift                   (new: constants, Bayer matrix, reference)
Packages/Compositor/Sources/Compositor/ColorGrade.swift                  (fields, clamp, coefficients, step 8)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift           (CMPGrade.poster, cmp_posterize, cmp_grade_at, GradeBlock)
Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift, OutputGradePass.swift (pass the pixel position)
Packages/Compositor/Sources/ColorGradeParameters/ColorGradeCatalog.swift (three descriptors)
Packages/Compositor/Tests/CompositorTests/PosterizeReferenceTests.swift  (new, CPU)
Packages/Compositor/Tests/CompositorTests/PosterizeOutputTests.swift     (new, GPU)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift          (posterize fields in fx.grade)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (keys)
Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift, SceneAutosaveCapture.swift
Apps/projectM-iOS/Views/ColorGradeSection.swift
Apps/projectM-iOS/Tests/ColorGradeSettingTests.swift, UITests/ColorGradeUITests.swift
docs/adr/0050-output-color-grade.md                                      (amended)
```

**Structure Decision**: extends FX-003's files with clearly marked FX-013 sections, as FX-005 did.

## Complexity Tracking

None.
