# Tasks: SHD-012 Authoring Preview Fixture

**Input**: `specs/249-shd-012-authoring-preview-fixture/` (spec, plan, research, data-model, contracts, quickstart)

Tests are requested by the spec (acceptance S1-S5). Budgets: unit tests ≤ 10 s, suites < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] SHD-012-T01 Add target `AuthoringPreview` (deps Compositor, ProceduralMaterials, ParameterGraph, VisualGenerators product) and test target `AuthoringPreviewTests` to the `Compositor` product in Packages/Compositor/Package.swift, with a header note

## Phase 2: Foundational

- [ ] SHD-012-T02 Implement `AuthoringPreviewFixture` (seed UInt64, seconds > 0 default 4, fps > 0 default 30; `frameCount`, `audio()`) in Packages/Compositor/Sources/AuthoringPreview/AuthoringPreviewFixture.swift
- [ ] SHD-012-T03 Implement `AuthoringPreviewRequest`, `AuthoringPreviewFrame`, `AuthoringPreviewTrajectory` and `AuthoringPreviewSequencer` (contract P1: bindings validated by `replaceBindings`; per frame analysis → modulator → effective values → motion) in Packages/Compositor/Sources/AuthoringPreview/AuthoringPreviewSequencer.swift

## Phase 3: User Story 2 - Two runs are identical (P1, the acceptance)

**Independent test**: trajectories and checksum sequences compared exactly across runs.

- [ ] SHD-012-T04 [US2] Trajectory tests: two runs equal (exact Double), per-frame and chunk-of-7 stepping equal a single pass, changed seed and changed binding target/source differ, refused binding throws, no-binding run, frame count 0, in Packages/Compositor/Tests/AuthoringPreviewTests/AuthoringPreviewTrajectoryTests.swift
- [ ] SHD-012-T05 [US2] Implement `AuthoringPreviewRecorder` and `AuthoringPreviewRecording` (contract P3: layer prepared once, per-frame values, `LayerFrameClock` at 1 s + t(n), bands as audio context, Reduce flashing on, half-float read-back, SHA-256 per frame, run digest, optional RGBA8 frames) in Packages/Compositor/Sources/AuthoringPreview/AuthoringPreviewRecorder.swift
- [ ] SHD-012-T06 [US2] GPU tests on the host: two recordings give equal checksum sequences and equal trajectories; the layer's motion matches the trajectory; a changed setting changes checksums, in Packages/Compositor/Tests/AuthoringPreviewTests/AuthoringPreviewRecorderTests.swift
- [ ] SHD-012-T07 [US2] Linux shape: build and run the trajectory tests with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE` (Packages/Compositor)

## Phase 4: User Story 1 - Preview a material against the fixture (P1)

**Independent test**: UI test plays the fixture twice and reads the same digest.

- [ ] SHD-012-T08 [US1] `FixturePreviewStore` (session state: target, source, seed 1…99; background run with its own recorder; `rendering`/`ready`; loop frame index; stop on settings change; summary text) in Apps/projectM-iOS/Coordinators/FixturePreviewStore.swift
- [ ] SHD-012-T09 [US1] Fixture preview section (pickers, seed stepper, Play/Stop, picture via `TimelineView` without `.animation`, Reduce Motion: no auto-play, frame slider with `.accessibleParameter`, summary) in Apps/projectM-iOS/Views/FixturePreviewSection.swift and wire it into Apps/projectM-iOS/Views/NoiseEditorView.swift
- [ ] SHD-012-T10 [US1] App unit tests (default binding, summary text, same digest twice, seed change changes the trajectory, settings change stops the loop) in Apps/projectM-iOS/Tests/FixturePreviewStoreTests.swift
- [ ] SHD-012-T11 [US1] UI test: open Noise editor, Play fixture, read summary "120 frames", play again, same digest, in Apps/projectM-iOS/UITests/FixturePreviewUITests.swift

## Phase 5: Polish

- [ ] SHD-012-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols), type-check budget, spec status
- [ ] SHD-012-T13 {device} On D1: Settings › Noise editor › Play fixture; the loop plays smoothly, the warp follows the kicks, a second Play shows the same run digest

## Dependencies

T01 → T02 → T03 → T04 (US2 trajectory) → T05 → T06, T07 → T08 → T09 → T10, T11 → T12. T13 needs a device.

## Parallel opportunities

T04 and T05 touch different files once T03 is in; T10 and T11 after T09.

## Implementation strategy

MVP = US2 (the acceptance in the package), then US1 (the editor).
