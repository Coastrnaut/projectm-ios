# Quickstart: UIX-013 Scene Performance HUD

Prerequisites: `xcodegen generate`; preset submodules; `Build` symlink; private simulator (iOS 27.2).

1. Unit and acceptance tests: `xcodebuild test-without-building -only-testing:projectM-iOSTests/SceneHUDAppTests`
   (content texts C1, preference C5, exclusion C4 for the external window, recording and saved frame).
2. Key lists: `-only-testing:projectM-iOSTests/LibraryBackupAppTests`.
3. UI: `-only-testing:projectM-iOSUITests/SceneHUDUITests` (show seed; HUD lines, cue step, placement C3).
4. Repo checks: `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`.
5. `{device}` On D1: turn on Settings → Show HUD with the five-cue show; read the four lines, step a cue, connect an external display or record: the HUD is not in the output.
