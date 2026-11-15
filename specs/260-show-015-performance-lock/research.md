# Research: SHOW-015 Performance Lock

- **SHOW-015-D1 — One lock.** Decision: reuse SCN-015's `SceneLock` as the performance lock. Rationale: the roadmap rows
  overlap ("prevent accidental editing while in performance mode"); SCN-015 already blocks the show editor's delete and
  reorder, keeps blackout/cues/Reduce flashing, persists and confirms unlock. Two locks would mean two keys, two badges
  and a false sense of safety when only one is on. Alternatives: a separate "Performance lock" with its own key (rejected:
  duplicate state); renaming the control (rejected: breaks SCN-015's labels and tests for no user gain).
- **SHOW-015-D2 — Refuse at the write.** Decision: each owning coordinator calls the lock's `refusesEdit()`; views only
  hide. Rationale: SCN-015-D1's choke point; keyboard, VoiceOver and stale alerts all reach the coordinator.
- **SHOW-015-D3 — Hide row gestures, disable buttons.** Decision: swipe actions, menu items, VoiceOver actions and Edit
  are hidden (a disabled swipe action cannot explain itself); toolbar/Settings buttons are disabled; each screen shows
  `SceneLockNote`. Alternatives: alert on tap (rejected: an extra modal mid-show).
- **SHOW-015-D4 — Additive edits stay.** Decision: New Collection, Add to Collection, rename collection and smart rules
  stay allowed. Rationale: the row asks to block delete/reorder; additive edits lose nothing and are needed to build a
  set list. Scene/folder renames stay locked (SCN-015's scope, unchanged).
- **SHOW-015-D5 — Storage.** Decision: Erase Data… and Restore from Backup… refused; Cancel of a pending request kept;
  media folder restore (adds files) kept.
- **SHOW-015-D6 — Unlock and persistence unchanged.** Decision: SCN-015's confirmation and persisted key. Rationale: a
  crash mid-show must not drop protection; a confirmation is reachable by every assistive technology.
