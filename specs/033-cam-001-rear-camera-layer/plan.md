# Implementation Plan: CAM-001 Rear Camera Layer

**Branch**: `feature/cam-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/033-cam-001-rear-camera-layer/spec.md`

## Summary

A new target `CameraLayer` in `Packages/Compositor` adds a CMP-001 `LayerSource`,
`CameraLayerSource`, that draws the newest picture of a `CameraFrameProvider` into the layer
picture with aspect fill and orientation, sampling an sRGB-encoded texture so the GPU decodes it to
linear light (research CAM-001-D2, D3). When the provider has no picture (not started, denied,
restricted, no camera, interrupted, failed) `render` throws `.notReady` and the compositor shows the
layer's `.transparent` fallback. Two providers implement the protocol: `StubCameraFrameProvider`
(deterministic, every permission state, a solid or striped picture, no camera; tests, the
simulator and DEBUG UI tests) and, on iOS only, `AVCameraFrameProvider` (an `AVCaptureSession` with
the back wide-angle camera, a modest preset, BGRA output with late frames discarded, its own serial
queue, `CVMetalTextureCache`, interruption and runtime-error observers; research CAM-001-D4, D5).
The CPU parts (feed states, aspect-fill and rotation math) build everywhere, Linux included.

In the app, `VisualChoice.camera` ("Camera") is session-only. `CameraVisualHost` (one
`CAMetalLayer` view, one display link, one `LiveBandAnalyzer`) runs a `Compositor` with two layers:
the camera layer and a `SpectrumLayerSource` (circular, transparent background, the user's bar
count). `AppCoordinator` starts the camera only through `resumeActiveVisual()` while Camera is
shown on the visualizer and running, and stops it in `pauseActiveVisual()`, on a visual change, in
PERF-011 suspension, and on scene disconnect (research CAM-001-D6). The host reports the feed
state; `VisualizerView` shows the non-blocking notice (with "Open Settings" for denied/restricted).
`NSCameraUsageDescription` is added through `project.yml`. Research: [research.md](research.md);
entities: [data-model.md](data-model.md); contract: [contracts/camera-layer.md](contracts/camera-layer.md);
checks: [quickstart.md](quickstart.md); decision record: ADR-0017.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Metal, CoreVideo and AVFoundation (Apple platforms, guarded with
`#if canImport(...)` and `COMPOSITOR_NO_METAL`); Compositor, SpectrumLayers and VisualGenerators
(existing). No new third-party dependency, no Vision, no networking.

**Storage**: none. The Camera choice is not stored (CAM-001-R11).

**Testing**: XCTest in `Packages/Compositor` (`CameraLayerTests`: GPU tests skipped without Metal,
CPU tests everywhere, Linux shape with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE`); app unit tests `CameraVisualTests` and UI tests `CameraUITests` on the
iOS 27.2 simulator with the stub provider (`-uitestCamera <scenario>`, DEBUG only).

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (host tests), Linux (CI, CPU parts only).

**Project Type**: iOS app plus SwiftPM package target.

**Performance Goals**: camera at the session preset's default rate (about 30 fps), display at
QualityGovernor's rate; one extra full-screen textured draw per frame over the spectrum; no
per-frame allocation by the layer (CAM-001-R15). Device frame rate and thermal behaviour are
`{device}` tasks.

**Constraints**: public APIs only; no file or network I/O on the camera path; render never waits
on a lock (try-lock, research CAM-001-D5); no main-actor mutation in test setUp/tearDown; no C
stdio globals; explicit closure types (Xcode 26); unit tests about 1 s, UI tests under 30 s
(owner rule 7).

**Scale/Scope**: about 450 lines of package Swift, 250 of package tests, 300 of app Swift, 200 of
app tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | AVFoundation, CoreVideo, Metal, UIKit's settings URL; nothing private, no `dlsym` | Pass |
| VI. Modular boundaries | The camera layer imports only Compositor, Metal, CoreVideo, AVFoundation; no projectM, ANGLE, capture or app code. The app hosts it. | Pass |
| VII. Real-time audio safety | The camera never touches the audio path; the analyzer is the existing one | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Simulator tests only with the stub; every real-camera behaviour is a `{device}` task left open | Pass |
| Security | No credentials, no signing change | Pass |
| Privacy | Separate spec with privacy review (spec "Privacy review"); permission at point of use with an accurate description; camera only while shown; nothing stored, sent or analysed; privacy policy and App Privacy notes updated | Pass |
| FR-068 (no networking) | No networking API added; compliance check runs | Pass |
| FR-089 (system indicators) | The status bar is never hidden while the camera runs (CAM-001-R10) | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/033-cam-001-rear-camera-layer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/camera-layer.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                                  # + target CameraLayer, in the library product
├── Sources/CameraLayer/
│   ├── CameraFeedState.swift                      # states, authorization, notices (CPU)
│   ├── CameraPictureGeometry.swift                # aspect fill + rotation math (CPU)
│   ├── CameraFrameProvider.swift                  # protocol, CameraFrame, LatestCameraFrame (Metal)
│   ├── CameraLayerSource.swift                    # the LayerSource (Metal)
│   ├── StubCameraFrameProvider.swift              # deterministic provider (Metal)
│   └── AVCameraFrameProvider.swift                # AVCaptureSession provider (iOS only)
└── Tests/CompositorTests/CameraLayerTests.swift   # + CameraGeometryTests (CPU)

Apps/projectM-iOS/
├── Visuals/CameraVisualHost.swift                 # compositor host: camera + spectrum
├── Coordinators/AppSettings.swift                 # VisualChoice.camera, not persisted
├── Coordinators/AppCoordinator.swift              # lifecycle wiring, feed state, notice
├── Views/VisualizerView.swift, SettingsView.swift, ControlsOverlay.swift
├── Tests/CameraVisualTests.swift
└── UITests/CameraUITests.swift
project.yml                                        # Compositor package, NSCameraUsageDescription
docs/privacy-policy.md, docs/release/app-privacy.md, docs/adr/0017-rear-camera-layer.md
```

**Structure Decision**: the camera layer is a target of the Compositor package (beside
SpectrumLayers), not a new package: it is a layer adapter like SpectrumLayers, the package's one
library product carries it to the app and CI's existing package loops already test it.

## Complexity Tracking

None. CMP-002 (layer stack) replaces `CameraVisualHost`'s fixed stack and the "Camera" choice with
user-built stacks; the layer and providers stay.
