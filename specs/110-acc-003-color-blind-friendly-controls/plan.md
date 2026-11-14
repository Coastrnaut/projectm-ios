# Implementation Plan: ACC-003 Color-blind Friendly Controls

**Branch**: `feature/acc-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Give every critical status a non-colour cue and the interface a high-contrast palette. A pure catalog
(`StatusCueCatalog`) maps each status state to a symbol, its words and a colour role; one small view
(`StatusCueSymbol`) draws the symbol, and the existing indicators and badges use it. The app gets an
asset-catalog accent (darker than systemBlue in light mode, Apple's high-contrast blues with Increase
Contrast) and an `InterfacePalette` of status colours checked by unit tests for 4.5:1 / 7:1. With
Increase Contrast, the visualizer's badges get an opaque, bordered background; Differentiate Without
Colour adds "Starting"/"Live" to the camera badge. The visualization ignores Smart Invert. A grayscale
snapshot test renders every status group with `ImageRenderer`, converts to luminance and checks each
pair. ACC-004's "Add Current Scene" contrast filter is removed. The native spectra gain an opt-in
cividis-derived palette.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), SwiftUI, iOS 26+ deployment
**Primary Dependencies**: SwiftUI environment (`colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`),
`ImageRenderer`, Core Graphics (8-bit DeviceGray context), UIKit `UITraitCollection`/`traitOverrides`
(iOS 17+, public), existing modules CaptureUI, VisualGenerators
**Storage**: UserDefaults, one Bool key `settings.visual.colorBlindSafePalette` (absent → off)
**Testing**: XCTest in `projectM-iOSTests` (host app on the simulator: catalog, palette ratios, asset
accent, grayscale renderings); CaptureUI package tests (state symbols); VisualGenerators package tests
(the palette); XCUITest `ColorBlindControlsUITests` with DEBUG launch arguments; ACC-004's
`AccessibilityScreensUITests` without the filter
**Target Platform**: iPhone and iPad
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no per-frame work added; the palette is computed once per configuration change
**Constraints**: no change to VoiceOver labels, values, identifiers or contract texts; small SwiftUI
bodies (CI's Xcode 26 type-checker); no animation, no announcement
**Scale/Scope**: ~6 status groups drawn by the catalog, 4 colour roles, ~9 source files touched, 4 test files

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI environment values, `UIWindowScene.traitOverrides`, `ImageRenderer`, Core Graphics | Pass |
| IV Truthful labeling | Source words unchanged; symbols only add shape | Pass |
| VI Modular boundaries | State symbols live in CaptureUI next to the state words; the palette ramp lives in VisualGenerators; the app catalog only composes | Pass |
| VII Real-time safety | No audio path change; palette colours are precomputed by the generators | Pass |
| VIII Upstream fidelity | projectM presets are never recoloured | Pass |
| X Evidence | Unit and UI tests on the simulator; the colour filters and Increase Contrast on D1 are a `{device}` task | Pass |
| Privacy | One on-device Bool key, in `ALLOWED_KEYS`; nothing sent | Pass |
| Accessibility (ACC-001/004/006/011) | No animation; symbols scale with text and are hidden from VoiceOver; no announcement | Pass |

Post-design re-check: unchanged, Pass. No ADR: no constitution default is overridden (the accent is a
design choice recorded in research D2).

## Project Structure

```text
specs/110-acc-003-color-blind-friendly-controls/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/status-cues.md
└── checklists/requirements.md

Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift        (stateSymbol, switchingSymbol)
Packages/CaptureUI/Sources/CaptureUI/StatusBanner.swift     (symbol; words in the primary colour)
Packages/CaptureUI/Tests/CaptureUITests/                    (distinct state symbols)
Packages/VisualGenerators/Sources/VisualGenerators/VisualPalette.swift   (case colorBlindSafe)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/      (monotonic luminance, first bar ≥ 3:1)

Apps/projectM-iOS/
├── Views/StatusCues.swift              (new: catalog, colour roles, InterfacePalette, appearance, symbol view, badge background)
├── Views/SourceStatusIndicator.swift   (symbol; badge background)
├── Views/CameraIndicator.swift         (starting/live symbols; DWC words)
├── Views/OSCListenerBadge.swift        (badge background)
├── Views/VisualizerView.swift          (recording and blackout symbols, badge background, Smart Invert)
├── Views/SettingsView.swift            (palette toggle section, small)
├── Coordinators/AppSettings.swift      (palette key)
├── Visuals/NativeSpectrumHost.swift    (applies the palette)
├── Coordinators/AppCoordinator.swift   (passes the palette; DEBUG contrast trait override)
├── ProjectMApp.swift                   (status appearance at the root; DEBUG probe)
├── Resources/Assets.xcassets/AccentColor.colorset   (new)
├── Tests/ColorBlindControlsTests.swift (new: catalog, palette ratios, accent, grayscale table)
└── UITests/ColorBlindControlsUITests.swift (new)
project.yml                             (ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME)
scripts/run_device_tests.py             (ALLOWED_KEYS)
Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift (filter removed)
specs/082-acc-004-voiceover-scene-browser/contracts/accessibility-tree.md (filter row updated)
```

## Complexity Tracking

None.
