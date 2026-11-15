# Implementation Plan: SHD-006 Noise Editor

**Branch**: `feature/shd-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/245-shd-006-noise-editor/spec.md`

## Summary

Noise Flow's metadata gains `seed`, `lacunarity`, `gain`, `warpAmount`, `warpFrequency` (slots 6-10) and
`octaves` widens to 1…8; the SHD-003 cap and the material uniform block grow from 8 to 16 slots (ADR). The shader
constant gets a seeded integer-hash value noise, a parameterised fBm and a 2-D domain warp, used by
`mat_noiseFlow` and `mat_noiseFlowLite`. A plain-Swift `NoiseTextureReference` mirrors it (CPU reference, seed
sequence for "Randomize seed"). A Metal `MaterialPreviewRenderer` draws one still frame of any material layer to
8-bit sRGB pixels; the app's new Settings › Noise editor uses it for the live preview, shows the generic metadata
controls (write-enabled) and stores the values in one UserDefaults key.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0), Xcode 27.2 (CI also Xcode 26)
**Primary Dependencies**: ProceduralMaterials, ShaderParameterMetadata (SHD-001/003/004), FrameCapture (half → sRGB conversion), ParameterGraph (MOD-001), SwiftUI, Metal
**Storage**: UserDefaults `settings.noiseEditor.values` (JSON, backed up, erased by Settings erase)
**Testing**: XCTest — `NoiseTextureReferenceTests` (CPU, Linux shape), `MaterialNoiseTests` (GPU: determinism, exact digest per GPU class, golden signatures, seeds differ, monotonic controls, CPU vs GPU), metadata/catalog test updates, app unit tests (`NoiseEditorTests`), one UI test on "SHD6 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+/macOS 15 packages; Linux for the CPU parts
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: ≤ 3 × 8 noise octaves per pixel (warp on); preview 256 × 256 redrawn per edit (one small GPU pass)
**Constraints**: SHD-011 (Metal code only in the reviewed module constant); Xcode 26 type-check budget; short tests
**Scale/Scope**: 5 new parameters, 1 cap change, 3 shader helpers, 1 renderer, 1 editor screen

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Metal, SwiftUI, UserDefaults. |
| VI Modular boundaries | Pass: noise math in ProceduralMaterials (CPU reference plain Swift), app only maps settings and shows controls. |
| VII Real-time audio safety | Pass: nothing on audio threads. |
| X Evidence-based quality | Pass: GPU determinism, exact digests, goldens, CPU reference, UI test; device look `{device}`. |
| SHD-011 / ADR-0024 | Pass: noise code is part of `ProceduralMaterialShaders.source`; no file, user text or download is compiled. |
| Accessibility (ACC-005) | Pass: generic slider rows use `.accessibleParameter`; steppers and the button are labelled. |
| Photosensitivity | Pass: the preview is a still; composited materials keep the flash guard. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
docs/adr/00NN-material-parameter-cap-16.md           # new ADR (cap 8 → 16)
Packages/Compositor/Package.swift                     # ProceduralMaterials depends on FrameCapture
Packages/Compositor/Sources/ShaderParameterMetadata/
  ShaderMetadataValidator.swift, ShaderMetadataError.swift   # cap 16
Packages/Compositor/Sources/ProceduralMaterials/
  MaterialDefinition.swift                            # maximumParameterCount 16
  MaterialParameterMetadata.swift                     # Noise Flow: 11 parameters
  ProceduralMaterialShaders.swift                     # 16 slots; seeded noise, fBm, warp
  NoiseTextureReference.swift                         # new: CPU reference, settings, seed sequence
  MaterialPreviewRenderer.swift                       # new: one still frame → RGBA8 sRGB
Packages/Compositor/Tests/ProceduralMaterialsTests/
  NoiseTextureReferenceTests.swift, MaterialNoiseTests.swift (new); catalog/metadata/render updates
Packages/Compositor/Tests/ShaderParameterMetadataTests/ShaderMetadataValidatorTests.swift   # 17 refused
Apps/projectM-iOS/Coordinators/NoiseEditorStore.swift   # new: values, persistence, randomize
Apps/projectM-iOS/Views/NoiseEditorView.swift           # new: link section, preview, controls
Apps/projectM-iOS/Views/SettingsView.swift              # one line: the link section
Apps/projectM-iOS/Tests/NoiseEditorTests.swift, UITests/NoiseEditorUITests.swift
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Apps/.../LibraryBackupAppTests.swift,
UI-test reset                                           # the new key
```

**Structure Decision**: extend existing targets; no new package or target.

## Complexity Tracking

| Deviation | Why needed | Simpler alternative rejected because |
|---|---|---|
| Parameter cap 8 → 16 | Noise Flow needs 11 parameters | A separate 8-parameter noise material would lose scale, tint and brightness |
