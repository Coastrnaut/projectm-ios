# Implementation Plan: SCN-015 Scene Lock Mode

**Branch**: `feature/scn-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

One small main-actor model, `SceneLock` (`settings.scene.locked`, default off), owned by `AppSettings` so every
place that already holds the settings (Settings, the inspector, the shelf, macros, snapshots) sees the same
lock. Its `refusesEdit()` is the single choke point (research SCN-015-D1): it returns true while locked, records
the refusal message and announces it. Every coordinator API that writes the scene calls it first:
`ParameterInspectorTargets` (every Settings-target write: inspector, shelf, snapshots recall, macros' targets),
`MacroCoordinator.setValue`, `SceneSnapshotCoordinator` save/rename/delete/recall, `ShowCoordinator`'s edit
methods (cues, scene names, transitions, templates, pack import, folders, tags) and
`SceneHistoryCoordinator.undo/redo` (and `canUndo/canRedo` read false). Navigation paths (`next`,
`previous`, `go`, the cue apply path, blackout, tempo, presets, MIDI/OSC live values) never call it.

UI: a Lock button in the controls (`lockScene`), a Scene lock section at the top of Settings, a "Scene locked"
badge in the visualizer's top status stack, disabled scene-editing Settings sections and shelf strip, and the
show editor without Edit, add, swipe-to-delete, drag reorder or edit menu items. Unlock asks for confirmation.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SwiftUI, Observation; app coordinators listed above; `AccessibilityAnnouncer` (library lane)
**Storage**: one UserDefaults Boolean `settings.scene.locked`
**Testing**: XCTest app unit tests (acceptance, persistence) and one UI test under 30 s on simulator "SCN15 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Constraints**: no scene format change; no networking; owner rule 7 budgets; Xcode 26 type-check budget; small edits in shared files (AppCoordinator, SettingsView, VisualizerView)

## Constitution Check

- I (public APIs only): SwiftUI and UserDefaults only. Pass.
- Privacy and local-first: one local Boolean; excluded from backups; no network. Pass.
- VI (modular boundaries): the policy is one model; coordinators keep their own writes. Pass.
- Accessibility (FR-070, ACC-004): VoiceOver labels, values and actions; announcements on the library lane. Pass.
- X (evidence): simulator tests prove behavior only; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Apps/projectM-iOS/Coordinators/SceneLock.swift                 # new: the lock model and choke point
Apps/projectM-iOS/Coordinators/AppSettings.swift               # owns `sceneLock`; key in allKeys
Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift   # targets refuse while locked
Apps/projectM-iOS/Coordinators/MacroCoordinator.swift          # setValue refuses
Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift  # save/rename/delete/recall refuse
Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSnapshots.swift  # wires the lock
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift (+Templates) # edit methods refuse
Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift   # undo/redo refuse
Apps/projectM-iOS/Coordinators/AppCoordinator.swift            # wire lock into show and history; announcer
Apps/projectM-iOS/Views/SceneLockViews.swift                   # new: badge, Settings section, unlock confirmation
Apps/projectM-iOS/Views/ControlsOverlay.swift                  # lock button; shelf strip disabled
Apps/projectM-iOS/Views/SettingsView.swift                     # section; scene sections disabled
Apps/projectM-iOS/Views/ShowEditorView.swift                   # gestures and menu items gated
Apps/projectM-iOS/Views/VisualizerView.swift                   # badge (one line)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  # excludedKeys
scripts/run_device_tests.py                                    # ALLOWED_KEYS
Apps/projectM-iOS/Tests/SceneLockAcceptanceTests.swift         # new
Apps/projectM-iOS/UITests/SceneLockUITests.swift               # new
```

## Complexity Tracking

None.
