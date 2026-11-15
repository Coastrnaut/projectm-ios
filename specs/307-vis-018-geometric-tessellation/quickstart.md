# Quickstart: VIS-018 validation

1. Package (host): `swift test --package-path Packages/VisualGenerators --filter Tessellation` — alignment (CPU), drive, flash and GPU render tests pass in a few seconds.
2. Package (Linux shape): the same with `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` (GPU tests compile out).
3. Full alignment sweep on demand: `VIS018_ALIGNMENT_SWEEP=1 swift test --package-path Packages/VisualGenerators --filter TessellationAlignmentTests/testFullPixelSweep`.
4. Golden: `swift test --package-path Packages/RenderGoldens --filter TessellationGolden` (macOS host); the same on the iOS Simulator through `xcodebuild test -scheme RenderGoldens`.
5. App: `TessellationAppTests`, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, `CameraVisualTests`, then `TessellationUITests` (< 30 s) on the agent's own simulator.
6. Repo checks: `test_scripts.py`, `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`.
7. `{device}`: choose Tessellation on D1, D2 (iPad 4:3) and an external display if available; step the tile count 2 → 16 in portrait and landscape; confirm the centre stays put and seams stay straight; note the frame rate on the performance overlay.
