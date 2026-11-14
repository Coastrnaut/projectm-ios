# Quickstart: validating VIS-004

Prerequisites: the worktree's `Build` symlink (xcframeworks), `xcodegen generate`, the presets
(`git submodule update --init --depth 1 Vendor/presets/*`), the agent simulator "VIS4 iPhone 17"
(iOS 27.2).

1. Package (host, Metal included):
   `swift test --package-path Packages/VisualGenerators --filter 'Lissajous|WaveformTapStereo'`
   → shape metrics (in-phase ratio < 0.02, quadrature > 0.95), stability, gain, persistence, flash.
2. Linux shape: `swift build --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL
   -Xswiftc -DANALYSIS_NO_ACCELERATE` (and `swift test … --filter Lissajous` the same way).
3. Goldens: `swift test --package-path Packages/RenderGoldens --filter Lissajous` (record once with
   `GOLDEN_RECORD=1`; the iOS Simulator class through `xcodebuild test` with
   `TEST_RUNNER_GOLDEN_RECORD=1`).
4. App: `LissajousAppTests` (settings, keys, host style and persistence clamp) and
   `LissajousUITests` (under 30 s) on VIS4.
5. Repo checks: compliance, docs, motion policy, permission catalog, status events, script tests.

Device (`{device}`): choose Lissajous on D1 with stereo music and check frame time with the
performance overlay.
