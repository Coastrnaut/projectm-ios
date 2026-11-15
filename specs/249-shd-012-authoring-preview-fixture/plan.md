# Implementation Plan: SHD-012 Authoring Preview Fixture

**Branch**: `feature/shd-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/249-shd-012-authoring-preview-fixture/spec.md`

## Summary

A deterministic "authoring preview" for procedural materials: REC-013's seeded fixture audio, analysed by the
ANL-016 pipeline stepped synchronously (`OfflineAnalysisDriver`) and paced by `OfflineFrameClock`, drives MOD-002
bindings (`AudioFeatureModulator`) and the material's motion (`MaterialMotion`). A plain-Swift sequencer records
the per-frame trajectory (bound parameter values, phase, audio level); a Metal recorder draws each frame through
the material layer's own GPU code (the SHD-006 preview path) and records a SHA-256 per frame. The Noise editor
gains a "Fixture preview" section that plays the run as a loop.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26 and Linux Swift 6.4.2)

**Primary Dependencies**: Compositor package (`Compositor`, `ProceduralMaterials`), VisualGenerators
(`VisualBandFeed`: REC-013 offline core), ParameterGraph (MOD-002), CryptoKit (Apple only), SwiftUI (app)

**Storage**: None (preview binding and fixture seed are session state; no new UserDefaults keys)

**Testing**: XCTest: package tests on the macOS host (GPU part on the host GPU) and the Linux shape
(`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`); app unit test of the store; one UI test

**Target Platform**: iOS 26+ app; package logic also Linux

**Project Type**: mobile app + Swift packages

**Performance Goals**: a 120-frame, 128 × 128 run in about a second on a recent device, off the main thread

**Constraints**: no wall clock, no live audio, no new shader code from input (ADR-0024), no new Metal library
compile path (reuses the layer's reviewed `prepare`); unit tests ≤ 10 s, UI test < 30 s

**Scale/Scope**: one new package target (~3 files), one app store + view section, tests

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs | Metal, CryptoKit, SwiftUI only. Pass. |
| VI Modular boundaries | New target depends on Compositor, ProceduralMaterials, VisualBandFeed, ParameterGraph; no app, projectM, capture imports. Pass. |
| VII Real-time audio safety | No audio callback involved; fixture analysis runs on the preview's task. Pass. |
| X Evidence | Determinism proven by package tests on the host GPU; simulator only for UI; device look is `{device}`. Pass. |
| Security / SHD-011 (ADR-0024) | No user text becomes code; the material's module-constant shader is compiled by the existing reviewed file. Pass. |
| Accessibility (ACC-001) | Loop respects Reduce Motion; Reduce flashing on; controls labelled. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/249-shd-012-authoring-preview-fixture/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/authoring-preview.md
└── tasks.md
```

### Source Code

```text
Packages/Compositor/Package.swift                       # + target AuthoringPreview, test target AuthoringPreviewTests
Packages/Compositor/Sources/AuthoringPreview/
├── AuthoringPreviewFixture.swift      # seed, seconds, fps → audio, frame count (plain Swift)
├── AuthoringPreviewSequencer.swift    # trajectory: analysis → modulator → motion per frame (plain Swift)
└── AuthoringPreviewRecorder.swift     # Metal: draws each frame, SHA-256 per frame (Apple only)
Packages/Compositor/Tests/AuthoringPreviewTests/
├── AuthoringPreviewTrajectoryTests.swift   # Linux-shape determinism, chunking, seed/binding sensitivity
└── AuthoringPreviewRecorderTests.swift     # host GPU: identical checksum sequences, changed setting differs
Apps/projectM-iOS/Coordinators/FixturePreviewStore.swift   # editor state, background run, loop index
Apps/projectM-iOS/Views/NoiseEditorView.swift              # + Fixture preview section
Apps/projectM-iOS/Views/FixturePreviewSection.swift        # the section (small bodies)
Apps/projectM-iOS/Tests/FixturePreviewStoreTests.swift
Apps/projectM-iOS/UITests/FixturePreviewUITests.swift
```

**Structure Decision**: the new target lives in the Compositor package next to `ProceduralMaterials`, which it
drives; the package is already in CI's `PKGS_VISUAL` group, so no CI change is needed.

## Complexity Tracking

None.
