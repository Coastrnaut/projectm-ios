# Contract A1: PresetCoordinator audition API (PRE-010)

Main actor. In memory only.

| Member | Behavior |
|---|---|
| `audition: PresetAudition?` | Observable state (data-model). |
| `onScreen: IndexedPreset?` | The preview on screen, else `current`. |
| `canPreview(_:) -> Bool` | Playable, not flagged while Reduce flashing is on, not `onScreen`. |
| `preview(_:from:) async` | Starts or continues an audition; loads the preset; on success `showing` = it and announces "Previewing <name>."; on failure the screen keeps what it had, `notice` = "<name> could not be previewed.", the preset is excluded for the session, announced. Never writes `lastPresetID`, scope, history, favorites, tags, collections or scene inputs. |
| `keepAudition() async -> Bool` | With a shown preview and nothing loading: ends the audition, sets the scope to its list, commits it like `select` without loading, announces "Kept <name>."; returns true (the browser closes). |
| `cancelAudition() async` | Ends the audition; if anything was previewed (or is loading), loads the original again (no stored write) and announces "Preview cancelled. <original> is back."; with only a notice, clears it silently. |
| `select(_:in:)` | Unchanged contract; a successful load also ends any audition without a restore (R8). |

Texts: `PresetCoordinator.previewingText(_:)`, `keptText(_:)`, `cancelledText(_:)`,
`previewFailedText(_:)`, `previewingLabel` (", previewing").

UI identifiers: `auditionBar`, `auditionName`, `auditionKeep`, `auditionCancel`, `auditionNotice`,
`auditionNoticeOK`; row menu item and swipe `previewPreset`.
