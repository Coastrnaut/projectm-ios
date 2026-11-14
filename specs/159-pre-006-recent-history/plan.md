# Implementation Plan: PRE-006 Recently Played History

**Branch**: `feature/pre-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/159-pre-006-recent-history/spec.md`

## Summary

A local list of recently shown preset IDs, beside the existing favorites, with an opt-out switch and a
Clear History control that touches nothing else.

Pure model (`Packages/PresetLibrary/Sources/PresetLibrary/RecentPresetHistory.swift`, new; Foundation
only, Linux-tested):

- `RecentPresetHistory`: ordered, de-duplicated IDs, capacity 50, `record`, `clear`, lenient
  `init(storedValue:)` (research PRE-006-D1, D2).
- `RecentPresetDwell`: the 3 s dwell state machine on the caller's monotonic clock (`shown`, `due`,
  `cancel`, `deadline`) (research D3).

App:

- `Coordinators/RecentPresetsStore.swift` (new): UserDefaults keys `recentPresets` and
  `settings.recentPresets.enabled`; turning off removes the history; an off switch read at launch
  removes any history (a restored switch) (research D4).
- `Coordinators/RecentPresetsCoordinator.swift` (new, `@Observable`): the store, the dwell, an injected
  clock and scheduler; `shown(_:)`, `checkDwell()`, `setEnabled(_:)`, `clear()`, `listing(in:)`,
  library-lane announcements.
- `PresetCoordinator`: one optional property `recent` and one line in `select` after a successful load.
- Views: `RecentPresetsView.swift` (new list, empty states, Clear History with confirmation),
  `RecentHistorySection.swift` (new Settings section: switch and Clear History); `PresetBrowserView`
  home row "Recently Played"; `SettingsView` (one property and one line in `tailSections`);
  `VisualizerView` (pass the coordinator to Settings).
- `AppCoordinator`: create the coordinator, wire the announcer, UI-test reset of both keys.

Backup and erase (`Packages/LibraryBackup`): `LibrarySettingsPolicy.recentPresetsKey` (excluded) and
`recentPresetsEnabledKey` (included, so erased with Settings); `LibraryErasePolicy.settingKeys(.collections)`
gains the history key; the category is renamed "Collections, tags, favorites and history"; the
inventory counts history entries (research D5).

Privacy: ADR (next free number) amending FR-065/FR-123 for the two keys; privacy policy section and
FR-063 coverage row; `scripts/run_device_tests.py` `ALLOWED_KEYS`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/recent-history.md](contracts/recent-history.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PresetLibrary, LibraryBackup. None new.

**Storage**: UserDefaults `recentPresets` ([String], ≤ 50) and `settings.recentPresets.enabled` (Bool,
absent = on).

**Testing**: XCTest. PresetLibrary (history and dwell rules), LibraryBackup (policy and erase), app unit
tests (`RecentPresetsAcceptanceTests`: clear acceptance, opt-out, dwell through `PresetCoordinator`,
relaunch, backup and erase policy), one UI test (`RecentPresetsUITests`, under 30 s) on simulator "PRE6".

**Target Platform**: iOS 26+ (app), macOS 15 and Linux (packages).

**Performance Goals**: O(50) per record; no wall-clock assertions (injected clock).

**Constraints**: Linux build of PresetLibrary and LibraryBackup; type-check budget; short tests; small
edits in shared files (`AppCoordinator`, `SettingsView`, `VisualizerView`).

**Scale/Scope**: 50 IDs.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI and Foundation only; no networking. |
| VI. Modular boundaries | Pass: rules in PresetLibrary (Linux-tested); policy in LibraryBackup; the app wires and draws. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: automated tests; simulator results are not device evidence; no device claim. |
| Privacy constraints | Pass with an ADR: no audio; preset IDs only, no times; local; opt-out that clears; never backed up; FR-065/FR-123 amended explicitly and the privacy policy updated. |

Post-design re-check: unchanged.

## Project Structure

```text
specs/159-pre-006-recent-history/  spec, plan, research, data-model, contracts/recent-history.md, quickstart, tasks
docs/adr/00NN-recently-played-history.md                                (new)
docs/privacy-policy.md                                                  (stored data, coverage row)
Packages/PresetLibrary/Sources/PresetLibrary/RecentPresetHistory.swift  (new)
Packages/PresetLibrary/Tests/PresetLibraryTests/RecentPresetHistoryTests.swift (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift, LibraryEraseInventory.swift
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryEraseAcceptanceTests.swift, LibraryBackupPresetTagTests.swift (title)
Apps/projectM-iOS/Coordinators/RecentPresetsStore.swift, RecentPresetsCoordinator.swift (new)
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift, AppCoordinator.swift (small)
Apps/projectM-iOS/Views/RecentPresetsView.swift, RecentHistorySection.swift (new)
Apps/projectM-iOS/Views/PresetBrowserView.swift, SettingsView.swift, VisualizerView.swift (small)
Apps/projectM-iOS/Tests/RecentPresetsAcceptanceTests.swift (new); LibraryBackupAppTests, LibraryEraseAppTests (keys)
Apps/projectM-iOS/UITests/RecentPresetsUITests.swift (new)
scripts/run_device_tests.py (ALLOWED_KEYS), scripts/check_status_events.py (register new files)
```

## Complexity Tracking

None.
