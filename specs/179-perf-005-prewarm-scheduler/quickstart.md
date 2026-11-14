# Quickstart: PERF-005

1. Core (macOS host; also Linux in CI): `swift test --package-path Packages/PresentationLifecycle --filter Prewarm` — acceptance A → B → C jump, eviction order, executor spy, pause, preset forwarding.
2. Photo adoption (host Metal): `swift test --package-path Packages/Compositor --filter ImageLayerPrewarm`.
3. App (simulator "PERF5"): `xcodebuild build-for-testing` then `test-without-building -only-testing:projectM-iOSTests/MediaPrewarmAppTests` — stepping cues prewarms the next scene's photo with one decode and applying it reuses the decoded picture.
4. `{device}`: on D1, step a photo show and confirm no frame-rate change and the first frame shows the picture (not run here).
