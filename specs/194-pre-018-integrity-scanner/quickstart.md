# Quickstart: PRE-018

1. `swift test --package-path Packages/PresetLibrary --filter PresetIntegrity` — scanner, inventory,
   relink, bounds (host; also Linux in CI).
2. App acceptance: `xcodebuild test-without-building ... -only-testing:projectM-iOSTests/LibraryIntegrityAcceptanceTests`
   on "PRE18 iPhone 17": broken fixture → 8 issues once each; Fix All Safe → rescan has 0 dangling, 3 left.
3. UI: `-only-testing:projectM-iOSUITests/LibraryCheckUITests` (< 30 s): launch with
   `-uitestResetNotice -uitestBrokenLibrary`, My Presets → Check Library → Check Library → issues shown.
Simulator results are not device evidence.
