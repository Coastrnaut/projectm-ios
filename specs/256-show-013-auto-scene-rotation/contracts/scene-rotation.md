# Contract: SHOW-013 Scene rotation

- **C1 Plan.** `SceneRotationPlan(list:folder:disabled:)` builds the collection (R1). `pick(current:seed:step:)`:
  enabled = collection − disabled; 0 → `.idle(.noScenes)`; 1 → `.idle(.oneScene)`; else candidates = enabled − {current}
  (all enabled when current is outside), `.scene(candidates[min(⌊level(seed, step) × n⌋, n − 1)])`. Pure; no clock.
- **C2 Schedule.** `deadline(after: t, settings, barLine: (UInt64) -> UInt64?, reduceFlashing:)`: timer → (t + interval
  s, false). Bars → b = t; N times b = barLine(b) (nil at any point → timer result); while b − t < gap b = barLine(b);
  gap = 15 s with Reduce flashing else 4 s → (b, true).
- **C3 Coordinator.** `setOn(_:)` (on: new seed, step 0, arm); `tick()`: off → nothing; held → deadline cleared,
  status held/showPlaying; no deadline → arm; now ≥ deadline → pick; `.scene` → first cue → `timedGo` (timer) or
  `stepNow(.go)` (bars), step += 1, deadline cleared until `sceneChanged()`; a step that neither moved nor queued
  rearms; `.idle` → status idle, deadline cleared (re-evaluated next tick). `sceneChanged()` rearms from now when on.
- **C4 Storage.** `settings.show.rotation` in `AppSettings.allKeys` (UI-test reset), `LibrarySettingsPolicy.excludedKeys`,
  `LibraryErasePolicy.settingsCategoryKeys`, `run_device_tests.py` ALLOWED_KEYS, and `LibraryBackupAppTests`'s excluded list.
