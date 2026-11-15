# Implementation Plan: OUT-009 Output Color Calibration

**Branch**: `feature/out-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A display calibration (gamma, red/green/blue trims; identity by default) and its transfer function
out = clamp(trim × e^(1/gamma), 0, 1) on the display-encoded value e are pure Swift in the `Compositor`
package (`DisplayCalibration`, CPU file, Linux-tested), with a stored-string codec and a tiny main-actor
protocol (`DisplayCalibrationReceiver`) that a visual's view adopts when its renderer can apply one.
iOS has no public colour transform for arbitrary layer content (research D1), so calibration is applied
in the two shared final passes that already exist:

* the compositor's screen output pass: a second fragment `cmp_output_calibrated` (the same body as
  `cmp_output`, then encode → transfer → decode, the sRGB target re-encodes) used only by
  `composite(into:)` and only while the calibration is not the identity; recordings (`encodeOutput`), still
  captures and the transition bus keep plain `cmp_output`, so they are uncalibrated and the identity is
  bit-exact (same pipeline);
* projectM's FX-019 GL output pass (`CFlashLimiter`): two uniforms after the envelope's gain, in encoded
  values; a capture frame redraws that pass uncalibrated for the read-back and then calibrated.

Not covered (said in the editor and the report): native spectra, the GLES fallback renderer, OUT-007's
card. `VisualSlotView` gives the held visual's view the calibration on external slots and the identity on
the device slot (and when a visual leaves); `ExternalDisplayCoordinator` pushes it to every external slot
inside the call (also during a recording hold). `ExternalOutputSetting` stores one device-local key;
Settings › External Display gets "Color calibration…", a full-screen editor in OUT-007's pattern.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26), Metal Shading Language (runtime-compiled), GLSL ES 3.00 (C string)
**Primary Dependencies**: Metal (compositor), ANGLE GL ES 3 (projectM), UIKit, SwiftUI
**Storage**: UserDefaults, one key `settings.externalDisplay.calibration` ("gamma,red,green,blue"; absent = identity)
**Testing**: XCTest: Compositor package (host + GPU), ANGLERendering package (iOS 27.2 simulator), app tests and one XCUITest on simulator "OUT9 iPhone 17"
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: no extra pass on frames; identity costs nothing (same pipeline / uniform branch)
**Constraints**: owner rule 7 budgets; Xcode 26 type-check budget; Linux builds of Compositor (CPU file only)
**Scale/Scope**: one package file + shader additions, one C pass change, slot/coordinator/setting extension, one editor view, DEBUG probe, key lists

## Constitution Check

- I. Public Apple APIs only: Metal render pipelines, GL ES uniforms through ANGLE, UIKit/SwiftUI. No private CA filters. PASS.
- IV/V. No source or capture claims; coverage stated honestly per visual. PASS.
- VI. Modular boundaries: transfer function in a package; per-renderer application in each renderer; routing in the app. PASS.
- VII. Real-time audio: nothing on the audio path. PASS.
- VIII. Upstream ProjectM fidelity: the engine is untouched (the pass is the app's own CFlashLimiter). PASS.
- X. Evidence: pure tests, GPU pixel tests (Metal and GL), app acceptance test, UI test; display check `{device}`. PASS.
- Privacy: one local preference key. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/Compositor/Sources/Compositor/DisplayCalibration.swift              (new, C1)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift               (cmp_output_calibrated, CalibrationBlock; C2)
Packages/Compositor/Sources/Compositor/Compositor.swift                      (displayCalibration, calibrated screen pass; C2)
Packages/Compositor/Tests/CompositorTests/DisplayCalibrationTests.swift      (new: pure)
Packages/Compositor/Tests/CompositorTests/DisplayCalibrationOutputTests.swift (new: GPU)
Packages/Rendering/Sources/CFlashLimiter/FlashLimiter.c, include/CFlashLimiter.h (calibration uniforms, DrawOutput; C3)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift           (receiver view, capture redraw; C3)
Packages/ANGLERendering/Tests/ANGLERenderingTests/DisplayCalibrationGLTests.swift (new)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift (NativeSpectrumLayerView receiver), Camera/Photo/Text/VideoVisualHost.swift (hook; C3)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift, ExternalDisplayCoordinator.swift, ExternalOutputSetting.swift (C4)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift, DisplayCalibrationEditorView.swift (new; C5)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift (probe `externalCalibration`; C6)
Apps/projectM-iOS/Tests/DisplayCalibrationAppTests.swift, UITests/DisplayCalibrationUITests.swift (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, LibraryErasePolicy.swift, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (keys)
```

**Structure Decision**: existing layout. Compositor is in CI's `PKGS_VISUAL`; ANGLERendering keeps its
simulator-only tests. No ADR: no constitution default is overridden (FX-003 already set the precedent of
coverage limited to the compositor's output pass; calibration is a presentation property like OUT-004/007).

## Complexity Tracking

None.
