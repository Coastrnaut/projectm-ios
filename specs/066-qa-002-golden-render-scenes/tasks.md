# Tasks: QA-002 Golden Render Scenes

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/golden-suite.md, quickstart.md in
`specs/066-qa-002-golden-render-scenes/`. Tests are part of the deliverable (the row is a test
harness). Budgets (owner rule 7): each test ≤ 10 s, package suite < 1 minute on the host.

Format: `- [ ] QA-002-Tnn [P?] [USn?] description (file)`. A task is ticked only when verified,
with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] QA-002-T01 Create `Packages/RenderGoldens/Package.swift` (targets `GoldenImages`, `SceneRenderHarness`, test target `RenderGoldensTests` excluding nothing outside `Tests/`; dependencies SceneFormat, Compositor, VisualGenerators, ParameterGraph; header comment per house style) and empty source folders

## Phase 2: Foundational (plain Swift, Linux)

- [ ] QA-002-T02 [P] `GoldenImage` (width, height > 0, rgba count = width × height × 4, straight alpha) and `GoldenSHA256` (FIPS 180-4) in `Packages/RenderGoldens/Sources/GoldenImages/GoldenImage.swift`, `GoldenSHA256.swift`
- [ ] QA-002-T03 [P] `GoldenRandom` (SplitMix64) and `GoldenSceneCatalog` (7 runs: name, seed, frameCount 8, start 1 s, interval 16,666,667 ns, capturedFrames ≥ 1 and < frameCount, audio, reduceFlashing true, osSensitive, photo recipes; resolutions 128 × 96 and 256 × 192) in `Sources/GoldenImages/GoldenRandom.swift`, `GoldenSceneCatalog.swift`
- [ ] QA-002-T04 [P] `GoldenEnvironment`: platform class (`macos`, `ios-simulator`, nil), record policy (`compare`, `record` for `GOLDEN_RECORD=1`, `refused` when `CI` or `GITHUB_ACTIONS` is set), OS version major.minor in `Sources/GoldenImages/GoldenEnvironment.swift`
- [ ] QA-002-T05 [P] Unit tests: SHA-256 vectors, SplitMix64 stability, catalog rules, environment policy table in `Tests/RenderGoldensTests/GoldenSHA256Tests.swift`, `GoldenEnvironmentTests.swift`

## Phase 3: US2 — scenes with fixed seeds and clocks (P1)

- [ ] QA-002-T06 [US2] Author the 7 canonical scene documents in `Packages/RenderGoldens/Scenes/*.scene.json` (research D10)
- [ ] QA-002-T07 [US2] Scene fixture tests (contract G1: decode without warnings, canonical bytes equal the file, live state succeeds, one catalog run per file, no camera/video/unknown) in `Tests/RenderGoldensTests/GoldenSceneFixtureTests.swift`
- [ ] QA-002-T08 [US2] `GoldenLayerFactory` (material, graph via SHD-011 import, photo from generated PNG, text, circular and linear spectra; refuses camera, video, unknown) and `GoldenSceneRenderer` (contract G2: warm-up frame, settle, capture via `requestFrameCapture` + REC-001 conversion) and `GoldenPNG` in `Sources/SceneRenderHarness/`
- [ ] QA-002-T09 [US2] Determinism test: every scene twice at 128 × 96, equal pixel hashes (S2) in `Tests/RenderGoldensTests/GoldenDeterminismTests.swift`

## Phase 4: US1 — reviewable diffs on renderer changes (P1)

- [ ] QA-002-T10 [P] [US1] `GoldenTolerance.qa002` (threshold 2, fraction 0.001, rounded down) and `GoldenComparison` in `Sources/GoldenImages/GoldenComparison.swift`; `GoldenDiffImage` (grey 30 % unchanged, yellow within, red 128-255 above, magenta outside overlap) in `GoldenDiffImage.swift`
- [ ] QA-002-T11 [P] [US1] Comparison and diff tests (identical, within, exceeding at the boundary counts 12/13 of 12,288, size mismatch, diff colors) in `Tests/RenderGoldensTests/GoldenComparisonTests.swift`, `GoldenDiffImageTests.swift`
- [ ] QA-002-T12 [US1] `GoldenManifest` (canonical JSON, entries sorted by scene, width, frame) in `Sources/GoldenImages/GoldenManifest.swift`; artifact writer (expected/actual/diff PNGs, summary, per-class summary.txt, XCTest attachments) and paths in `Tests/RenderGoldensTests/GoldenArtifacts.swift`, `GoldenPaths.swift`
- [ ] QA-002-T13 [US1] Golden suite (contract G4) in `Tests/RenderGoldensTests/GoldenRenderSuiteTests.swift`; record the macOS and iOS 27.2 simulator goldens into `Packages/RenderGoldens/Goldens/{macos,ios-simulator}/`
- [ ] QA-002-T14 [US1] Deliberate-regression proof (contract G6) in `Tests/RenderGoldensTests/GoldenRegressionProofTests.swift`

## Phase 5: US3 — record only on purpose (P2)

- [ ] QA-002-T15 [US3] Record-mode behavior tests on a scratch golden folder (missing written, unchanged file untouched, refused writes nothing, missing without record fails via the suite's decision function) in `Tests/RenderGoldensTests/GoldenRecordTests.swift`

## Phase 6: US4 — consistent and small set (P3)

- [ ] QA-002-T16 [US4] `GoldenIntegrity` (data-model issues, 2,000,000-byte budget) in `Sources/GoldenImages/GoldenIntegrity.swift` and tests on the committed set plus doctored copies in `Tests/RenderGoldensTests/GoldenIntegrityTests.swift`

## Phase 7: Polish

- [ ] QA-002-T17 [P] `Packages/RenderGoldens/README.md` (scenes and licensing, record mode, review, CI guard, size), ADR `docs/adr/00NN-golden-render-scenes.md` and its index row
- [ ] QA-002-T18 Append `RenderGoldens` to the 5 package loops in `.github/workflows/ios-ci.yml`
- [ ] QA-002-T19 Verify: host `swift test`, Linux shape, iOS 27.2 simulator `xcodebuild test`, iOS 26.5 simulator cross-check, `check_compliance.py`, `validate_docs.py`, PosterBoard count; record results in this file and the spec status

## Dependencies

T01 → T02-T05 → T06-T09 (US2) → T10-T14 (US1; needs the renderer) → T15 (US3) → T16 (US4) → T17-T19.
US1 depends on US2 (it compares rendered scenes); US3 and US4 depend on the manifest (T12).

## Parallel examples

- T02, T03, T04 touch different files and can be written together; T10 and T11 likewise.

## Implementation strategy

MVP = US2 + US1 (scenes render and compare with diffs). Then the record guard (US3) and integrity
(US4), then docs and CI.
