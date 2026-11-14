# Contract: Cue rehearsal (SHOW-006)

- **C1 Isolation.** Nothing in rehearsal calls `ShowCoordinator.applyScene`, writes `AppSettings`, the autosave or
  scene history, moves the show's position, or draws into a live visual's view, drawable, recording or Save Frame
  source. The panel exists only in the device window's SwiftUI status stack.
- **C2 Target.** Default `.followNext`; `previousTarget()` / `nextTarget()` pick `.picked`; the panel shows
  "Rehearsal · Cue n · <label>" or "Rehearsal · End of show".
- **C3 Picture.** Circular/Linear spectrum → rendered 320 × 180 still (Reduce flashing, safety clamp); else the
  stored SCN-006 picture with "Stored picture" (and "Edits show when the cue runs" when edited), or "No picture yet".
- **C4 Draft.** `setDraft(_:)` re-renders only; `revert()` restores the loaded values; `close()` drops the draft.
- **C5 Save.** `saveDraft()` → `ShowCoordinator.saveRehearsal(cueID:parameters:)`: refused while locked
  (`SceneLock.refusalMessage`), writes the scene file only, announces "Saved to cue n. Shows when the cue runs."
- **C6 Accessibility identifiers.** `showRehearse` (toggle, label "Rehearse next cue", value On/Off),
  `cueRehearsalPanel`, `cueRehearsalTitle`, `cueRehearsalPicture`, `cueRehearsalPrevious`, `cueRehearsalNext`,
  `cueRehearsalEdit`, `cueRehearsalSave`, `cueRehearsalRevert`, `cueRehearsalClose`.
- **C7 Announcements** (cue lane): "Rehearsal on", "Rehearsal off", the save result.
