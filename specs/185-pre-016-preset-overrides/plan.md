# Implementation Plan: PRE-016 Preset parameter overrides

**Branch**: `feature/pre-016` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Per-preset overrides of eight initial values (zoom, rot, warp, fDecay, wave_r/g/b, fGammaAdj) are
stored as overlay data in `PresetCollections/overrides.json` and applied by a **text overlay** just
before the bytes reach the engine (research PRE-016-D1). No engine change, no preset file is written.
The overlay model, document and store live in the `PresetLibrary` package (Linux-testable); FILE-005
backup/restore and FILE-011 erase count follow PRE-003's tags pattern in `LibraryBackup`; the app
adds a small coordinator, a sheet with `.accessibleParameter` sliders, a menu item, and one hook in
`RendererPresetLoader.load`.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / Swift 6.4.2; CI also Xcode 26)
**Primary Dependencies**: Foundation; LocalPortability (FILE-007 `DocumentSchema`); SwiftUI in the app
**Storage**: one JSON document, `Application Support/PresetCollections/overrides.json`, atomic writes
**Testing**: XCTest — `swift test --package-path Packages/PresetLibrary` and `Packages/LibraryBackup`
(host, Linux-clean), app unit tests and one XCUITest on simulator "PRE16 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: overlay of a 512 KiB preset well under 5 ms (one linear byte pass); no change
for presets without overrides
**Constraints**: type-check budget (300 ms bodies / 150 ms expressions), unit tests ≤ 10 s, UI test < 30 s
**Scale/Scope**: up to 20,000 presets with overrides, 8 parameters each, file ≤ 1 MiB

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass — Foundation/SwiftUI only. |
| VI Modular boundaries | Pass — logic in `PresetLibrary`/`LibraryBackup`, app only wires and shows. |
| VII Real-time audio safety | Pass — nothing on the audio path; overlay runs in the load path on the main actor before `setPreset`. |
| VIII Upstream ProjectM fidelity | Pass — no engine patch; uses the documented file format and `loadPresetData`. |
| IX Untrusted input | Pass — the document is bounded and schema-checked; values clamped; names allow-listed. User presets keep PRE-012's guarded path (the overlay changes only header numbers). |
| X Evidence | Unit + acceptance tests in packages; app UI test on simulator (not device evidence; no device claim made). |
| Privacy | Pass — local file, no network, no new UserDefaults key. |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/185-pre-016-preset-overrides/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/preset-overrides.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/PresetLibrary/Sources/PresetLibrary/Overrides/
├── PresetOverrideParameter.swift   # allow-list, ranges, defaults, clamping/rounding
├── PresetOverrideMap.swift         # preset ID → [name: value], validation, Equatable
├── PresetOverridesFile.swift       # versioned document (FILE-007 schema), lenient read
├── PresetOverrideStore.swift       # load/save transactions, newer/unreadable handling
└── PresetTextOverlay.swift         # read original values; apply overlay to bytes
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetOverride*Tests.swift
Packages/LibraryBackup/Sources/LibraryBackup/  (Contents, Archive, Records, RestorePlan, Installer,
                                                EraseInventory, Folders, Format: overrides record)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetOverrideTests.swift
Apps/projectM-iOS/Coordinators/PresetOverridesCoordinator.swift
Apps/projectM-iOS/Views/PresetOverridesView.swift
Apps/projectM-iOS/Coordinators/AppCoordinator.swift      # loader hook + construction (small)
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift   # one property
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift  # prune on remove
Apps/projectM-iOS/Views/PresetBrowserView.swift          # menu item + sheet
Apps/projectM-iOS/Tests/PresetOverridesAcceptanceTests.swift
Apps/projectM-iOS/UITests/PresetOverridesUITests.swift
```

**Structure Decision**: follow PRE-003 (tags) exactly for storage, backup and erase, so the four
features that share `PresetCollections/` behave alike.

## Complexity Tracking

None.
