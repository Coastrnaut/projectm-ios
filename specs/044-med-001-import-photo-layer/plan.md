# Implementation Plan: MED-001 Import Photo Layer

**Branch**: `feature/med-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/044-med-001-import-photo-layer/spec.md`

## Summary

The viewer picks one image with the system Photos picker (`PhotosPicker`, out of process, no library
permission) or the Files picker (`fileImporter`, image types). The app copies it into
`Application Support/Photos/` through the `ImageLayer` target's importer: the file is checked
(≤ 40 MB, an image, ≤ 100 million pixels), decoded upright and scaled to ≤ 4096 px by ImageIO, and
re-encoded without metadata (PNG with alpha, JPEG 0.9 otherwise). The identifier is a UUID stored
in the settings key `settings.photo.id`. A new `Photo` visual (persisted) hosts a CMP-001
compositor with a CMP-002 stack: the photo layer (`ImageLayerSource`) at the bottom, the circular
spectrum on top. The layer decodes the stored copy once on a background queue into a mipmapped
sRGB texture (straight alpha) and draws it with aspect fill, sRGB → linear and premultiplying in
the shader; until ready or on failure it throws `.notReady` (transparent fallback). Errors are
typed (`ImageImportError`) and shown as a non-blocking banner. A DEBUG-only launch flag
(`-uitestSeedPhoto <name>`) imports a generated fixture through the same path for the UI test.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: ImageIO, CoreGraphics, UniformTypeIdentifiers (import, decode, encode);
Metal (layer); PhotosUI (`PhotosPicker`) and SwiftUI `fileImporter` (app only)

**Storage**: one file in `Library/Application Support/Photos/<uuid>.{png,jpg}`; the identifier in
UserDefaults (`settings.photo.id`, an FR-065 "user setting")

**Testing**: XCTest: Compositor package tests (host macOS, iOS 27.2 simulator; Linux shape with
`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), app unit tests, one UI test

**Target Platform**: iOS/iPadOS 26.0+ (ADR-0002); package code also builds on macOS 15 and Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: no per-frame allocation, I/O or decode (CMP-001 contract); decode of a
4096 px stored copy off the main thread; one texture ≤ 64 MB (+ mips ≈ 85 MB worst case)

**Constraints**: no network (FR-068), public APIs only, no photo library permission, no
required-reason API (file timestamps, disk space) without declaration

**Scale/Scope**: one stored photo; ~8 new source files, ~5 test files

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | PhotosUI `PhotosPicker`, SwiftUI `fileImporter`, ImageIO, CoreGraphics, Metal; nothing private, no `dlsym` | Pass |
| VI. Modular boundaries | `ImageLayer` imports only Compositor, Metal, ImageIO/CoreGraphics; no projectM, ANGLE, capture or app code. The app owns storage location, settings and pickers. | Pass |
| VII. Real-time audio safety | No audio path change; the analyzer is the existing one | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Simulator and host tests with generated fixtures; real pickers, HEIC and panoramas on D1/D3 are `{device}` tasks left open | Pass |
| Security (untrusted imports) | Size, type, pixel-count checks before decode; damaged data → typed error; decoder boundary for MED-014 | Pass |
| Privacy | Privacy review in the spec; no permission; copy stripped of metadata; removable; privacy policy and App Privacy notes updated | Pass |
| FR-068 (no networking) | No networking API; compliance check runs | Pass |
| FR-065 (what is stored) | Adds the imported photo and its identifier; documented in the privacy policy (amendment like AUD-001-R22) | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/044-med-001-import-photo-layer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/image-layer.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                                  # + target ImageLayer (library product), test deps
├── Sources/ImageLayer/
│   ├── ImageImportLimits.swift                    # limits + ImageImportError (CPU, Linux)
│   ├── ImagePictureGeometry.swift                 # fill/fit math (CPU, Linux)
│   ├── ImageLayerKind.swift                       # LayerKind.photo (CPU, Linux)
│   ├── ImageDecoding.swift                        # DecodedImage, ImageDecoding protocol (CPU) + ImageIODecoder (#if canImport(ImageIO))
│   ├── ImageSanitizer.swift                       # pixels-only re-encode (#if canImport(ImageIO))
│   └── ImageLayerSource.swift                     # the LayerSource (Metal)
└── Tests/CompositorTests/
    ├── ImageGeometryTests.swift                   # CPU
    ├── ImageImportTests.swift                     # ImageIO: strip, caps, corrupt, decode
    └── ImageLayerTests.swift                      # GPU: linear color, fill, fallback

Apps/projectM-iOS/
├── Coordinators/PhotoStore.swift                  # folder, identifier, import/replace/remove
├── Coordinators/PhotoCoordinator.swift            # picker results → store, notice text
├── Visuals/PhotoVisualHost.swift                  # compositor host: photo + spectrum
├── Coordinators/AppSettings.swift                 # VisualChoice.photo (persisted), photo id key
├── Coordinators/AppCoordinator.swift              # host lifecycle, notice
├── Views/SettingsView.swift, VisualizerView.swift, ControlsOverlay.swift
├── Tests/PhotoStoreTests.swift
└── UITests/PhotoLayerUITests.swift
docs/privacy-policy.md, docs/release/app-privacy.md, docs/adr/0020-imported-photo-layer.md,
docs/test-reports/photo-layer.md
```

**Structure Decision**: the photo layer is a target of the Compositor package beside CameraLayer
and SpectrumLayers (a layer adapter; the package's one library product carries it to the app, and
CI's package loops test it). The importer and decoder live in the same target so MED-014 hardens
one module. Storage location, settings and pickers are the app's (Constitution VI).

## Complexity Tracking

`PhotoVisualHost` repeats `CameraVisualHost`'s frame loop (display link, presentation and
background handling) instead of generalizing it: changing the camera host's lifecycle is out of
scope and would put CAM-001/CAM-012 behaviour at risk. A shared "layered visual host" belongs to
the layer inspector (CMP-015) or the scene rows, which replace both fixed stacks.
