# Quickstart: VIS-019 validation

1. Package (host): `swift test --package-path Packages/VisualGenerators --filter Cymatic` — pattern, drive, settle, flash and GPU render tests pass in a few seconds.
2. Package (Linux shape): `swift build --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL` and the CPU tests with the same flag.
3. Golden: `swift test --package-path Packages/RenderGoldens --filter Cymatic` (macOS host); the same on the iOS Simulator through `xcodebuild test -scheme RenderGoldens`.
4. App: `CymaticAppTests`, `SettingsTests`, `LibraryBackupAppTests`, `CameraVisualTests`, then `CymaticUITests` (< 30 s) on the agent's own simulator.
5. Repo checks: `test_scripts.py`, `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`.
6. `{device}`: choose Cymatic Lines on D1, play a test tone sweep and music for 30 s each; note frame rate (performance overlay), that tones change the figure and that silence returns it to the cross.
