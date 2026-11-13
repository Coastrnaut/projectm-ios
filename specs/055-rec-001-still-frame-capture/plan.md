# Implementation Plan: REC-001 Still Frame Capture

**Branch**: `feature/rec-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/055-rec-001-still-frame-capture/spec.md`

## Summary

A new pure-Swift target `FrameCapture` in `Packages/Compositor` holds the capture formats, the
captured-pixel value, the color conversion (half float decode, clamp, unpremultiply, sRGB transfer,
8-bit rounding, row flip, channel swizzle), the refusal rules and, behind `#if canImport(ImageIO)`,
the PNG/HEIF encoder and a property inspector (research REC-001-D1 to D5). Each visual hands over
the frame it presents next, after its flash limiting:

| Visual | Capture point | Pixels |
|---|---|---|
| Camera, Photo, Video (CMP-001) | `Compositor.requestFrameCapture`: the next `composite` encodes the existing output pipeline (composite × flash-guard gain) a second time into a private `rgba16Float` texture, blits it to a shared buffer, and delivers it when the command buffer completes | linear premultiplied half-float RGBA |
| Circular / Linear Spectrum | `NativeSpectrumHost`: turns `framebufferOnly` off for the request, and blits the first readable drawable it presents into a shared buffer | sRGB BGRA8, top-down, opaque |
| projectM (ANGLE) | `ANGLERenderer.captureNextFrame`: after the FX-019 post-pass wrote framebuffer 0 and before `eglSwapBuffers`, `glReadPixels` (the existing test readback) | sRGB-agnostic RGBA8, bottom-up, opaque |

`FrameCaptureCoordinator` (app, main actor) checks the refusal rules (blackout not live, paused,
busy, no visual), asks the shown visual's source, applies a 1 s timeout, converts and encodes on a
detached task, and presents the system Files exporter (`fileExporter`) with a `FileDocument`; in
DEBUG `-uitestCaptureDirectory <name>` writes to the app's temporary folder instead and exposes a
probe. "Save Frame" joins the controls with a PNG / HEIF choice.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: Metal (blit, existing compositor output pipeline), EGL/GLES through
`CANGLE` (existing readback), ImageIO and CoreGraphics (encoding, read-back), UniformTypeIdentifiers
and SwiftUI (`fileExporter`). No new package; `Compositor` target gains a dependency on the new
`FrameCapture` target in the same package; the library product lists it.

**Storage**: none. The encoded bytes live in memory until the exporter finishes (FR-065).

**Testing**: `swift test --package-path Packages/Compositor` on the Mac host (conversion, fixture
encoding with ImageIO read-back, metadata, compositor GPU capture) and in the Linux shape
(`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`: conversion and gate only);
`xcodebuild test -scheme ANGLERendering` on the iOS 27.2 simulator (projectM capture); app unit tests
(coordinator refusals, native spectrum and Camera capture through the hosts); one UI test
(`FrameCaptureUITests`).

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app plus package additions.

**Performance Goals**: zero cost when no capture is pending (one optional check per frame); the
capturing frame adds one render pass + one blit (compositor) or one blit (native) or one
`glReadPixels` (projectM, synchronous on the GL thread, once). Conversion and encoding off the main
thread.

**Constraints**: public APIs only; no new Metal source (SHD-011 allowlist unchanged); explicit
closure types; no C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock
assertions; owner rule 7 budgets; never the Simulator panel tool.

**Scale/Scope**: about 700 lines of source and 600 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal, ImageIO, CoreGraphics, GLES `glReadPixels` through ANGLE, SwiftUI `fileExporter` | Pass |
| IV/V. Truthful labeling, no universal claims | No compatibility claim; Files/iCloud on devices are `{device}` tasks | Pass |
| VI. Modular boundaries | Conversion and encoding in a package target with no app, capture or engine knowledge; each renderer exposes only "next frame's pixels" | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched (readback through the existing bridge C function) | Pass |
| IX. Dependencies | None added | Pass |
| X. Evidence | Fixture tests on host and Linux; simulator GPU checks; devices last, by the owner | Pass |
| Privacy | Explicit action only, user-chosen destination, no Photos permission, no metadata, no copy kept; privacy policy updated; label still Data Not Collected | Pass |
| Flash safety (ADR-0011) | Capture reads the post-limiter frame; nothing new is shown | Pass |

Post-design re-check: unchanged, all pass. No ADR is needed: no constitution default is overridden
(decisions recorded in research REC-001-D1 to D8 and the spec's Clarifications).

## Project Structure

### Documentation (this feature)

```text
specs/055-rec-001-still-frame-capture/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/frame-capture.md
└── checklists/requirements.md
docs/privacy-policy.md, docs/release/app-privacy.md   # saved frames
```

### Source Code (repository root)

```text
Packages/Compositor/Package.swift                                   # + FrameCapture target, test target
Packages/Compositor/Sources/FrameCapture/FrameCaptureFormat.swift    # NEW formats, policies, errors, gate
Packages/Compositor/Sources/FrameCapture/CapturedPixels.swift        # NEW pixel value
Packages/Compositor/Sources/FrameCapture/FrameColorConversion.swift  # NEW conversion
Packages/Compositor/Sources/FrameCapture/FrameImageEncoder.swift     # NEW ImageIO encode + inspect
Packages/Compositor/Sources/Compositor/Compositor.swift              # + requestFrameCapture
Packages/Compositor/Tests/FrameCaptureTests/*.swift                  # NEW
Packages/Compositor/Tests/CompositorTests/CompositorCaptureTests.swift   # NEW (GPU)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift  # + captureNextFrame
Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLECaptureTests.swift
Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift        # NEW
Apps/projectM-iOS/Visuals/*Host.swift                               # + capture source conformance
Apps/projectM-iOS/Views/ControlsOverlay.swift, VisualizerView.swift # Save Frame, format choice, exporter, notice, probe
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                 # owns the capture coordinator, active source
Apps/projectM-iOS/Tests/FrameCaptureAppTests.swift
Apps/projectM-iOS/UITests/FrameCaptureUITests.swift
```

**Structure Decision**: rules and encoding in the package (host- and Linux-testable), readback in
each renderer, glue in the app.

## Complexity Tracking

None: no constitution violation.
