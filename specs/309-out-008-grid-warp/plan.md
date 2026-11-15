# Implementation Plan: OUT-008 Grid Warp

**Branch**: `feature/out-008` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

A grid warp (3…9 × 3…9 control points in picture-relative coordinates, identity by default) is validated, sampled and
stored by pure Swift in `PresentationLifecycle` (`GridWarp`, next to OUT-007's `CornerPin`): a uniform Catmull-Rom
surface through the points (linear end extrapolation, so evenly spaced and affine grids are reproduced exactly), a
validator that names the first failing rule (size, finiteness, range, per-cell convexity and orientation, folding of
the drawn 16 × 16-per-cell triangle mesh, a self-crossing outline, coverage), clamped-or-refused edits, resampling to a
new size and a stored-string codec. The output stage follows OUT-009's precedent (a per-display property applied in the
visual's own final pass, external slots only): Compositor gets `OutputWarpMesh` (the render description: size, points
as floats, guides) and `OutputWarpReceiver`; the compositor's screen pass renders into one pooled display-format
picture and a new `GridWarpPass` draws it through the mesh (vertex shader evaluates the same Catmull-Rom surface from
`vertex_id`, no vertex buffer) when a mesh is set; projectM's FX-019 output step (`CFlashLimiter`) draws its existing
output through the same mesh in GLSL (no extra pass). `.none` adds no pass, so the identity is bit-identical by
construction; a forced identity mesh is shown exact on the GPU. `VisualSlotView` hands the mesh to receivers (external
role only), `ExternalDisplayCoordinator` pushes the mesh and the guides flag, `ExternalOutputSetting` stores one
device-local key, OUT-014 profiles carry it optionally, and Settings › External Display gets "Grid warp…".

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26), C11 (CFlashLimiter), MSL and GLSL ES 3.00
**Primary Dependencies**: Metal (compositor pass), ANGLE GLES 3 (FX-019 output step), SwiftUI (editor), PresentationLifecycle (pure Swift, Linux-tested)
**Storage**: UserDefaults, one key `settings.externalDisplay.gridWarp` (absent = identity)
**Testing**: XCTest — PresentationLifecycle on the host; Compositor GPU tests on the host (Metal); ANGLERendering and app tests on the iOS 27.2 simulator "OUT08 iPhone 17"; one XCUITest
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: identity: zero cost; active: projectM no extra pass, compositor one extra full-screen pass + one picture
**Constraints**: owner rule 7 budgets; Xcode 26 type-check budget; public APIs only; Linux build of PresentationLifecycle
**Scale/Scope**: one package model file, one Compositor model + pass, a C/GLSL change, slot/coordinator/setting/profile wiring, one editor view

## Constitution Check

- I. Public Apple APIs only: Metal render passes, GLES through ANGLE, SwiftUI. Core Animation's mesh transform is not public, so it is not used (research OUT-008-D1). PASS.
- IV/V. No source or capture claims. PASS.
- VI. Modular boundaries: geometry/validation in PresentationLifecycle; the render description and passes in Compositor and Rendering (no app types); app wiring in the app. PASS.
- VII. Real-time audio: nothing on the audio path. PASS.
- VIII. projectM untouched (the change is in this repo's CFlashLimiter post-pass, not `Vendor/projectM`). PASS.
- X. Evidence: validator unit and fuzz tests, GPU exactness and reference tests, app tests with the fake external display; projector check `{device}`. PASS.
- Privacy: one local preference key; no network. PASS.

Post-design re-check: unchanged, PASS. No ADR: no constitution default is overridden (OUT-009 set the precedent of a
display-only final-pass property).

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/GridWarp.swift            (new: model, surface, validator, codec; C1)
Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputProfile.swift       (optional gridWarp field; C5)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/GridWarpTests.swift    (new)
Packages/Compositor/Sources/Compositor/OutputWarp.swift                                (new: OutputWarpMesh, OutputWarpReceiver; C2)
Packages/Compositor/Sources/Compositor/GridWarpPass.swift                              (new: MSL + pass; C2)
Packages/Compositor/Sources/Compositor/Compositor.swift, CompositorShaders.swift       (screen pass hook, source splice)
Packages/Compositor/Tests/CompositorTests/GridWarpOutputTests.swift                    (new)
Packages/Rendering/Sources/CFlashLimiter/FlashLimiter.c, include/CFlashLimiter.h       (warp output step; C3)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift                     (receiver, capture unwarped; C3)
Packages/ANGLERendering/Tests/ANGLERenderingTests/GridWarpGLTests.swift                (new)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift, ExternalDisplayCoordinator.swift, ExternalOutputSetting.swift,
  ExternalOutputSetting+Profile.swift                                                  (C4)
Apps/projectM-iOS/Visuals/{Camera,Photo,Video,Text}VisualHost.swift, NativeSpectrumHost.swift (receiver hook)
Apps/projectM-iOS/Views/GridWarpEditorView.swift (new), ExternalDisplaySection.swift   (C4)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                                    (probe `externalGridWarp`)
Apps/projectM-iOS/Tests/GridWarpAppTests.swift (new), UITests/GridWarpUITests.swift (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, LibraryErasePolicy.swift (keys)
```

**Structure Decision**: existing app + package layout; all touched packages are already in CI groups.

## Complexity Tracking

None.
