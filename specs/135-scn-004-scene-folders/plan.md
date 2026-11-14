# Implementation Plan: SCN-004 Scene Folder Organization

**Branch**: `feature/scn-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/135-scn-004-scene-folders/spec.md`

## Summary

Folders are logical and live in the show's index (`show.json`), beside the cues that already refer
to scenes by scene ID. Scene files never move or change, so every reference (cues, the stored
position, the switcher, archives, imports, backups) stays valid by construction.

Pure model (`Packages/ShowControl/Sources/ShowControl/`, Foundation only, Linux-tested):

- `SceneFolders.swift`: `SceneFolder` (id, name, parentID), `SceneFolderTree` (folders by ID plus
  scene-ID → folder-ID assignments) with create, rename, move folder, move scene, delete (contents
  to the parent, colliding names suffixed " 2", " 3"…), queries (children, scenes in a folder, path,
  depth) and `SceneFolderError`. Limits: 256 folders, depth 5, names 1-80 characters, unique among
  siblings by a folded comparison (case, accents, width; `nil` locale). Research SCN-004-D1, D2.
- `ShowCueList`: a `folders` tree plus forwarding operations that check the scene is in the show;
  duplicate placement is the caller's (`moveScene` after insert).
- `ShowDocument.swift`: two optional keys, `folders` (array of `{id, name, parent}`, written parents
  first) and `sceneFolders` (object scene ID → folder ID), written only when non-empty, so a show
  without folders encodes to the same bytes as today. Decoding repairs damaged folder data and
  reports `ShowDecodeWarning.droppedFolders(n)` / `.droppedFolderAssignments(n)`; the show is never
  refused for folder data. Format version stays 1. Research SCN-004-D3, D4.

Storage: no new file. `ShowStore.save` already writes the whole index atomically; FILE-005 and
FILE-004 decode and re-encode the show through the model, so backup, exact restore, merge restore
and import keep the folders without changes (research SCN-004-D5).

App:

- `ShowCoordinator`: folder operations that mutate `list`, save, and announce through an injected
  `announceLibrary` closure (wired by AppCoordinator to the shared announcer's `.library` lane);
  `folderPath(ofScene:)`, `firstCue(ofScene:)`, `goToScene(_:)`; Duplicate Scene puts the copy in
  its source's folder.
- `SceneFoldersView` (new, `Views/`): one level of the tree (folders, then scenes, sorted by name),
  NavigationLink drill-down, "New Folder", per-row swipe actions, context menus and VoiceOver
  actions; "Move to…" sheet (`SceneFolderPicker`) with Top Level and the indented tree, refused
  destinations disabled; delete confirmation for non-empty folders. Reached from a row in
  `ShowEditorView` (no `SettingsView` edit).
- UIX-002: `SceneSwitcherEntry` gains `folderPath` (computed from the list's tree in `entries`), the
  row subtitle and VoiceOver value show it, and the filter also matches it (non-early group).
- No new settings keys, no networking.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/scene-folders.md](contracts/scene-folders.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: ShowControl (model, storage), SceneFormat (scene documents), LibraryBackup
(backup round trip test only). No new dependency.

**Storage**: `Application Support/Show/show.json` (optional fields added; version 1).

**Testing**: XCTest. ShowControl package tests on host and Linux (folder tree, document round trip,
legacy fixture, damaged data, store reload); LibraryBackup round trip; app unit tests
(`SceneFolderAcceptanceTests`, switcher); one UI test (`SceneFoldersUITests`, under 30 s) on the
feature's own simulator "SCN4".

**Target Platform**: iOS 26+ (app), macOS 15 and Linux (packages).

**Performance Goals**: folder operations are O(folders + scenes) on at most 256 folders and 256 cues;
no measurable cost. No wall-clock assertions.

**Constraints**: Linux build of ShowControl (Foundation only); type-check budget (bodies < 300 ms,
expressions < 200 ms); short tests (owner rule 7).

**Scale/Scope**: one new model file, one new view file, edits to ShowCueList, ShowDocument,
ShowCoordinator, ShowEditorView, SceneSwitcher(View).

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI and Foundation only; no networking. |
| VI. Modular boundaries | Pass: the model and its file format are in the ShowControl package (Linux-tested); the app only wires and draws. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: acceptance proven by automated tests; simulator results are not device evidence and no device claim is made. |
| Privacy constraints | Pass: data stays in the app's local show folder; no new UserDefaults keys; folder names are user content and never logged (events carry counts only). |

Post-design re-check: unchanged (no violations, no complexity entries).

## Project Structure

```text
specs/135-scn-004-scene-folders/  spec, plan, research, data-model, contracts/scene-folders.md, quickstart, tasks
Packages/ShowControl/Sources/ShowControl/SceneFolders.swift          (new)
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift           (folders property + operations)
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift          (optional keys, repair)
Packages/ShowControl/Tests/ShowControlTests/SceneFolderTreeTests.swift      (new)
Packages/ShowControl/Tests/ShowControlTests/ShowFolderDocumentTests.swift   (new)
Packages/LibraryBackup/Tests/LibraryBackupTests/<backup round trip with folders> (new test)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                 (folder operations)
Apps/projectM-iOS/Coordinators/SceneSwitcher.swift                   (folder path)
Apps/projectM-iOS/Views/SceneFoldersView.swift                       (new)
Apps/projectM-iOS/Views/ShowEditorView.swift                         (link row)
Apps/projectM-iOS/Views/SceneSwitcherView.swift                      (subtitle)
Apps/projectM-iOS/Tests/SceneFolderAcceptanceTests.swift             (new)
Apps/projectM-iOS/UITests/SceneFoldersUITests.swift                  (new)
```

## Complexity Tracking

None.
