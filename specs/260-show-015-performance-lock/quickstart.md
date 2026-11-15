# Quickstart: SHOW-015 Performance Lock

Simulator "SHOW15 iPhone 17" (iOS 27.2). Behavior evidence only; no device claim.

1. `xcodegen generate`, then `xcodebuild build-for-testing` (scheme `projectM-iOS`, derived data in the worktree,
   `CODE_SIGNING_ALLOWED=NO`).
2. Acceptance (S1-S3): `test-without-building -only-testing:projectM-iOSTests/PerformanceLockAcceptanceTests` — lock on:
   8 delete/reorder attempts refused, show and collections unchanged; erase/restore refused; blackout, Go, Reduce
   flashing act; lock off: the same attempts succeed.
3. UI (S4, under 30 s): `-only-testing:projectM-iOSUITests/PerformanceLockUITests` — lock, open Collections: no Delete
   swipe, no Edit; back to the visualizer: emergency Black out works; restore; unlock with confirmation.
4. Regression: `SceneLockAcceptanceTests`, `SceneLockUITests`, `EmergencyBlackoutTests`, collections tests,
   `LibraryBackupAppTests`, `SettingsTests`.
5. `{device}` (SHOW-015-T12): on D1, lock, try swipe-delete on a cue and a collection, tap the emergency blackout,
   unlock.
