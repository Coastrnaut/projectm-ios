# Quickstart: validate PRE-016

Run from the worktree root on the Mac.

1. Package tests (host, under 1 minute each):
   ```bash
   swift test --package-path Packages/PresetLibrary --filter PresetOverride
   swift test --package-path Packages/LibraryBackup --filter PresetOverride
   ```
   Expected: overlay, clamping, allow-list, document, store-relaunch, reset-bytes-identical and backup
   round-trip tests pass.
2. App: `xcodegen generate`, then `build-for-testing` for scheme `projectM-iOS` on simulator
   "PRE16 iPhone 17" (iOS 27.2) and `test-without-building -only-testing:projectM-iOSTests/PresetOverridesAcceptanceTests
   -only-testing:projectM-iOSUITests/PresetOverridesUITests`.
   Expected: acceptance (loaded data carries overrides; Included file byte-identical; reset loads the
   original bytes; overrides survive a new store) and the UI test (adjust Zoom, reset, label back to the
   original) pass, the UI test in under 30 s.
3. Repo checks: `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
   `check_status_events`, `test_scripts`.

Manual (optional, simulator, not evidence): touch and hold a preset → Adjust Parameters… → move
Decay; the preset on screen reloads; Reset to Original restores it.
