# Data Model: FILE-003 Import Dry Run

## PresetArchiveImportPlan (PresetLibrary)

| Field | Type | Notes |
|---|---|---|
| archiveSHA256 | String | SHA-256 of the archive bytes |
| policy | PresetArchiveConflictPolicy | `keepBoth` (default) or `skip` |
| refusal | String? | The reader's message when the whole archive is refused; then `entries` is empty |
| entries | [PresetArchivePlanEntry] | Archive order |
| counts | derived | new, identical, nameConflicts, idConflicts, refused, toInstall |
| missingLicense | derived [String] | Final names of presets to install with no licence lines (copies of Included presets excepted) |
| totalBytes | derived Int | Sum of byte counts of presets to install |
| actions | derived [PresetArchiveAction] | `.add(id:name:)` in archive order |

## PresetArchivePlanEntry

| Field | Type | Notes |
|---|---|---|
| incomingID, incomingName | String | From the manifest (name cleaned) |
| sha256 | String | Text hash |
| byteCount | Int | |
| kind | PresetArchiveEntryKind | `new`, `identical(existingName)`, `nameConflict(existingName)`, `idConflict(existingName)`, `refused(PresetArchiveRefusal)` |
| install | PresetArchiveAction? | Final id and name, or nil (skipped or refused) |
| hasLicense | Bool | Licence lines found by the validator, or a copy of an Included preset |

## PresetArchiveRefusal

`inQuarantine`, `blocked`, `builtIn(name:pack:)`, `failsChecks(message)`, `libraryFull`; each with a
message.

## PresetArchiveInstallOutcome

`installed([UserPreset])`, `changed(PresetArchiveImportPlan)`, `refused(String)`.

## LibraryTreeSnapshot

`files: [String: String]` (relative path → SHA-256 hex), `directories: Set<String>`, `digest`
(SHA-256 of the sorted listing). Missing roots are recorded as absent.

## SceneArchiveImportPlan (app)

| Field | Type | Notes |
|---|---|---|
| archiveSHA256 | String | |
| currentPhotoID, currentVideoID | String? | Seen at planning |
| refusal | SceneArchiveServiceError? | |
| media | [(key, type, fileExtension, byteCount)] | |
| replacesPhoto, replacesVideo | Bool | The conflict: the stores keep one of each |
| repairEntries | [SceneRepairReport.Entry] | After the install |
| licenses | [String] | Always empty: scenes carry no licence data |
| totalBytes | Int | |
| steps | [SceneArchiveImportStep] | `verified`, `staged(path)`…, `adopted(type)`…, `madeCurrent(type)`… |

## State: the preview (app)

```
idle ──pick .zip──▶ previewing(plan) ──Cancel──▶ idle (nothing written)
previewing ──policy──▶ previewing(re-planned)
previewing ──Install──▶ installing ──ok──▶ idle (announced)
                                   ──changed──▶ previewing(new plan, changed sentence)
                                   ──failed──▶ previewing(plan, "Nothing was installed.")
```
