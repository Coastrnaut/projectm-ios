# Tasks: SHOW-015 Performance Lock

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [contracts/performance-lock.md](contracts/performance-lock.md)
**Tests**: requested by the roadmap acceptance and the brief (coordinator acceptance tests, a UI test under 30 s).

## Phase 1: Foundational (wiring the existing lock)

- [ ] SHOW-015-T01 Wire the SCN-015 lock into `PresetCoordinator` and `LibraryBackupCoordinator` (`sceneLock: SceneLock?`, set in `connectSceneLock()`) in Apps/projectM-iOS/Coordinators/AppCoordinator+SceneLock.swift; no new stored key (data-model: "No new entity or stored key")

## Phase 2: User Story 1 — Nothing can be deleted or reordered mid-show (P1)

- [ ] SHOW-015-T02 [US1] Refusals (contract P1): `refusedByLock()` and `isCollectionEditLocked` in Apps/projectM-iOS/Coordinators/PresetCoordinator.swift guarding `deleteCollection`, `removeFromCollection`, `movePresets`, `moveCollections` (and so `movePreset`, `moveCollection`); `deleteSmartCollection` in Apps/projectM-iOS/Coordinators/PresetCoordinator+Smart.swift; refusal sets `collectionsMessage` to `SceneLock.refusalMessage`
- [ ] SHOW-015-T03 [US1] Storage refusals: `LibraryEraseCoordinator.canStart` false while locked, `openSheet`/`requestErase` refuse (Apps/projectM-iOS/Coordinators/LibraryEraseCoordinator.swift); `restoreTapped` returns false and `requestRestore` refuses, `isRestoreLocked` (Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift); Cancel Erase and Cancel Restore unchanged
- [ ] SHOW-015-T04 [P] [US1] Collection views (contract P3): hide Delete/Remove swipe actions, Move Up/Down and Delete menu items, the matching VoiceOver actions, the Edit button and `onMove` while locked; show `SceneLockNote` — Apps/projectM-iOS/Views/PresetCollectionsView.swift, Apps/projectM-iOS/Views/PresetCollectionView.swift, Apps/projectM-iOS/Views/SmartCollectionViews.swift, Apps/projectM-iOS/Views/PresetBrowserView.swift (`PresetRow` collection actions)
- [ ] SHOW-015-T05 [P] [US1] Scene Folders: hide folder Rename/Move/Delete and scene Move/Tags (swipe, menu, VoiceOver) while locked, disable New Folder, show the note — Apps/projectM-iOS/Views/SceneFoldersView.swift
- [ ] SHOW-015-T06 [P] [US1] Storage views: note beside the disabled Erase Data… and Restore from Backup… — Apps/projectM-iOS/Views/LibraryEraseSection.swift, Apps/projectM-iOS/Views/LibraryBackupSection.swift
- [ ] SHOW-015-T07 [US1] Acceptance tests (S1, S2): with the lock on, cue delete, cue move, folder delete, collection delete, collection reorder, preset reorder in a collection, Remove from Collection and smart collection delete are refused and the show list and collections are unchanged; erase and restore open nothing and record nothing; with the lock off the same calls succeed — Apps/projectM-iOS/Tests/PerformanceLockAcceptanceTests.swift

## Phase 3: User Story 2 — Emergency controls stay available (P1)

- [ ] SHOW-015-T08 [US2] Acceptance test (S3): with the lock on, blackout and restore, Go to cue and Next, and Reduce flashing each act; Cancel Erase stays available — Apps/projectM-iOS/Tests/PerformanceLockAcceptanceTests.swift

## Phase 4: User Story 3 — Unlock deliberately (P1)

- [ ] SHOW-015-T09 [US3] Copy (R7): `SceneLock.unlockMessage` and the Settings footer name collections, erase and restore — Apps/projectM-iOS/Views/SceneLockViews.swift
- [ ] SHOW-015-T10 [US1] [US2] [US3] UI test (S4, under 30 s): lock in the controls; Collections shows the note, no Edit button and no Delete on swipe; back on the visualizer the emergency Black out works and Restore returns; unlock with confirmation removes the badge — Apps/projectM-iOS/UITests/PerformanceLockUITests.swift

## Phase 5: Polish

- [ ] SHOW-015-T11 Regression and repo checks: SceneLock, EmergencyBlackout, collections, SceneFolders, LibraryBackupApp and Settings tests; the six repo scripts; privacy manifest and network symbols on the Debug app; type-check budget — specs/260-show-015-performance-lock/spec.md status
- [ ] SHOW-015-T12 {device} On D1: lock; swipe a cue and a collection (no Delete); tap the emergency blackout and restore; unlock with confirmation — docs/test-reports (owner run)

## Dependencies

T01 → T02, T03 → T04-T07 → T08 → T09 → T10 → T11. T04, T05, T06 touch different files and can run in parallel.

## Implementation Strategy

MVP is User Story 1 (T01-T07); US2 adds only tests (the emergency paths are untouched); US3 is copy plus the UI test.
