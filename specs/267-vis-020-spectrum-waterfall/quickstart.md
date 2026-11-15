# Quickstart: VIS-020 Spectrum Waterfall

1. `swift test --package-path Packages/VisualGenerators --filter Waterfall` — history order over 60 s and past the
   wrap, fixed storage, flash, GPU order (host GPU).
2. Same with `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` (Linux shape).
3. `swift test --package-path Packages/RenderGoldens --filter Waterfall` — golden on the host; the simulator golden
   through `xcodebuild test` on "VIS20 iPhone 17".
4. App: `WaterfallAppTests`, `SettingsTests`, `CameraVisualTests`, `WaterfallUITests` on "VIS20 iPhone 17".
5. `{device}`: on D1 with music, choose Spectrum Waterfall; check the frame rate on the PERF-001 overlay and that the
   picture falls steadily, newest at the top.
