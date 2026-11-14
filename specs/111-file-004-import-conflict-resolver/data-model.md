# Data Model: FILE-004 Import Conflict Resolver

## Presets (PresetLibrary), changes to FILE-003's model

| Type | Change |
|---|---|
| `PresetArchiveConflictPolicy` | adds `replace` (cases: keepBoth default, skip, replace) |
| `PresetArchiveImportPlan` | adds `overrides: [String: PresetArchiveConflictPolicy]` (incoming id → choice) and `replaceCount` (derived) |
| `PresetArchivePlanEntry` | adds `choice: PresetArchiveConflictPolicy?` (effective, nil when not a conflict), `replaces: PresetArchiveAction?` (the replaced preset's id and name), `fellBack: Bool` |
| `PresetArchiveAction` | adds `replacesID: String?` |
| `PresetArchiveText` | `installed(_:replaced:)` |

## Scenes (ShowStorage)

`ShowSceneImportChoice`: `skip`, `keepBoth` (default), `replace`.

`ShowSceneImportEntry`: incomingID, incomingName, contentSHA256, kind (`new`, `identical`,
`idConflict(existingName: String?, cueCount: Int)`), choice (effective, nil when not a conflict),
install (`ShowSceneImportAction`: sceneID, name, replaces: Bool, cueID: UUID?), fellBack.

`ShowSceneImportPlan`: libraryDigest (SHA-256 of the show file and every stored scene file),
defaultChoice, overrides, refusal (`ShowSceneImportRefusal`: `showUnreadable`, `tooManyCues`),
entries; derived counts and `canInstall`.

`ShowSceneImportOutcome`: `installed(ShowCueList, [SceneDocument])`, `changed(ShowSceneImportPlan)`,
`refused(String)`.

Journal (`scene-import.journal.json`): `version` 1, `phase` (`prepared` | `committed`), `added`
[scene id], `replaced` [scene id], `directoryExisted`, `scenesFolderExisted`, `show` (base64 of the
new show bytes; committed only).
