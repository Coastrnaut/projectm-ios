# Implementation Plan: SCN-003 Scene Duplicate and Rename

**Branch**: `feature/scn-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/074-scn-003-scene-duplicate-and-rename/spec.md`

## Summary

Three layers, each small:

1. **SceneFormat** (pure, Linux): `SceneDocument.normalizedName(_:)` (trim, then the SCN-001 name
   rule), `copyName(_:)` ("<name> copy", shortened to 120 characters), `renamed(to:)` and
   `duplicated(newID:name:)`, both `throws(SceneEditError)` and returning a value that differs from
   the original only in `name` (and `id` for a duplicate). The validator's name check reuses
   `isValidName(_:)` so there is one rule.
2. **ShowControl** (pure, Linux): `ShowCueList.insert(sceneID:label:after:cueID:)` puts a cue right
   after another (position unchanged), and `copyLabel(_:)`. **ShowStorage**: `duplicateScene(_:newID:name:)`
   (read → `duplicated` → atomic write of the new file; never touches the original file),
   `renameScene(_:to:)` (read → `renamed` → atomic rewrite of the same file), and
   `referencedMediaIDs()` (every photo and video store ID named by any stored scene, read from the
   files each time).
3. **App**: `ShowCoordinator.duplicateScene(of:)` (store the copy, insert its cue, save the show) and
   `renameScene(of:to:)`, plus a scene-name cache for the editor. `ShowEditorView`: Duplicate Scene and
   Rename Scene… in each cue's context menu and as VoiceOver actions; a "Scene: <name>" caption and
   VoiceOver value when the scene name differs from the label. Nothing is applied and the position
   does not move (SHOW-001-R6).

ADR-0028 (scene document) and ADR-0033 (show) are amended; no new ADR (no default is overridden).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: SceneFormat (existing codec and validator), ShowControl/ShowStorage
(existing), Foundation; app: SwiftUI. ShowControl's test target gains ParameterGraph (already a
SceneFormat dependency) to build a registry for `liveState` in the acceptance test.

**Storage**: unchanged layout: `Application Support/Show/Scenes/<ID>.scene.json` (canonical SCN-001
bytes) and `show.json`; every write `.atomic`; the copy's scene file is written before the show that
refers to it.

**Testing**: XCTest. `swift test --package-path Packages/SceneFormat` and `Packages/ShowControl` on
the host and the Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE`); `xcodebuild test` of `projectM-iOSTests`, `ShowCueUITests` and the new
`SceneDuplicateUITests` on an own iOS 27.2 simulator. Budgets (owner rule 7): unit ≤ 10 s (target
1-2 s), suite < 1 min, UI test < 30 s, property test ≤ 1 s.

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI; app iOS 26+

**Project Type**: mobile app + SwiftPM packages

**Performance Goals**: a duplicate or rename reads and writes one scene file (≤ 1 MiB, typically a few
KB) on user action; the editor's name cache decodes each stored scene once at launch (≤ 256).

**Constraints**: no networking; atomic writes; deterministic model (IDs injected by tests); no
main-actor mutation in setUp/tearDown; no wall-clock assertions.

**Scale/Scope**: ≤ 256 cues; names ≤ 120 characters; labels ≤ 80.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public APIs only | Foundation, SwiftUI context menus and alerts. |
| II-V. Capture | Untouched: duplicate and rename never apply a scene or touch the audio source. |
| VI. Modular boundaries | The rules live in the packages (Linux-tested); the app only wires buttons. |
| VII. Real-time audio safety | No audio-thread work; file I/O on the main actor on user action. |
| VIII, IX. Dependencies | No new third-party dependency; one in-repo package edge for tests. |
| X. Evidence | Unit, property and acceptance tests; a simulator UI test; no device claim. |
| Privacy | Local only; stores scene names and copies the user made; no new data kind (FR-065 unchanged). |

Gate: pass. Re-checked after design: pass.

## Project Structure

### Documentation (this feature)

```text
specs/074-scn-003-scene-duplicate-and-rename/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/scene-duplicate-rename.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
Packages/SceneFormat/Sources/SceneFormat/SceneEditing.swift        (new) name rule, rename, duplicate
Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift     name check reuses isValidName
Packages/SceneFormat/Tests/SceneFormatTests/SceneEditingTests.swift (new) table, acceptance, property
Packages/ShowControl/Package.swift                                  test dependency on ParameterGraph
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift          insert(after:), copyLabel
Packages/ShowControl/Sources/ShowStorage/ShowStore.swift            duplicateScene, renameScene, referencedMediaIDs
Packages/ShowControl/Tests/ShowControlTests/ShowSceneEditTests.swift (new) acceptance, references, media
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                duplicateScene(of:), renameScene(of:to:), names
Apps/projectM-iOS/Views/ShowEditorView.swift                        menu items, alert, caption
Apps/projectM-iOS/Tests/ShowSceneEditCoordinatorTests.swift          (new) coordinator cases
Apps/projectM-iOS/UITests/SceneDuplicateUITests.swift               (new) UI test with -uitestShowSeed
docs/adr/0028-scene-document-format.md, docs/adr/0033-show-cue-list-document.md   amendments
```

**Structure Decision**: no new package; the scene-level rule belongs to SceneFormat (the library rows
reuse it), the show-level actions to ShowStorage and the app's show editor.

## Complexity Tracking

None.
