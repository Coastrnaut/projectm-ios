# Implementation Plan: SHOW-015 Performance Lock

**Branch**: `feature/show-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

No new state. The SCN-015 `SceneLock` (`settings.scene.locked`) is the performance lock (research SHOW-015-D1). Its
`refusesEdit()` choke point gains three consumers and the screens that still offer destructive gestures hide them:

1. `PresetCoordinator` gets `sceneLock: SceneLock?` (wired in `AppCoordinator.connectSceneLock()`); `deleteCollection`,
   `deleteSmartCollection`, `moveCollections` (and so `moveCollection`), `movePresets` (and so `movePreset`) and
   `removeFromCollection` call `refusedByLock()` first, which sets `collectionsMessage` to the lock's message.
   `isCollectionEditLocked` drives the views.
2. `LibraryBackupCoordinator` gets `sceneLock: SceneLock?`; `restoreTapped()` and `requestRestore()` refuse (message
   and announcement through the lock); `isRestoreLocked` disables the button. `LibraryEraseCoordinator` gets
   `isLocked: () -> Bool` and `refusesEdit: () -> Bool` closures (set by `LibraryBackupCoordinator`); `canStart` is false
   while locked and `openSheet()`/`requestErase()` refuse. Cancel of a pending request is untouched.
3. Views: `PresetCollectionsView`, `PresetCollectionView`, `SmartCollectionsSection` and `PresetRow`'s collection
   actions hide Delete/Remove swipe actions, Move Up/Down and Delete menu items, VoiceOver actions and the Edit button
   while locked, and show `SceneLockNote`. `SceneFoldersView` hides folder Rename/Move/Delete and scene Move/Tags while
   locked, disables New Folder and shows the note. The Storage sections show the note beside the disabled buttons.
4. Copy: `SceneLock.unlockMessage` and the Settings footer name collections, erase and restore.

Emergency controls (blackout, Go/Next/Previous, Reduce flashing, unlock) are untouched and only gain tests.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SwiftUI, Observation; existing coordinators (`SceneLock`, `ShowCoordinator`, `PresetCoordinator`, `LibraryBackupCoordinator`, `LibraryEraseCoordinator`, `OutputBlackout` via `AppCoordinator`)
**Storage**: none new (`settings.scene.locked` exists, already in every key list)
**Testing**: XCTest app unit tests (`PerformanceLockAcceptanceTests`), one UI test under 30 s (`PerformanceLockUITests`) on simulator "SHOW15 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Performance Goals**: n/a (a Boolean check per gesture)
**Constraints**: owner rule 7 budgets; Xcode 26 type-check budget (small view bodies); small edits in shared files (AppCoordinator+SceneLock only)
**Scale/Scope**: size S; ~8 source files touched

## Constitution Check

- I (public APIs only): SwiftUI only. Pass.
- Privacy and local-first: no new data, no network. Pass.
- VI (modular boundaries): the policy stays one model; each coordinator keeps its own writes and refuses at the write. Pass.
- Accessibility (FR-070, ACC-004): the hidden gestures include their VoiceOver actions; the note is a visible label; refusals announce through the existing lane. Pass.
- X (evidence): simulator tests prove behavior only; the device check is a `{device}` task.

Post-design re-check: unchanged, pass.

## Project Structure

```text
specs/260-show-015-performance-lock/   spec, plan, research, data-model, contracts/performance-lock.md, quickstart, tasks
Apps/projectM-iOS/Coordinators/
  AppCoordinator+SceneLock.swift        wire presets + libraryBackup to the lock
  PresetCoordinator.swift               refusals in delete/move/remove
  PresetCoordinator+Smart.swift         refusal in deleteSmartCollection
  LibraryBackupCoordinator.swift        restore refusal, erase closures
  LibraryEraseCoordinator.swift         canStart/openSheet/requestErase refusal
Apps/projectM-iOS/Views/
  PresetCollectionsView.swift, PresetCollectionView.swift, SmartCollectionViews.swift, PresetBrowserView.swift (PresetRow)
  SceneFoldersView.swift, LibraryBackupSection.swift, LibraryEraseSection.swift, SceneLockViews.swift (copy)
Apps/projectM-iOS/Tests/PerformanceLockAcceptanceTests.swift
Apps/projectM-iOS/UITests/PerformanceLockUITests.swift
```

**Structure Decision**: app-only change; no package touched (Linux CI unaffected).

## Complexity Tracking

None.
