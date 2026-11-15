# Quickstart: VIS-017 validation

1. Package (host): `swift test --package-path Packages/VisualGenerators --filter SignedDistance` — scene, drive, step-cap, finiteness, flash and GPU render tests pass in a few seconds.
2. Package (Linux shape): `swift build --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL` and the CPU tests with the same flag.
3. Golden: `swift test --package-path Packages/RenderGoldens --filter SignedDistance` (macOS host); the same on the iOS Simulator through `xcodebuild test -scheme RenderGoldens`.
4. App: `SignedDistanceAppTests`, `SettingsTests`, `LibraryBackupAppTests`, `CameraVisualTests`, then `SignedDistanceUITests` (< 30 s) on the agent's own simulator.
5. Repo checks: `test_scripts.py`, `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`.
6. `{device}`: choose SDF Shapes on D1 at each quality, watch for 30 s with music; note frame rate (performance overlay) and look.
