# Implementation Plan: MED-009 Text Overlay

**Branch**: `feature/med-009` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/053-med-009-text-overlay/spec.md`

## Summary

A new `TextLayer` target in the Compositor package draws one `TextOverlaySpec` (message, font,
weight, size, color, alignment, vertical position, outline, background box) as a CMP-001 layer.
The spec, its cleaning (control characters, 280 grapheme clusters, 8 lines), its versioned JSON,
the message direction (first strong letter) and the placement arithmetic are plain Swift and build
on Linux. `TextRasterizer` draws the spec with CoreText into an 8-bit sRGB premultiplied CPU bitmap
(a `TextRendering`: the text area's rectangle of the picture, its pixels, the ink bounds and an
FNV-1a 64 checksum), single-threaded and therefore byte-deterministic for the same spec and picture
size. `TextLayerSource` rasterizes on a background serial queue only when the spec or the picture
size changes, converts the bitmap once to linear premultiplied half floats (CMP-001-R2) and uploads
it into a texture of the rendering's size. Per frame `render` only clears the picture (a render pass
with a clear load action and no draw) and blits the uploaded texture into its rectangle: **no new
shader**, so SHD-011's Metal-source allowlist is unchanged.

The app adds a persisted "Text" visual (`TextVisualHost`: the circular spectrum at index 0, the text
at index 1, through `LayerStack`), a `TextOverlayStore` (one UserDefaults key
`settings.text.overlay` holding the versioned JSON), a `TextOverlayCoordinator` (the editor's model)
and a small editor section in Settings. DEBUG builds add `-uitestSeedText <message>` and an
accessibility element `textRendering` with the rendering's size and checksum; the UI test compares
it before and after a relaunch (MED-009-S1).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: CoreText and CoreGraphics (rasterizer), Metal (upload and blit), Foundation
(`JSONEncoder`/`JSONDecoder`); SwiftUI `TextField`, `Picker`, `Slider`, `ColorPicker` (app only)

**Storage**: UserDefaults key `settings.text.overlay` (an FR-065 "user setting"): JSON
`{"version":1,…}`, a few hundred bytes

**Testing**: XCTest: Compositor package tests (host macOS, iOS 27.2 simulator; Linux shape with
`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), app unit tests, one UI test.
Unicode fixtures are string literals in the tests; no fonts or media are checked in.

**Target Platform**: iOS/iPadOS 26.0+ (ADR-0002); package code also builds on macOS 15 and Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: per frame one clear pass and one blit, no allocation, no lock wait, no text
drawing (CMP-001 contract); a rasterization (only on a change) of a phone-sized text area in tens of
milliseconds, off the frame loop

**Constraints**: no network (FR-068), public APIs only, no new shader source (SHD-011), no bundled
fonts, no new permission

**Scale/Scope**: one overlay; ~8 new package source files, ~4 app files, ~3 test files

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | CoreText, CoreGraphics, Metal, SwiftUI; nothing private, no `dlsym` | Pass |
| VI. Modular boundaries | `TextLayer` imports only Compositor (and CoreText/CoreGraphics/Metal); no projectM, ANGLE, capture or app code. The app owns storage, settings and the editor. | Pass |
| VII. Real-time audio safety | No audio path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| IX. Pinned dependencies | No new dependency; system fonts only, nothing bundled | Pass |
| X. Evidence | Host, Linux-shape and simulator tests with deterministic fixtures; Dynamic Type, right-to-left and emoji input on D1/D3 are a `{device}` task left open | Pass |
| Security (untrusted input) | The message is cleaned and bounded before storage and drawing; damaged or newer stored values never crash (typed decode result) | Pass |
| Privacy | Privacy review in the spec; no permission; text stays on the device; privacy policy stored-data list updated | Pass |
| FR-068 (no networking) | No networking API; compliance check runs | Pass |
| SHD-011 (shader source policy) | No Metal source: clear pass + blit | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/053-med-009-text-overlay/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/text-layer.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/Compositor/
├── Package.swift                         # + target TextLayer (deps Compositor)
├── Sources/TextLayer/
│   ├── TextOverlaySpec.swift             # spec, enums, defaults, clamping, versioned JSON (plain Swift)
│   ├── TextSanitizer.swift               # control characters, grapheme and line limits (plain Swift)
│   ├── TextDirection.swift               # first strong letter → LTR/RTL; alignment side (plain Swift)
│   ├── TextLayout.swift                  # text area, pixel size, canvas rectangle (plain Swift)
│   ├── TextRendering.swift               # bitmap, ink bounds, checksum, half-float conversion (plain Swift)
│   ├── TextLayerKind.swift               # LayerKind.text
│   ├── TextRasterizer.swift              # CoreText → RGBA8 premultiplied sRGB (CoreText)
│   └── TextLayerSource.swift             # the CMP-001 layer: upload + clear + blit (Metal)
└── Tests/TextLayerTests/
    ├── TextSpecTests.swift               # sanitizer, limits, direction, codable, layout (Linux too)
    ├── TextRasterizerTests.swift         # determinism, Unicode fixtures, alignment side (CoreText)
    └── TextLayerSourceTests.swift        # through the real compositor, 64 × 64 readback (Metal)

Apps/projectM-iOS/
├── Coordinators/TextOverlayStore.swift, TextOverlayCoordinator.swift, AppCoordinator.swift, AppSettings.swift
├── Visuals/TextVisualHost.swift
├── Views/SettingsView.swift (+ text section), VisualizerView.swift (+ diagnostics label)
├── Debug/UITestTextFixture.swift         # DEBUG: -uitestSeedText
├── Tests/TextOverlayStoreTests.swift
└── UITests/TextOverlayUITests.swift
```

**Structure Decision**: a new `TextLayer` target in the Compositor package beside `ImageLayer` and
`VideoLayer`, with its own test target (`TextLayerTests`) so it does not touch the shared
`CompositorTests` target that PERF-004 edits in parallel. App files mirror MED-001's Photo files.

## Complexity Tracking

| Choice | Why | Simpler alternative rejected because |
|---|---|---|
| `TextVisualHost` repeats `PhotoVisualHost`'s frame loop | Keeps MED-001/MED-002's verified hosts untouched; the stack differs (spectrum under, text over) | A generic media host would change verified paths in a row that is not about them; PERF-004 is editing the hosts in parallel |
| CPU half-float conversion instead of an sRGB texture + shader | No new Metal source (SHD-011), and the layer picture is exactly the uploaded bytes (S5) | A sampling shader would need an allowlist entry and a review for a static picture |
