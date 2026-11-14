# Tasks: CMP-006 Aspect Fitting

**Input**: Design documents from `specs/101-cmp-006-aspect-fitting/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/aspect-fitting.md, quickstart.md

Tests are part of the row's verification (unit tests, snapshots, GPU performance), so test tasks are
included. Budgets (owner rule 7): unit test about 1-2 s and at most 10 s, package suite under 1 minute.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] CMP-006-T01 Run the baseline before any change: `swift test --package-path Packages/Compositor` and `swift test --package-path Packages/SceneFormat` on the Mac; record counts in docs/test-reports/aspect-fitting.md

## Phase 2: Foundational (blocks every story)

- [ ] CMP-006-T02 Add `LayerFitMode` (raw values "fill", "fit", "stretch", "pixelAccurate"; `CaseIterable`), `LayerFit` (mode, anchor "clamped to 0…1; non-finite reads 0.5"; `.default` = fill, centre) and `LayerFitPlacement` (visible, offset, `textureCoordinate`, `contentRect`, `pixelAspect`, `contentToOutput`, `placed(transform:outputWidth:outputHeight:)`; any size ≤ 0 → identity; pixelAccurate origin rounded to whole output pixels) in typed `Double` steps, outside any Metal guard (CMP-006-R1-R6) in Packages/Compositor/Sources/Compositor/LayerFit.swift
- [ ] CMP-006-T03 Add `fit: LayerFit?` (default nil) to `LayerCompositeSettings` and the Metal-side protocol `LayerFitting: AnyObject { var fit: LayerFit? { get set } }` in Packages/Compositor/Sources/Compositor/LayerContract.swift; the compositor sets a conforming layer's `fit` from its settings at `init(device:layers:)`, when a layer is created at `apply`, and for kept layers at every `apply` (CMP-006-R7; research D5) in Packages/Compositor/Sources/Compositor/Compositor.swift
- [ ] CMP-006-T04 [P] CPU tests: the 2 × 2 × 4 table (portrait/landscape content × portrait/landscape output × four modes) asserting fill covers (visible ≤ 1), fit shows all (visible ≥ 1), stretch maps corners, pixelAccurate 1:1, pixel aspect 1 except stretch; equal-aspect content; identity for zero sizes; anchor clamping; composed matrix with a rotated uniform-scale CMP-005 transform keeps square pixels (CMP-006-S1) in Packages/Compositor/Tests/CompositorTests/LayerFitGeometryTests.swift

## Phase 3: User Story 1 - Choose how a photo or video fills the output (P1) 🎯 MVP

**Goal**: photo and video draw in any of the four modes. **Independent test**: geometry table plus GPU read-back.

- [ ] CMP-006-T05 [US1] Photo: `ImageScaleMode` becomes `typealias ImageScaleMode = LayerFitMode`; `ImagePictureGeometry` delegates to `LayerFitPlacement` (new `anchor` parameter, default centre; fill and fit numbers unchanged); `ImageLayerSource` adopts `LayerFitting` and uses `fit ?? LayerFit(mode: mode)` in `render` in Packages/Compositor/Sources/ImageLayer/ImagePictureGeometry.swift and ImageLayerSource.swift
- [ ] CMP-006-T06 [US1] Video: plain-Swift `VideoPictureGeometry` (placement on the upright size + `CameraRotation` mapping) in Packages/Compositor/Sources/VideoLayer/VideoPictureGeometry.swift; `VideoLayerSource` adopts `LayerFitting`, stops calling `CameraPictureGeometry`, and its shader returns transparent outside 0…1 in Packages/Compositor/Sources/VideoLayer/VideoLayerSource.swift
- [ ] CMP-006-T07 [P] [US1] CPU tests: `VideoPictureGeometry` fill equals the old `CameraPictureGeometry` fill for every rotation (today's output unchanged), fit and pixelAccurate on a rotated portrait track in Packages/Compositor/Tests/CompositorTests/LayerFitGeometryTests.swift; existing ImageGeometryTests still pass
- [ ] CMP-006-T08 [US1] GPU tests: a portrait marker photo (coloured corner and centre markers on a grey field) drawn through `ImageLayerSource` into a portrait output per mode; read pixels at the positions `LayerFitPlacement` predicts (markers present, bars transparent in fit and pixelAccurate, 1:1 texels in pixelAccurate); one video case: the rotated `VideoFixtures` clip (upright 48 × 64) in fit mode in a landscape output shows the clip's colour in the centre and transparent bars (CMP-006-S3, R7) in Packages/Compositor/Tests/CompositorTests/LayerFitCompositeTests.swift

## Phase 4: User Story 2 - The chosen crop survives landscape output (P1)

**Goal**: same behaviour and anchor in landscape output. **Independent test**: anchor table plus GPU portrait → landscape.

- [ ] CMP-006-T09 [P] [US2] CPU tests: for fill, fit, pixelAccurate and anchors centre, (0.5, 0), (0, 0), (1, 0.5), the anchor lands on the same output fraction in a portrait and a landscape output (1e-9; pixelAccurate within one output pixel) and the mode rule holds in both (CMP-006-S2) in Packages/Compositor/Tests/CompositorTests/LayerFitGeometryTests.swift
- [ ] CMP-006-T10 [US2] GPU tests: the same compositor and photo layer rendered into a portrait output and then a landscape output, per mode, markers found where predicted at both sizes; one case with a non-normal blend mode (`screen` over a backdrop layer) and one with a CMP-005 transform; a fit change at `apply` shown next frame without reloading the photo; a fit set on a layer that does not adopt `LayerFitting` changes nothing (CMP-006-S3, R7, R8, R11) in Packages/Compositor/Tests/CompositorTests/LayerFitCompositeTests.swift
- [ ] CMP-006-T11 [US2] GPU performance: time the photo layer per mode on the Mac (GPU start/end times over a few frames, printed, no assertion), recorded in docs/test-reports/aspect-fitting.md as not device evidence (CMP-006-S5) in Packages/Compositor/Tests/CompositorTests/LayerFitCompositeTests.swift

## Phase 5: User Story 3 - Scenes keep the mode (P2)

**Goal**: `composite.fit` saved and restored. **Independent test**: decode/validate/load/capture/encode round trips.

- [ ] CMP-006-T12 [US3] `SceneFit` (`mode: String` "any string kept", `anchor: LayerPoint` "optional (centre), clamped 0…1 with valueClamped") and `SceneComposite.fit: SceneFit?`; decoder accepts `fit` as a closed object (other keys `droppedField`, missing `mode` malformed); encoder writes `fit` only when set in Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift, SceneDecoding.swift, SceneEncoding.swift
- [ ] CMP-006-T13 [US3] Validation warning `unsupportedFitMode` (repair report: note) for a mode not in `LayerFitMode`; `liveState` maps known modes to `LayerCompositeSettings.fit`, unknown to nil kept in `SceneLiveState.preservedFits`; `init(capturing:)` writes the live fit, or the preserved one while the live fit is nil (CMP-006-R9, R10) in Packages/SceneFormat/Sources/SceneFormat/SceneIssue.swift, SceneValidation.swift, SceneRepair.swift, SceneLiveState.swift
- [ ] CMP-006-T14 [US3] Tests: each mode and an anchor survive decode → live → capture → encode; unknown mode warned, drawn as default, written back; anchor clamping warning; `fit` without `mode` malformed; a scene without `fit` re-encodes byte-identically (CMP-006-S4) in Packages/SceneFormat/Tests/SceneFormatTests/SceneFitTests.swift

## Phase 6: Polish & cross-cutting

- [ ] CMP-006-T15 Linux shape: `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerFitGeometryTests`
- [ ] CMP-006-T16 Regression: Compositor, SceneFormat, RenderGoldens (no golden re-recorded), ImportFuzz, ShowControl, SceneArchive package tests; app unit tests on a dedicated "CMP6 iPhone 17" iOS 27.2 simulator (`-only-testing:projectM-iOSTests`), simulator deleted afterwards
- [ ] CMP-006-T17 Docs: check the spec's camera adoption section is current (CMP-006-R12); SCN-001 contract and ADR-0028 list `composite.fit`; MED-001 image-layer contract notes the four modes; docs/test-reports/aspect-fitting.md with the geometry and GPU tables; spec status Implemented
- [ ] CMP-006-T18 Checks: `python3 scripts/check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`

## Dependencies

- T01 → T02 → T03; T04 after T02.
- US1 (T05-T08) after T03; US2 (T09-T11) after US1's layer code (T05); US3 (T12-T14) after T02 (independent of US1/US2).
- Polish after all stories.

## Parallel examples

- T04, T07 and T09 are CPU tests in one file but separate test methods; written together after T02.
- US3 (SceneFormat) can proceed in parallel with US1/US2 (Compositor layers).

## Implementation strategy

MVP = Phase 2 + US1 (modes drawn for photo and video). Then US2 (the acceptance criterion's
orientation proof), then US3 (persistence), then polish. Commit after each phase.

## Analysis (speckit-analyze, 2026-11-14)

Applied: S2's pixelAccurate tolerance aligned with the contract (half an output pixel); the plan's
optional video GPU case made a definite T08 case; R11 (fit ignored by other layers) given a test in
T10; R12 (camera adoption note) checked in T17. Coverage after the fixes: R1-R12 and S1-S5 each map
to at least one task; no constitution conflict; no unresolved placeholder.
