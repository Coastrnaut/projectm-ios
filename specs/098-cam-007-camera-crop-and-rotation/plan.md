# Implementation Plan: CAM-007 Camera Crop and Rotation

**Branch**: `feature/cam-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/098-cam-007-camera-crop-and-rotation/spec.md`

## Summary

CAM-007 generalizes the camera layer's aspect fill into a user-chosen crop, in the one place the
picture is fitted today. In `Packages/Compositor` (target `CameraLayer` only):

- New `CameraCrop` value (`CameraCrop.swift`): `mode` (`CameraCropMode.fill` / `.fit`), `anchor`
  (`CameraCropAnchor.center` / `.top` / `.bottom`, a point on the upright picture's vertical center
  line) and `zoom` (1, 1.5, 2, 3). `CameraCrop.fill` (Fill, Center, 1×) is the default.
- `CameraPictureGeometry.init(pictureWidth:pictureHeight:rotation:outputWidth:outputHeight:mirrored:crop:)`
  computes one uniform scale (Fill: cover; Fit: contain; times the zoom) and places the shown part
  so the anchor point of the upright picture lands on the same relative output point (research
  CAM-007-D1: "object-position" placement, offset = (1 − visible) × anchor). `crop` defaults to
  `.fill`, which reproduces CAM-001's centered aspect fill exactly, so every existing caller and
  test is unchanged (CAM-007-S3). Math in typed steps.
- The shader keeps its uniforms (visible, offset, rotation, mirror carry the whole transform);
  it returns transparent for output points whose upright coordinate is outside the picture (Fit's
  bars, research CAM-007-D2). `CameraPictureGeometry.textureCoordinate` gains the matching
  `contains(x:y:)` so the CPU model and the shader agree.
- `CameraLayerSource.crop` (main thread, read per frame like `mirrored`): no restart, no camera
  reconfiguration (CAM-007-R5). The geometry is recomputed every frame from the picture's size and
  rotation and the layer picture's size, so a device rotation (new drawable aspect, new rotation
  angle from `AVCaptureDevice.RotationCoordinator`) keeps the chosen crop by construction
  (research CAM-007-D3).

In the app:

- `AppSettings`: `cameraCropMode` (`settings.camera.cropMode`), `cameraCropAnchor`
  (`settings.camera.cropAnchor`), `cameraZoom` (`settings.camera.zoom`), unknown → defaults, one
  set for both cameras; `cameraCrop` combines them. Keys in `allKeys` and `ALLOWED_KEYS`.
- `SettingsView`: CAM-002's Camera section gains "Crop" (segmented Fill/Fit,
  `cameraCropModePicker`), "Anchor" (segmented Center/Top/Bottom, `cameraCropAnchorPicker`) and
  "Zoom" (segmented 1×/1.5×/2×/3×, `cameraZoomPicker`, values spelled "1.5 times").
- `CameraVisualHost.crop` forwards to the layer; `make(…, crop:)`; `AppCoordinator.cameraSettingsChanged()`
  applies it; `VisualizerView` observes the three settings.
- Scenes and cues unchanged: Camera and its settings are never recorded.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/camera-crop.md](contracts/camera-crop.md); checks: [quickstart.md](quickstart.md);
decision record: ADR-0017 amendment (no default overridden: Fill, centered, stays the default).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Metal (shader), Compositor; SwiftUI in the app. No new dependency, no
Vision, no networking, no AVFoundation change.

**Storage**: three UserDefaults settings (mode, anchor, zoom). No pictures stored.

**Testing**: `Packages/Compositor`: `CameraCropTests` (CPU geometry table, Linux shape too) and
GPU pixel tests in `CameraLayerTests` (marker picture at portrait and landscape sizes per mode);
app unit tests `CameraCropTests` (settings persistence through a new `AppSettings`, host
forwarding without a restart, composite and REC-001 capture framing); UI test
`CameraCropUITests` with `-uitestCamera granted`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package target.

**Performance Goals**: no extra pass, no new uniform; one bounds test in the fragment shader; no
per-frame allocation (CAM-001-R15).

**Constraints**: public APIs only; typed steps for coordinate math; explicit closure types; no
main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests about 1-2 s, UI test
under 30 s (owner rule 7). CMP-004 (blend modes) edits Compositor shaders and layer types in
parallel: Compositor edits stay inside `Sources/CameraLayer` and the camera tests.

**Scale/Scope**: about 8 source files touched, 1 new source file, 3 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal and SwiftUI only; no camera API change | Pass |
| VI Modular boundaries | Geometry stays a pure value in `CameraLayer`; app reads/writes settings only | Pass |
| X Evidence | Simulator stand-in results only; real cameras on D1-D3 are `{device}` tasks | Pass |
| Privacy | No new capture, storage of pictures or transmission; settings never start the camera | Pass |
| No networking | None added; `check_compliance.py` | Pass |
| Accessibility (ACC-001) | Labels and spoken values on the three pickers; no new animation (motion policy unaffected) | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/098-cam-007-camera-crop-and-rotation/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/camera-crop.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/CameraLayer/
├── CameraCrop.swift               # new: mode, anchor, zoom
├── CameraPictureGeometry.swift    # crop-aware fit, contains(x:y:)
└── CameraLayerSource.swift        # crop property, transparent outside the picture
Packages/Compositor/Tests/CompositorTests/
├── CameraCropTests.swift          # new: geometry table
└── CameraLayerTests.swift         # + pixel tests per mode, portrait and landscape
Apps/projectM-iOS/
├── Coordinators/AppSettings.swift, AppCoordinator.swift
├── Visuals/CameraVisualHost.swift
├── Views/SettingsView.swift, VisualizerView.swift
├── Tests/CameraCropTests.swift    # new
└── UITests/CameraCropUITests.swift # new
scripts/run_device_tests.py, docs/adr/0017-rear-camera-layer.md
```

**Structure Decision**: extend the existing `CameraLayer` target and the Camera visual host; no
new target.

## Complexity Tracking

None.
