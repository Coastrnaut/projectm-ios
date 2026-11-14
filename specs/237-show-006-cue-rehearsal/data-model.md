# Data Model: SHOW-006 Cue Rehearsal Mode

Nothing is stored except Save to Cue's rewrite of an existing scene file (format unchanged, no new field).

- **ShowRehearsalTarget** (ShowControl, value): `.followNext` | `.picked(UUID)`.
  - `resolve(in list) -> ShowCue?`: follow-next → `list.nextCue`; picked → that cue, or `list.nextCue` if it is gone.
  - `stepped(by delta: Int, in list) -> ShowRehearsalTarget`: `.picked` of the cue `delta` places from the resolved
    one (clamped to the list; from no resolved cue, the first or last cue); an empty list stays `.followNext`.
- **ShowCueList.nextCue**: the cue Next would reach (nil at the end, empty or all skipped).
- **CueRehearsalDraft** (app): `cueID`, `sceneID`, `visual` (`VisualChoice`), `original` and `values`
  (`SnapshotRenderValues`); `isEdited = values != original`; `parameters` (the seven MOD-001 values for Save).
- **CueRehearsalPicture** (app): `.rendered(CGImage)` | `.stored(UIImage)` | `.none(String)` ("No picture yet",
  "End of show", "The scene could not be read.").
- **CueRehearsalCoordinator** state: `isOn`, `target`, `cue` (resolved), `draft?`, `picture`, `isRendering`,
  `renderCount`, `message?`. Transitions: off → on (load) → edit (render) → save | revert | close (off, draft dropped).
