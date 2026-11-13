# Implementation Plan: QA-002 Golden Render Scenes

**Branch**: `feature/qa-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/066-qa-002-golden-render-scenes/spec.md`

## Summary

A new package, `Packages/RenderGoldens`, holds seven small scene documents (canonical SCN-001 JSON
authored here), their run settings (seed, clock, audio, captured frames) and per-platform golden PNGs
with a manifest. Its plain-Swift target `GoldenImages` hashes (own SHA-256), compares (fixed QA-002
tolerance), draws diff images, reads and writes the manifest, checks integrity and decides record mode;
it builds and is tested on Linux. Its Metal target `SceneRenderHarness` turns a scene's live state
(SCN-001 `liveState`) into compositor layers (photo, material, graph, spectra, text), renders the
fixed frames at 128 × 96 and 256 × 192 through the `Compositor` with the flash guard on, and captures
the shown frame with REC-001's capture and 8-bit sRGB conversion; PNG coding is REC-001's
`FrameImageEncoder`. The test target compares every capture with its golden, attaches and writes
expected/actual/diff images on failure, records only with `GOLDEN_RECORD=1` outside CI, proves a
deliberate regression fails, and checks the manifest's integrity. ADR-0030 (or the next free number
at commit time) records the golden policy.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: SceneFormat (decode, validate, live state), Compositor package (Compositor,
ProceduralMaterials, GeneratorGraph, GeneratorGraphImport, ImageLayer, TextLayer, SpectrumLayers,
FrameCapture), VisualGenerators (spectrum generators, visual parameter catalog), ParameterGraph
(registry, store)

**Storage**: files in the repository: `Packages/RenderGoldens/Scenes/*.scene.json`,
`Packages/RenderGoldens/Goldens/<class>/*.png` + `manifest.json`; failure artifacts in the gitignored
`Packages/RenderGoldens/.build/golden-diffs/<class>/`

**Testing**: XCTest; `swift test` on the Mac host and the Linux shape
(`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`);
`xcodebuild test -scheme RenderGoldens` on an iOS 27.2 simulator (and a cross-check on iOS 26.5)

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI

**Project Type**: Swift package (test infrastructure library + tests)

**Performance Goals**: the golden suite (7 scenes × 2 resolutions, 8 frames each) in a few seconds on
the host; every test ≤ 10 s; package suite < 1 minute (owner rule 7)

**Constraints**: no new Metal source (SHD-011 allowlist: only existing passes are used); public APIs;
deterministic inputs (fixed times, seeded bands, seeded images); no wall-clock assertions;
no main-actor mutation in setUp/tearDown

**Scale/Scope**: 7 scenes, 8 captures per class and resolution → 32 golden PNGs; budget < 2 MB total

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Metal, ImageIO (via FrameCapture), Foundation. Pass. |
| VI Modular boundaries | A test-infrastructure package that depends on the render packages; nothing depends on it; no app, projectM or capture change. Pass. |
| VII Real-time safety | Test-only code; no audio path touched. Pass. |
| IX Dependencies and licenses | No third-party dependency; SHA-256 written in Swift (no swift-crypto). Scenes, graphs, text and generated images are this repository's (MIT). Pass. |
| X Evidence | Unit tests for the plain logic on two hosts; GPU goldens on the host and the simulator are regression evidence for those platforms only, never device or performance evidence. Pass. |
| Security | Scenes go through SCN-001 decoding and validation and SHD-011's graph import like user files; nothing is executed. Pass. |
| Privacy | No user data; images are generated. Pass. |

No deviation. A new ADR records the golden policy (platform classes, tolerance, record switch, CI
guard, text OS rule), because it sets a project-wide testing default that QA-003 and QA-006 build on.

## Project Structure

### Documentation (this feature)

```text
specs/066-qa-002-golden-render-scenes/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/golden-suite.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
Packages/RenderGoldens/
├── Package.swift
├── README.md                              (record mode, review, CI guard, budgets)
├── Scenes/*.scene.json                    (7 canonical SCN-001 documents)
├── Goldens/macos/, Goldens/ios-simulator/ (PNGs + manifest.json each)
├── Sources/GoldenImages/                  (plain Swift; Linux)
│   ├── GoldenImage.swift                  (RGBA8 straight pixels)
│   ├── GoldenSHA256.swift
│   ├── GoldenComparison.swift             (tolerance rule, result)
│   ├── GoldenDiffImage.swift
│   ├── GoldenManifest.swift               (entries, canonical JSON)
│   ├── GoldenIntegrity.swift
│   ├── GoldenEnvironment.swift            (platform class, record policy, OS version)
│   ├── GoldenRandom.swift                 (SplitMix64)
│   └── GoldenSceneCatalog.swift           (run settings, audio, generated photos)
├── Sources/SceneRenderHarness/            (Metal; compiled out on Linux)
│   ├── GoldenLayerFactory.swift
│   ├── GoldenSceneRenderer.swift
│   └── GoldenPNG.swift                    (FrameImageEncoder bridge)
└── Tests/RenderGoldensTests/
    ├── GoldenPaths.swift, GoldenArtifacts.swift (shared helpers)
    ├── GoldenSHA256Tests.swift, GoldenComparisonTests.swift, GoldenDiffImageTests.swift,
    │   GoldenManifestTests.swift, GoldenEnvironmentTests.swift, GoldenIntegrityTests.swift,
    │   GoldenSceneFixtureTests.swift      (Linux)
    └── GoldenRenderSuiteTests.swift, GoldenDeterminismTests.swift, GoldenRegressionProofTests.swift (GPU)
.github/workflows/ios-ci.yml                (RenderGoldens appended to the 5 package loops)
.gitignore (none needed: `.build/` is already ignored)
docs/adr/00NN-golden-render-scenes.md, docs/adr/README.md (index row)
docs/FEATURE_ROADMAP_AUTONOMOUS.md         (none: the run's status files are the orchestrator's)
```

**Structure Decision**: a new package rather than a test target in SceneFormat or Compositor: the
golden set is cross-cutting (it needs SceneFormat and every layer target), QA-003 and QA-006 will build
on it, and keeping it separate keeps the existing packages' suites short. Fixtures live outside the
targets and are found through the test file's `#filePath` (no resource bundle), so record mode can
write them back into the source tree from the host and from the simulator.

## Complexity Tracking

None.
