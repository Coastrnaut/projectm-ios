# Implementation Plan: CAM-002 Front Camera Layer

**Branch**: `feature/cam-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/096-cam-002-front-camera-layer/spec.md`

## Summary

CAM-002 extends CAM-001's camera layer instead of adding a visual. In `Packages/Compositor`
(target `CameraLayer`):

- `CameraPosition` (`back`, `front`) and a `mirrored` flag join `CameraPictureGeometry`; the
  geometry's `textureCoordinate` and the shader flip the upright picture's x before the rotation
  mapping (research CAM-002-D1). This is the only place the mirror exists, so the compositor's one
  composite (screen, REC-001 capture, REC-003 output pass, OUT-001 external display) carries it
  (research CAM-002-D2).
- `CameraLayerSource.mirrored` (main thread, read per frame, no restart). Every `CameraFrame` is
  stamped with the position it came from; the layer draws only pictures whose position equals the
  provider's current position, so no picture of the previous camera is drawn after a switch
  (research CAM-002-D3).
- `CameraFrameProvider` gains `position` and `select(_:)` (default implementations keep other
  conformers compiling). `StubCameraFrameProvider` simulates both positions, a missing front
  camera and an asymmetric pattern (`.marker`). `AVCameraFrameProvider` picks the wide-angle
  device for the position, and switches a running session by replacing its input inside
  `beginConfiguration`/`commitConfiguration` on the session queue, with the slot closed until the
  video queue has drained (research CAM-002-D4); rotation comes from a new
  `AVCaptureDevice.RotationCoordinator` for the new device (research CAM-002-D5).
- `CameraFeedState.notice(position:)` / `accessibilityValue(position:)` name the front camera for
  `unavailable`.

In the app:

- `AppSettings`: `cameraPosition` (`settings.camera.position`, default back), `cameraMirrorFront`
  (`settings.camera.mirrorFront`, absent → on), `cameraMirrorBack` (`settings.camera.mirrorBack`,
  absent → off), `cameraMirrored` for the current position; all in `allKeys` (cleared by
  `-uitestResetNotice`) and in `ALLOWED_KEYS` of `scripts/run_device_tests.py`.
- `SettingsView`: a "Camera" section while Camera is chosen: segmented "Camera" picker Back/Front
  (`cameraPositionPicker`) and a "Mirror" toggle (`cameraMirrorToggle`).
- `AppCoordinator.cameraSettingsChanged()` (from `VisualizerView.onChange`) applies position and
  mirror to the live host without touching the source; the host is also created with them.
- `CameraIndicator` reads "Front camera on" for the front camera; `PermissionCatalog.cameraNotice`
  passes the position for the unavailable notice; denied/restricted notices unchanged.
- The usage description changes in `project.yml`, `PermissionCatalog` and
  `docs/privacy-policy.md` together (spec Clarifications); scenes and cues unchanged (Camera is
  never recorded).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/front-camera.md](contracts/front-camera.md); checks: [quickstart.md](quickstart.md);
decision record: ADR-0017 amendment (no default overridden).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Metal, CoreVideo, AVFoundation (iOS); Compositor, SpectrumLayers. No new
dependency, no Vision, no networking.

**Storage**: three UserDefaults settings (position, two mirror flags). No pictures stored.

**Testing**: `Packages/Compositor` (`CameraGeometryTests` mirror matrix on the CPU, Linux too;
`CameraLayerTests` GPU marker tests); app unit tests (`FrontCameraTests`: settings, host switching,
the consistency acceptance across composite, REC-001 capture and REC-003 output pass); UI test
`FrontCameraUITests` with `-uitestCamera granted`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package target.

**Performance Goals**: no extra pass: the mirror is one branch in the existing fragment shader; no
per-frame allocation (CAM-001-R15).

**Constraints**: public APIs only; explicit closure types; typed steps for coordinate math (no
long untyped number expressions); no main-actor mutation in setUp/tearDown; no wall-clock
assertions; unit tests about 1-2 s, UI test under 30 s (owner rule 7). AUD-013 and ACC-006 run in
parallel: edits to `SettingsView`, `AppCoordinator`, `AppSettings` stay small and local.

**Scale/Scope**: about 10 source files touched, 3 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | AVFoundation device discovery, session reconfiguration, RotationCoordinator; no private API | Pass |
| VI / X Evidence | Simulator results only for the stand-in; real cameras are `{device}` tasks (T-device) | Pass |
| Privacy: start only on explicit action | Position and mirror are settings; the camera still starts only from choosing Camera in the session (CAM-001-R11) | Pass |
| Privacy: point-of-use permission, accurate text | Same single permission; usage text reworded for both cameras and user saves (CAM-002-R9), checked by `check_permission_catalog.py` | Pass |
| Privacy: no covert use | Badge "Front camera on", status bar never hidden (CAM-002-R8) | Pass |
| No networking | None added; `check_compliance.py` | Pass |
| Accessibility (ACC-001) | Labels/values on the picker, toggle, badge; no new animation (no `MotionPolicy` use needed) | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/096-cam-002-front-camera-layer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/front-camera.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/CameraLayer/
├── CameraFeedState.swift          # CameraPosition, position-aware notice/value
├── CameraPictureGeometry.swift    # mirrored flag in the mapping
├── CameraFrameProvider.swift      # position on CameraFrame and the protocol, slot stamping
├── CameraLayerSource.swift        # mirrored, position filter, shader flag
├── StubCameraFrameProvider.swift  # positions, missing front, .marker pattern
└── AVCameraFrameProvider.swift    # device per position, live input swap
Packages/Compositor/Tests/CompositorTests/
├── CameraGeometryTests.swift      # + mirror matrix
└── CameraLayerTests.swift         # + GPU mirror and switch tests
Apps/projectM-iOS/
├── Coordinators/AppSettings.swift, AppCoordinator.swift, PermissionCatalog.swift
├── Visuals/CameraVisualHost.swift
├── Views/SettingsView.swift, VisualizerView.swift, CameraIndicator.swift
├── Tests/FrontCameraTests.swift
└── UITests/FrontCameraUITests.swift
project.yml, docs/privacy-policy.md, scripts/run_device_tests.py, docs/adr/0017-rear-camera-layer.md
```

**Structure Decision**: extend the existing `CameraLayer` target and Camera visual host; no new
target.

## Complexity Tracking

None.
