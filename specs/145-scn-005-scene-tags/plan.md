# Implementation Plan: SCN-005 Scene Tags

**Branch**: `feature/scn-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/145-scn-005-scene-tags/spec.md`

## Summary

Tags follow SCN-004's pattern: they live in the show's index (`show.json`) beside the cues and folders,
keyed by scene ID, as one optional key `sceneTags`. Scene files never change.

Pure model (`Packages/ShowControl/Sources/ShowControl/`, Foundation only, Linux-tested):

- `SceneTags.swift` (new): `SceneTagMap` (scene ID → sorted tags) with `normalizedTag`, `fold`
  (SCN-004's folding), `add`, `remove`, `setTags`, `tags(ofScene:)`, the derived `vocabulary`,
  `matches(sceneID:all:)` (AND), `prune(keepingScenes:)`, `repaired(_:sceneIDs:)` and
  `SceneTagError`. Limits: 16 per scene, 256 distinct, 1-40 characters. Research SCN-005-D1 to D3.
- `ShowCueList`: a `tags` map plus `addTag`, `removeTag`, `copyTags` that check the scene is in the
  show.
- `ShowDocument.swift`: optional `sceneTags` (object scene ID → array of strings), written only when
  non-empty after pruning to the show's scenes, so a show without tags keeps its bytes. Decoding
  repairs damaged entries and reports `ShowDecodeWarning.droppedTags(n)`. Format version stays 1.
  Research SCN-005-D4.

Storage, backup and import: no change. FILE-005 and FILE-004 decode and re-encode through the model
(research SCN-005-D5), as for folders.

App:

- `ShowCoordinator`: `tags(ofScene:)`, `tagVocabulary`, `addTag`, `removeTag` (save, announce on the
  library lane, refusals as editor message plus announcement); Duplicate Scene copies tags.
- `SceneTagsView.swift` (new): the Tags sheet for one scene: current tags with Remove (button and
  VoiceOver action), a field with Add (Return adds), suggestions (the vocabulary minus the scene's
  tags, filtered by the field's text), Done.
- `SceneFoldersView`: scene rows show tags; "Tags…" swipe action, context menu and VoiceOver action.
- UIX-002: `SceneSwitcherEntry` gains `tags`; `SceneSwitcherFilter.results(_:query:tags:)` applies
  the selected tags (AND, folded) and matches the query against tags (non-early group);
  `SceneSwitcherModel` gains `selectedTags` (in memory) and `toggleTag`; `SceneSwitcherView` shows a
  chip row (horizontal scroll) and a tag button after each row that opens the Tags sheet;
  `AppCoordinator+SceneSwitcher` gains `toggleSwitcherTag` (re-highlight, count announcement).
- `scripts/check_status_events.py`: register `Views/SceneTagsView.swift`.
- No new settings keys, no networking.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/scene-tags.md](contracts/scene-tags.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: ShowControl (model, storage), LibraryBackup (round trip test only). None new.

**Storage**: `Application Support/Show/show.json` (one optional key; version 1).

**Testing**: XCTest. ShowControl package tests on host and Linux (tag rules, document round trip,
legacy bytes, damaged data, store reload); LibraryBackup round trip; app unit tests
(`SceneTagAcceptanceTests`, switcher filter); one UI test (`SceneTagsUITests`, under 30 s) on the
feature's own simulator "SCN5".

**Target Platform**: iOS 26+ (app), macOS 15 and Linux (packages).

**Performance Goals**: filtering is O(cues × tags) on at most 256 cues × 16 tags; no measurable cost.
No wall-clock assertions.

**Constraints**: Linux build of ShowControl; type-check budget; short tests (owner rule 7).

**Scale/Scope**: one new model file, one new view file; edits to ShowCueList, ShowDocument,
ShowCoordinator, SceneFoldersView, SceneSwitcher(View), AppCoordinator+SceneSwitcher.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI and Foundation only; no networking. |
| VI. Modular boundaries | Pass: model and file format in ShowControl (Linux-tested); the app wires and draws. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: automated tests; simulator results are not device evidence; no device claim. |
| Privacy constraints | Pass: local show folder only; no new UserDefaults keys; tags are user content and never logged. |

Post-design re-check: unchanged.

## Project Structure

```text
specs/145-scn-005-scene-tags/  spec, plan, research, data-model, contracts/scene-tags.md, quickstart, tasks
Packages/ShowControl/Sources/ShowControl/SceneTags.swift              (new)
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift            (tags property + operations)
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift           (optional key, repair)
Packages/ShowControl/Tests/ShowControlTests/SceneTagMapTests.swift     (new)
Packages/ShowControl/Tests/ShowControlTests/ShowTagDocumentTests.swift (new)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupSceneTagTests.swift (new)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                  (tag operations)
Apps/projectM-iOS/Coordinators/SceneSwitcher.swift                    (tags, filter, selection)
Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSwitcher.swift     (toggle)
Apps/projectM-iOS/Views/SceneTagsView.swift                           (new)
Apps/projectM-iOS/Views/SceneFoldersView.swift                        (tags on rows, Tags… action)
Apps/projectM-iOS/Views/SceneSwitcherView.swift                       (chips, tag button)
Apps/projectM-iOS/Tests/SceneTagAcceptanceTests.swift                 (new)
Apps/projectM-iOS/UITests/SceneTagsUITests.swift                      (new)
scripts/check_status_events.py                                        (register the new view)
```

## Complexity Tracking

None.
