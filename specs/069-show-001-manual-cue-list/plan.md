# Implementation Plan: SHOW-001 Manual Cue List

**Branch**: `feature/show-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/069-show-001-manual-cue-list/spec.md`

## Summary

A new package, `Packages/ShowControl`, holds the show: target `ShowControl` is the pure model
(`ShowCueList`: versioned Codable document, stable cue UUIDs, ordered cues referencing SCN-001 scene
IDs, a position of Standby or the active cue ID; add, remove, move, rename, next, previous, go to;
validation; no clock, no randomness), and target `ShowStorage` stores it in a folder (`show.json` plus
`Scenes/<sceneID>.scene.json` as canonical SCN-001 bytes; atomic writes; damaged files set aside;
unreferenced scenes removed). Both build and test on Linux. In the app, `ShowCoordinator`
(main actor) owns the list and the store, captures the shown look as a scene snapshot
(`ShowSceneSnapshot`: visual, spectrum and glow options, text, stored photo/video IDs → an SCN-001
document) and applies a cue's scene by validating it (`liveState`) and setting the same settings the
Settings screen sets, then the coordinator's existing `visualSettingsChanged()` and
`glowSettingsChanged()`: the audio source is never touched, the camera is never started, and the
OUT-010 cover keeps a blackout black. UI: a show row in the controls, keyboard shortcuts (arrows,
Page Up/Down) on the visualizer, an editor in Settings → Show. ADR-0031 (or the next free number at
commit time) records the show document and the scene reference rule.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: Foundation (Codable, UUID, FileManager); SceneFormat (scene decode, encode,
validate, live state) for `ShowStorage` and the app; app: SwiftUI, the existing `AppSettings`,
`TextOverlayCoordinator`, `PhotoCoordinator`, `VideoCoordinator`, `ExternalDisplayCoordinator`

**Storage**: `Application Support/Show/show.json` and `Application Support/Show/Scenes/*.scene.json`
(excluded from nothing: part of the user's normal backups like other app data); damaged files renamed
to `show.damaged-<n>.json` in the same folder

**Testing**: XCTest. `swift test --package-path Packages/ShowControl` on the Mac host and the Linux
shape; `xcodebuild test` of `projectM-iOSTests` (ShowCoordinator) and the UI test `ShowCueUITests` on
an iOS 27.2 simulator. Budgets (owner rule 7): unit ≤ 10 s each (target 1-2 s), suite < 1 min, UI
test < 30 s

**Target Platform**: iOS 26+ / macOS 15 package, Linux CI; app iOS 26+

**Project Type**: mobile app + SwiftPM package

**Performance Goals**: a step (decide + read one scene file + validate + apply settings) completes
on the main actor well inside one interaction; scene files are ≤ 1 MiB (SCN-001), typically < 4 KiB

**Constraints**: deterministic model (no time, no randomness, no dictionary-order dependence); no
networking; atomic writes; no main-actor mutation in test setUp/tearDown; no wall-clock assertions

**Scale/Scope**: ≤ 256 cues, labels ≤ 80 characters, show file ≤ 1 MiB

## Constitution Check

| Principle | Status |
|---|---|
| I. Public APIs only | Foundation, SwiftUI keyboard shortcuts, FileManager. No private API. |
| II-V. Capture | Untouched: a cue never starts, stops or labels an audio source (R8). |
| VI. Modular boundaries | The model and storage are a package with no UI or engine knowledge; the app maps scenes to its settings. |
| VII. Real-time audio safety | No audio-thread work; file I/O happens on the main actor on user action only, never in callbacks. |
| VIII, IX. Dependencies | No new third-party dependency. |
| X. Evidence | Unit tests for every rule (deterministic); simulator UI test for the app flow; no device claim. ADR for the new stored document. |
| Privacy | Local only; stores labels, scene settings and store IDs; FR-065's list is extended by this spec and the privacy policy gets a "Shows" paragraph. |

Gate: pass (no violation, no justification needed).

## Project Structure

### Documentation (this feature)

```text
specs/069-show-001-manual-cue-list/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/show-document.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
Packages/ShowControl/
├── Package.swift
├── Sources/ShowControl/        ShowCueList.swift, ShowCue.swift, ShowDocument.swift (Codable),
│                               ShowValidation.swift, ShowStep.swift
├── Sources/ShowStorage/        ShowStore.swift (folder, atomic writes, set-aside, scene files)
└── Tests/ShowControlTests/     acceptance (five cues), editing, validation table, property (seeded),
                                codec round trip, store round trip
Apps/projectM-iOS/
├── Coordinators/ShowCoordinator.swift      list + store + apply + notice
├── Coordinators/ShowSceneSnapshot.swift    look ↔ SCN-001 document (minimal; unify with SCN-002)
├── Views/ShowControls.swift                controls row + keyboard shortcut buttons
├── Views/ShowEditorView.swift              Settings → Show
├── Debug/UITestShowFixture.swift           DEBUG seed of a five-cue show
├── Tests/ShowCoordinatorTests.swift
└── UITests/ShowCueUITests.swift
docs/adr/0031-show-cue-list-document.md
```

Shared files touched minimally: `AppCoordinator.swift` (own a `ShowCoordinator`, seed, wire apply),
`ControlsOverlay.swift` (one row), `VisualizerView.swift` (shortcut buttons, notice, DEBUG probe),
`SettingsView.swift` (one navigation row), `project.yml` (package), `.github/workflows/ios-ci.yml`
(five package loops), `docs/privacy-policy.md`, `docs/adr/README.md`.

**Structure Decision**: a new package rather than `PerformanceControl`: the show model is a document
with storage and a SceneFormat dependency, while `PerformanceControl` is OSC and tempo with no scene
dependency; OSC-012 (cue sync) will depend on `ShowControl`, not the reverse.

## Complexity Tracking

None.
