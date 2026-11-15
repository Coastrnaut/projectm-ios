# Data Model: SHOW-015 Performance Lock

No new entity or stored key.

- **Scene lock** (SCN-015, existing): `settings.scene.locked` (Bool, absent = unlocked). Persisted on the device,
  excluded from library backups, in `ALLOWED_KEYS` and the UI-test reset (unchanged).
- New read-only derived values: `PresetCoordinator.isCollectionEditLocked`, `LibraryBackupCoordinator.isRestoreLocked`,
  `LibraryEraseCoordinator.canStart` (now also false while locked).
- State transitions: unlocked → locked (one action); locked → unlocked (confirmation). Unchanged.
