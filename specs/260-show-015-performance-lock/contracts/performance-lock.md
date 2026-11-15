# Contract: SHOW-015 Performance Lock

P1. While `SceneLock.isLocked`, these calls change nothing, set the lock's refusal (count, message, announcement) and,
where the screen has one, its message: `ShowCoordinator.remove/move/deleteFolder/moveFolder/moveScene` (SCN-015,
unchanged); `PresetCoordinator.deleteCollection`, `deleteSmartCollection`, `moveCollections`, `moveCollection`,
`movePresets`, `movePreset`, `removeFromCollection` (`collectionsMessage` = `SceneLock.refusalMessage`);
`LibraryEraseCoordinator.openSheet`, `requestErase`; `LibraryBackupCoordinator.restoreTapped` (returns false),
`requestRestore`.

P2. While locked, these act as when unlocked and never consult the lock: emergency blackout/B key and OUT-010 Black
out/Restore, `ShowCoordinator.next/previous/go`, `AppSettings.reduceFlashing`, `LibraryEraseCoordinator.cancelErase`,
`LibraryBackupCoordinator.cancelRestore`, `PresetCoordinator.createCollection/addToCollection/renameCollection`.

P3. UI identifiers: the lock note `sceneLockNote` on Collections, a collection, Scene Folders and Storage while locked;
`libraryEraseButton` and Restore from Backup disabled; no `Delete` swipe action and no Edit button on the collections
list; `newCollection` stays enabled.

P4. Unlock: SCN-015's "Unlock scene?" confirmation (`sceneUnlockConfirm`); the lock persists across relaunch.
