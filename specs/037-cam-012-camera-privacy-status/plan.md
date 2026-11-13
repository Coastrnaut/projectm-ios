# Implementation Plan: CAM-012 Camera Privacy Status

**Branch**: `feature/cam-012` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/037-cam-012-camera-privacy-status/spec.md`

## Summary

Add an in-app "Camera on" badge with a "Stop camera" button to the visualizer. The badge is
derived only from the camera feed state that CAM-001's provider reports (starting or running →
shown). Stop camera stops the camera synchronously in the Camera visual's host (the provider's
`stop()` returns with the slot closed, the picture dropped and the state idle; the host never
restarts it), then the coordinator returns `settings.visual` to the visual chosen before Camera
(the stored key) and switches visuals the usual way, which releases the Camera visual and resumes
the fallback visual. Audio is untouched. App-only change: no package changes, no ADR (no default
is overridden; the decisions are in the spec's Clarifications and research.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 language mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: SwiftUI, UIKit (existing app); CameraLayer (CAM-001, unchanged).

**Storage**: none (CAM-012-R8). The stored visual key is only read.

**Testing**: app unit tests `CameraPrivacyStatusTests` (stub provider; the host's frame loop in a
window for the no-freeze test) and UI test `CameraPrivacyStatusUITests` on an iOS 27.2 simulator
with `-uitestCamera granted` (DEBUG only).

**Target Platform**: iOS/iPadOS 26.0+.

**Project Type**: iOS app.

**Performance Goals**: Stop camera does no blocking work on the main thread beyond CAM-001's
provider `stop()`; the visualizer keeps producing frames across the switch.

**Constraints**: public APIs only; no wall-clock assertions; explicit closure types; unit tests
about 1-2 s (≤10 s), UI test under 30 s (owner rule 7).

**Scale/Scope**: about 120 lines of app Swift, 150 of unit tests, 80 of UI test.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | SwiftUI and UIKit accessibility; nothing private | Pass |
| VI. Modular boundaries | App-only; CameraLayer package unchanged | Pass |
| VII. Real-time audio safety | No audio path change; Stop never touches the source | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Simulator tests with the stub only; the real camera indicator is `{device}` task CAM-012-T13, left open | Pass |
| Security | No credentials, no signing change | Pass |
| Privacy (capture stops when the user stops it) | Stop camera is exactly that control for the camera; spec "Privacy review" | Pass |
| FR-068 (no networking) | None added | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/037-cam-012-camera-privacy-status/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/camera-privacy-status.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Visuals/CameraVisualHost.swift          # stopCamera(): synchronous stop, never restarted; frame counter
├── Coordinators/AppCoordinator.swift       # cameraIndicator, stopCamera(), fallback switch
├── Coordinators/AppSettings.swift          # visualBeforeCamera (reads the stored key)
├── Views/CameraIndicator.swift             # the badge with Stop camera (new)
├── Views/VisualizerView.swift              # shows the badge
├── Tests/CameraPrivacyStatusTests.swift    # new
└── UITests/CameraPrivacyStatusUITests.swift  # new
docs/privacy-policy.md                      # one sentence: the badge and Stop camera
```

**Structure Decision**: app target only; the indicator rule is a pure static function on a small
value type so it is unit-testable without the coordinator.

## Complexity Tracking

None.
