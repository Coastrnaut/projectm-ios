# Implementation Plan: UIX-011 Color Palette Picker

**Branch**: `feature/uix-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A pure palette model in SceneFormat (`ColorPalette`, `PaletteLibrary`, the `projectm-ios.palettes` file codec,
colour names and contrast, and the scene link accessors on `SceneDocument.extra` / `SceneLayer.extra`) with a
resolver (layer link → scene link → default). VisualGenerators' `VisualPalette` gains a `custom` case (stops +
blend style) so every native generator can draw a user palette. The app adds `PaletteStore` (the file in
`Application Support/Palettes`) and `PaletteCoordinator` (library edits, the scene's link, the missing notice),
records the link through `SceneInputs.palette` (SCN-002 autosave, SCN-010 undo), applies the effective palette
to the native visual (ACC-003 still wins), and a Settings › Palettes screen with an accessible swatch editor.
FILE-005 backs palettes up per palette, FILE-011 erases them with "Scenes and show", FILE-009 counts them
under Scenes.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; CI Xcode 26 type-check budget)
**Primary Dependencies**: SceneFormat (model, codec), VisualGenerators (rendering), LibraryBackup, SwiftUI (`ColorPicker`)
**Storage**: one JSON file `Application Support/Palettes/palettes.json` (format `projectm-ios.palettes`, version 1); scene links in SCN-001 documents; no UserDefaults key
**Testing**: XCTest — SceneFormatTests (model, codec, resolver), VisualGeneratorsTests (custom palette colours), LibraryBackupTests (backup/restore/erase), app unit tests (acceptance through the real store), one XCUITest
**Target Platform**: iOS 26+ / iPadOS 26+ (packages also on Linux)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: a palette edit reaches the generator on the next frame (colours recomputed only when the palette changes)
**Constraints**: no wall-clock assertions; unit tests ≤ 10 s, UI test < 30 s; SwiftUI bodies split into properties
**Scale/Scope**: ≤ 64 user palettes × ≤ 8 colours (file well under 16 KB)

## Constitution Check

- I Public Apple APIs only: SwiftUI `ColorPicker`, `UIColor`/`CGColor` sRGB conversion, Foundation file I/O. Pass.
- VI Modular boundaries: model and codec in SceneFormat (no files, Linux), rendering in VisualGenerators, file I/O and UI in the app. Pass.
- VII Real-time audio safety: no audio path touched; colours are recomputed on the main actor when a palette changes. Pass.
- Privacy/local-first: one local file; nothing sent; included in the user's own local backup only. Pass.
- Sensory safety (ACC-003, ACC-012): the colour-blind-safe switch overrides links; the flash limiter and intensity caps act on the rendered frame whatever the palette. Pass.
- X Evidence-based quality: per-rule unit tests, acceptance through the real store, one short UI test; no device claim. Pass.

Post-design re-check: unchanged, pass. No ADR: scene fields are optional additions (SCN-001-R10 rules), no default overridden.

## Project Structure

### Documentation (this feature)

```text
specs/225-uix-011-color-palette-picker/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/palettes.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/SceneFormat/Sources/SceneFormat/ScenePalettes.swift                 # new: model, library, codec, links, resolver
Packages/SceneFormat/Sources/SceneFormat/PaletteColorNames.swift             # new: colour names, contrast
Packages/SceneFormat/Tests/SceneFormatTests/ScenePalettesTests.swift         # new
Packages/VisualGenerators/Sources/VisualGenerators/VisualPalette.swift       # custom case
Packages/VisualGenerators/Tests/VisualGeneratorsTests/CustomPaletteTests.swift # new
Packages/LibraryBackup/Sources/LibraryBackup/*                               # palettes folder, record, plan section, install, erase
Packages/LibraryBackup/Tests/LibraryBackupTests/PaletteBackupTests.swift     # new
Apps/projectM-iOS/Coordinators/PaletteStore.swift                            # new: the file
Apps/projectM-iOS/Coordinators/PaletteCoordinator.swift                      # new: edits, scene link, notice, VisualPalette bridge
Apps/projectM-iOS/Views/PaletteViews.swift                                   # new: list, editor, swatch rows
Apps/projectM-iOS/Coordinators/{AppCoordinator,SceneAutosaveCapture,AppCoordinator+SceneHistory,StorageLocations}.swift  # small hooks
Apps/projectM-iOS/Views/SettingsView.swift                                   # one row
Apps/projectM-iOS/Tests/PaletteAppTests.swift                                # new: acceptance
Apps/projectM-iOS/UITests/PalettePickerUITests.swift                         # new
```

**Structure Decision**: no new package (SceneFormat already reaches LibraryBackup and the app, and is in the
`PKGS_VISUAL` CI group), so no workflow change.

## Complexity Tracking

None.
