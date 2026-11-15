# Quickstart: SHOW-013 Auto Scene Rotation

1. Package: `swift test --package-path Packages/ShowControl --filter SceneRotationTests` — 1000 seeded steps exclude
   disabled scenes and never repeat; same seed same sequence; idle cases; schedule timer and bars.
2. App: `xcodegen generate`, `build-for-testing` on "SHOW13 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/SceneRotationAcceptanceTests`.
3. UI: `-only-testing:projectM-iOSUITests/SceneRotationUITests` (< 30 s): the seeded show changes scene by itself twice.
4. Device `{device}` (D1): a show with 4+ scenes, tap 120 BPM, Settings › Rotate scenes on, Bars, 4 bars; scenes change
   on the downbeat every 8 s, never the same scene twice, and a disabled scene never shows.
