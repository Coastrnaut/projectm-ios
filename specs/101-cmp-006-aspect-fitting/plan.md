# Implementation Plan: CMP-006 Aspect Fitting

**Branch**: `feature/cmp-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/101-cmp-006-aspect-fitting/spec.md`

## Summary

One plain-Swift fit model in the `Compositor` target, used by the photo and video layers, chosen
per stack entry and saved in scenes.

In `Packages/Compositor`:

- `LayerFit.swift` (target `Compositor`, plain Swift, builds on Linux): `LayerFitMode` (`fill`,
  `fit`, `stretch`, `pixelAccurate`; `String`-backed, `CaseIterable`), `LayerFit` (mode + anchor,
  anchor clamped to 0…1) and `LayerFitPlacement`, the pure function of the spec: content pixel size,
  output pixel size, fit and an output-pixels-per-content-pixel factor (default 1) → the visible
  content rectangle (`visible`, `offset`, in content fractions) plus derived values: the content's
  rectangle in output fractions, the pixel aspect, the content → output matrix, and that matrix
  composed with a CMP-005 transform (research CMP-006-D1 to D4). Computed in typed `Double` steps.
- `LayerCompositeSettings` gains `fit: LayerFit?` (nil: the layer's default). A new Metal-side
  protocol `LayerFitting: AnyObject` (`var fit: LayerFit? { get set }`) lets the compositor hand a
  stack entry's fit to a layer at `init` and `apply` (shown from the next frame, nothing re-created;
  research CMP-006-D5). Compositing itself is unchanged: fitting happens inside the layer picture.
- `ImageLayer`: `ImageScaleMode` becomes a type alias of `LayerFitMode`; `ImagePictureGeometry`
  delegates to `LayerFitPlacement` (fill and fit give the same numbers as before; new anchor
  parameter). `ImageLayerSource` adopts `LayerFitting`; its init `mode` is the default used while
  `fit` is nil.
- `VideoLayer`: a plain-Swift `VideoPictureGeometry` (placement on the upright size + the track's
  quarter turn) replaces the use of CameraLayer's `CameraPictureGeometry`; the video shader draws
  transparent outside the content (fit, pixelAccurate). `VideoLayerSource` adopts `LayerFitting`.
- CameraLayer, text, spectra, materials and graphs are not changed (spec Baseline, R11, R12).

In `Packages/SceneFormat`:

- `SceneFit` (`mode: String`, `anchor: LayerPoint`) and `SceneComposite.fit: SceneFit?`; decode
  (closed object, `mode` required, `anchor` optional and clamped with `valueClamped`), encode only
  when set; validation warning `unsupportedFitMode` for an unknown name; SCN-012 repair report lists
  it as a note; `liveState` maps known names to `LayerFit`, unknown ones to nil and keeps them in
  `SceneLiveState.preservedFits`; `init(capturing:)` writes the live fit or the preserved one while
  the live fit is nil. Format version unchanged.

Docs: SCN-001 contract and ADR-0028 consequence list `composite.fit`; MED-001 contract notes the
modes. No ADR (no default changes; spec Clarifications). No UI.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/aspect-fitting.md](contracts/aspect-fitting.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from the modules' Swift constants (ADR-0009 decision 3).

**Primary Dependencies**: Metal, AVFoundation (video, unchanged). No new dependency.

**Storage**: the scene document (`composite.fit`, optional; version 1).

**Testing**: `Packages/Compositor`: `LayerFitGeometryTests` (CPU, Linux: mode table, anchor across
orientations, transform composition, edge cases), `LayerFitCompositeTests` (GPU read-back of a
portrait marker photo in portrait then landscape output per mode, with a blend mode and a
transform; video geometry on the GPU through a synthetic texture is covered by the plain-Swift
`VideoPictureGeometry` tests plus one GPU case if a video fixture is cheap), existing
`ImageGeometryTests`. `Packages/SceneFormat`: round trip, unknown mode, clamping, byte identity.
Regression: SceneFormat, RenderGoldens, ImportFuzz, ShowControl, SceneArchive, app unit tests.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added render pass; per-frame cost of the placement is a few arithmetic
operations on the CPU. GPU time per mode measured on the Mac (CMP-006-S5), not device evidence.

**Constraints**: owner rule 7 (unit tests ~1-2 s, suite < 1 min); no wall-clock assertions; no
CameraLayer edits (CAM-007 in parallel); typed steps for matrix arithmetic (type-checker limits).

**Scale/Scope**: S. Two layer sources, one model file, scene format optional field.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal and run-time shader source as already used | Pass |
| VI Modular boundaries | Model in `Compositor`, used by `ImageLayer`/`VideoLayer`; document in `SceneFormat`; CameraLayer untouched | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | Unit + GPU read-back tests on the Mac and simulator; GPU time labelled not device evidence | Pass |
| X ADR for overriding defaults | No default changes (no fit = today's fill) | Pass (no ADR) |
| Accessibility / flashing | Composite flash guard unchanged, runs on the finished composite | Pass |
| No networking, privacy | None added | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/101-cmp-006-aspect-fitting/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/aspect-fitting.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerFit.swift            (new)
Packages/Compositor/Sources/Compositor/LayerContract.swift       (settings.fit, LayerFitting)
Packages/Compositor/Sources/Compositor/Compositor.swift          (hand fit to layers)
Packages/Compositor/Sources/ImageLayer/ImagePictureGeometry.swift
Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift
Packages/Compositor/Sources/VideoLayer/VideoPictureGeometry.swift (new)
Packages/Compositor/Sources/VideoLayer/VideoLayerSource.swift
Packages/Compositor/Tests/CompositorTests/LayerFitGeometryTests.swift (new)
Packages/Compositor/Tests/CompositorTests/LayerFitCompositeTests.swift (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneValidation,SceneIssue,SceneLiveState,SceneRepair}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneFitTests.swift  (new)
docs/test-reports/aspect-fitting.md                              (new)
```

**Structure Decision**: existing packages only; no new target.

## Complexity Tracking

None.
