# Quickstart: FILE-009 Storage Usage Explorer

1. Package tests (host): `swift test --package-path Packages/LocalPortability --filter StorageUsageTests`
   — fixture tree exact content bytes, overhead bound, links, limits, cancellation.
2. Linux shape: `swift test --package-path Packages/LocalPortability --filter StorageUsageTests` in the
   Linux CI lane (allocated-size checks skip where the platform reports no allocation).
3. App: `xcodegen generate`, then `xcodebuild test` on an iOS 27.2 simulator with
   `-only-testing:projectM-iOSTests/StorageLocationsTests -only-testing:projectM-iOSUITests/StorageUsageUITests
   -only-testing:projectM-iOSUITests/SettingsUITests`. Expected: Storage shows the seeded sizes
   (Recordings "1 MB"); after "Add Test Recording" and Refresh, Recordings "3 MB" and the total grows.
4. Privacy: `python3 scripts/check_privacy_manifest.py <Debug .app>` passes with the manifest unchanged.
5. `{device}` D1 with real media: import a photo, a video, an audio track; record a clip; open
   Settings › Storage; values are plausible against iPhone Storage's figure for the app (Documents & Data).
