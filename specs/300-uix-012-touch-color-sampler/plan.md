# Implementation Plan: UIX-012 Touch Color Sampler

**Branch**: `feature/uix-012` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Two plain-Swift pieces in the Compositor package's `FrameCapture` module (builds on Linux): `PreviewPixelMapping`, a
pure function from a window point through the UIX-007 split placement, the view-to-picture fit (stretch, fit, fill
with OUT-004's pixel aspect) and the picture's pixel size to an integer output pixel (or a rejection); and
`CapturedPixels.sampledColor(x:y:)`, which reads one pixel of any REC-001 capture layout and returns straight,
clamped linear RGBA. The app adds a main-actor `ColorSamplerCoordinator` that asks the shown visual's REC-001
`FrameCaptureSource` for its next presented frame (asynchronous, never blocking rendering, 1 s timeout, late frames
dropped), maps the tap with the captured size, converts to the target's space (linear `ParameterColor` or
sRGB-encoded `TextColor`, alpha kept) and writes it between SCN-010 `endCoalescing()` and one
`recordStep(label: "Sample <name>")`. A `ColorSamplingLayer` above the visualizer's tap target catches taps in window
coordinates while sampling (status, controls and the emergency blackout above it stay usable; a reporter in the
backdrop hands it the UIX-007 placement) and shows a banner with Cancel; an
`EyedropperButton` sits next to the three MED-009 text colour pickers. Results announce on the parameter lane.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; CI Xcode 26 type-check budget)
**Primary Dependencies**: Compositor package (`FrameCapture`, `Compositor`, `TextLayer`), ParameterGraph (`ParameterColor`), SwiftUI
**Storage**: none (no new UserDefaults key; the target's own value is the only state written)
**Testing**: FrameCaptureTests (pure mapping and conversion, host and Linux); CompositorTests GPU test (test pattern through the real compositor and capture); app unit tests (coordinator with a fake capture source, undo, refusals); one XCUITest with a DEBUG solid-colour capture fixture
**Target Platform**: iOS 26+ / iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: one asynchronous frame read-back per tap; no work while not sampling
**Constraints**: no wall-clock assertions (the coordinator's timeout is injected); UI test < 30 s; small SwiftUI bodies
**Scale/Scope**: three text colour targets; a generic target type for later controls

## Constitution Check

- I Public APIs only: SwiftUI `SpatialTapGesture`, Metal through the existing capture. Pass.
- VI Modular boundaries: pure geometry and conversion live in `FrameCapture` (no UIKit, Linux-buildable); the app composes them. Pass.
- VII Real-time audio safety: no audio path touched; the render loop only fulfils the existing capture request. Pass.
- Privacy/local-first: the frame stays in memory for one pixel read and is dropped; nothing stored or sent. Pass.
- X Evidence-based quality: GPU acceptance test of the transform plus read-back, unit and UI tests; the live-visual check stays a `{device}` task. Pass.

Post-design re-check: unchanged, pass. No ADR: no project default is overridden (REC-001's capture is reused as is).

## Project Structure

### Documentation (this feature)

```text
specs/300-uix-012-touch-color-sampler/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/color-sampler.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/Compositor/Sources/FrameCapture/PreviewPixelMapping.swift        # new: pure transform (C1)
Packages/Compositor/Sources/FrameCapture/CapturedPixelSample.swift        # new: one pixel → straight linear (C2)
Packages/Compositor/Tests/FrameCaptureTests/PreviewPixelMappingTests.swift # new
Packages/Compositor/Tests/CompositorTests/ColorSampleCompositorTests.swift # new: GPU acceptance (S1)
Apps/projectM-iOS/Coordinators/ColorSamplerCoordinator.swift              # new: mode, request, write, announce (C3)
Apps/projectM-iOS/Coordinators/AppCoordinator+ColorSampler.swift          # new: wiring, availability, targets
Apps/projectM-iOS/Views/ColorSamplingViews.swift                          # new: eyedropper button, sampling layer
Apps/projectM-iOS/Views/VisualizerView.swift                              # 3 small edits: sampling layer, placement reporter, split flag
Apps/projectM-iOS/Views/SettingsView.swift                                # eyedroppers by the 3 text colour pickers
Apps/projectM-iOS/Tests/ColorSamplerTests.swift                           # new
Apps/projectM-iOS/UITests/ColorSamplerUITests.swift                       # new
scripts/check_status_events.py                                            # list the new files
```

**Structure Decision**: geometry and pixel reading in the package (testable without a device or UIKit); mode and
writes in the app next to REC-001's coordinator, whose `FrameCaptureSource` it reuses.

## Complexity Tracking

None.
