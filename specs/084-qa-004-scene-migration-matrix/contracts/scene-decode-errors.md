# Contract: the documented scene decode errors (QA-004-R6)

Every reason a stored scene is refused, in one table. The data copy is `errors` and
`migrationErrors` in `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json`;
`SceneMigrationMatrixMetaTests` fails when a `SceneDecodeError` or `SceneMigrationError` case in
code has no row here and in the data, or when a row's report group or "if opened" text differs from
what `SceneRepairReport(refusal:)` builds. Linked from ADR-0028 (QA-004 amendment).

Every refusal is a single SCN-012 report entry: item "Scene file", severity **Cannot open**, no
repair actions, path `$`, problem = the message below. `1` in the messages is
`SceneDocument.currentVersion`.

## Decode errors

| Code | `SceneDecodeError` | When | User-facing message | Report group | If opened (report text) | Covered by |
|---|---|---|---|---|---|---|
| `refusal.empty` | `empty` | zero bytes | The file is empty. | Damaged file | The file is damaged and cannot open. | SceneDecodeErrorTests.testRefusalsHaveExactMessages |
| `refusal.tooLarge` | `tooLarge(bytes:limit:)` | more than 1 MiB | The scene is ⟨bytes⟩ bytes; scenes are at most ⟨limit⟩ bytes. | Damaged file | The file is damaged and cannot open. | SceneHostileInputTests.testOversizePayloadsAreRefusedBeforeParsing |
| `refusal.notJSON` | `notJSON(offset:reason:)` | not JSON | The scene is not valid JSON at byte ⟨offset⟩: ⟨reason⟩. | Damaged file | The file is damaged and cannot open. | SceneDecodeErrorTests.testRefusalsHaveExactMessages |
| `refusal.nestingTooDeep` | `nestingTooDeep(limit:)` | nesting beyond the limit | The scene nests deeper than ⟨limit⟩ levels. | Damaged file | The file is damaged and cannot open. | SceneHostileInputTests.testDeepNestingIsRefusedAtTheDepthLimit |
| `refusal.duplicateKey` | `duplicateKey(path:key:)` | a key twice in one object | ⟨path⟩ has the key "⟨key⟩" twice. | Damaged file | The file is damaged and cannot open. | SceneHostileInputTests.testDuplicateKeysAreRefused |
| `refusal.notAScene` | `notAScene` | not an object, or `format` is not `projectm-ios.scene` | The file is not a projectM-iOS scene. | Damaged file | The file is damaged and cannot open. | matrix row QA-004-M13 |
| `refusal.newerVersion` | `newerVersion(_:)` | an integer version above the current | This scene was saved by a newer version of the app (format version ⟨v⟩); this version reads format version 1. | Unsupported version | Made by a newer version of the app: update the app to open it. | matrix rows QA-004-M04, M05 |
| `refusal.invalidVersion` | `invalidVersion(_:)` | version missing, not a number, not written as an integer, beyond 64 bits, or below the oldest supported with no step | The scene's format version must be a whole number from 1; found ⟨text⟩. (⟨text⟩ is the number as written, `nothing`, `a string`, `null`, `a boolean`, `an array` or `an object`) | Unsupported version | The scene's format version cannot be read, so it cannot open. | matrix rows QA-004-M02, M03, M06-M12 |
| `refusal.tooMany` | `tooMany(what:count:limit:)` | a count limit exceeded | The scene has ⟨count⟩ ⟨what⟩; at most ⟨limit⟩ are allowed. | Damaged file | The file is damaged and cannot open. | SceneDecodeErrorTests.testCountLimitsAreCheckedBeforeTypedDecoding |
| `refusal.malformed` | `malformed(path:reason:)` | a wrong JSON type or missing required field | ⟨path⟩: ⟨reason⟩. | Damaged file | The file is damaged and cannot open. | SceneDecodeErrorTests.testRefusalsHaveExactMessages |
| `refusal.migrationFailed` | `migrationFailed(fromVersion:step:path:reason:)` | an older version the chain cannot bring to the current one (no step, or a step refused it); unreachable with today's empty production chain | The scene's format version ⟨v⟩ cannot be updated to version 1[ (step ⟨step⟩)]: ⟨path⟩: ⟨reason⟩. | Unsupported version | The scene's older format cannot be updated by this version of the app, so it cannot open. | matrix rows QA-004-M15, M16 (test-only chains) |

## Migration errors (mapped by `decode`)

| `SceneMigrationError` | Becomes |
|---|---|
| `notAScene` | `notAScene` |
| `invalidVersion(text)` | `invalidVersion(text)` |
| `newerVersion(v)` | `newerVersion(v)` |
| `missingStep(fromVersion: v)` | `migrationFailed(fromVersion: v, step: nil, path: "$.version", reason: "no step from version v")` |
| `stepFailed(step, fromVersion, path, reason)` | `migrationFailed(fromVersion, step, path, reason)` |

## How each container surfaces a refusal

| Container | Reader | A refusal `e` becomes | Side effects |
|---|---|---|---|
| decode | `SceneDocument.decode` | throws `e` | none |
| repairReport | `SceneRepairReport.open` | one entry `refusal.<case>` as above; `document` nil | none |
| showStore | `ShowStore.scene(_:)`, `ShowStore.load()` | `scene` throws `.unreadable(e)`; `load` keeps the show and lists the scene ID in `unreadableScenes` (the cue shows "Scene missing") | the file is not changed, no backup |
| archive | `SceneArchiveReader.read` | throws `.sceneRefused(e)`, message "The scene could not be read: ⟨e.message⟩" | nothing imported |
| autosave | `SceneAutosaveStore.load` | no document, source none, events `mainUnreadable(e.message)`, then `setAsideNewer("current.scene.newer")` for `newerVersion` only, then `nothingRestored` | only a newer file is renamed aside; nothing else written |
| golden | `GoldenSceneRenderer.document(from:)` | throws `.sceneInvalid(e.message)` | none |

A **migrated** document: decode result `migration.migrated` with the log; the report gains the note
`migration.updated` ("Updated from an older format (version N to M)."); the show store and autosave
read it in memory and write nothing (backups only at the next save, SCN-013); the autosave adds the
event `migrated(from:to:steps:changes:)`; the archive imports the migrated document.
